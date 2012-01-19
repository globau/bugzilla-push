# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

# boilerplate

package Bugzilla::Extension::Push;

use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Constants;
use Bugzilla::Extension::Push::Message;
use Bugzilla::Extension::Push::Serialise;
use Bugzilla::Extension::Push::Util;
use Bugzilla::Install::Filesystem;

use JSON qw(-convert_blessed_universally);
use Scalar::Util 'blessed';
use Storable 'dclone';

our $VERSION = '1';

use constant DEBUGGING => 1;

#
# deal with creation and updated events
#

sub _object_created {
    my ($self, $args) = @_;

    my $object = _get_object_from_args($args);
    return unless $object;
    return unless _should_push($object);
    return unless is_public($object);

    $self->_push('create', $object, { timestamp => $args->{'timestamp'} });
}

sub _object_modified {
    my ($self, $args) = @_;

    my $changes = $args->{'changes'} || {};
    return unless scalar keys %$changes;

    my $object = _get_object_from_args($args);
    return unless $object;
    return unless _should_push($object);
    my $is_public = is_public($object);

    if (!$is_public) {
        # when a bug is changed from public to private, push a fake update with just
        # the group changes, so connectors can remove now-private bugs if required
        # we can't use user->can_see_bug(old_bug) as that works on IDs, and the
        # bug has already been updated, so for now assume that a bug without
        # groups is public.
        if ($object->isa('Bugzilla::Bug') && !@{$args->{'old_bug'}->groups_in}) {
            # note the group changes only
            $changes = {
                'bug_group' => $changes->{'bug_group'}
            };
            # return the original bug object, so we don't leak any security
            # sensitive information.  due to how $user->can_see_bug_works,
            # is_public() on the old_bug will still return true
            $object = $args->{'old_bug'};
        } else {
            # never push non-public objects
            return;
        }
    }

    # make flagtypes changes easier to process
    if (exists $changes->{'flagtypes.name'}) {
        _split_flagtypes($changes);
    }

    # TODO split group changes?

    # send an individual message for each change
    foreach my $field_name (keys %$changes) {
        my $change = {
            field     => $field_name,
            removed   => $changes->{$field_name}[0],
            added     => $changes->{$field_name}[1],
            timestamp => $args->{'timestamp'},
        };

        $self->_push('modify', $object, $change);
    }
}

sub _get_object_from_args {
    my ($args) = @_;
    return get_first_value($args, qw(object bug flag group));
}

sub _should_push {
    my ($object) = @_;
    my $class = blessed($object);
    return grep { $_ eq $class } qw(Bugzilla::Bug Bugzilla::Attachment);
}

# changes to bug flags are presented in a single field 'flagtypes.name' split
# into individual fields
sub _split_flagtypes {
    my ($changes) = @_;

    my @removed = _split_flagtype($changes->{'flagtypes.name'}->[0]);
    my @added = _split_flagtype($changes->{'flagtypes.name'}->[1]);
    delete $changes->{'flagtypes.name'};

    foreach my $ra (@removed, @added) {
        $changes->{$ra->[0]} = ['', ''];
    }
    foreach my $ra (@removed) {
        my ($name, $value) = @$ra;
        $changes->{$name}->[0] = $value;
    }
    foreach my $ra (@added) {
        my ($name, $value) = @$ra;
        $changes->{$name}->[1] = $value;
    }
}

sub _split_flagtype {
    my ($value) = @_;
    my @result;
    foreach my $change (split(/, /, $value)) {
        my $requestee = '';
        if ($change =~ s/\(([^\)]+)\)$//) {
            $requestee = $1;
        }
        my ($name, $value) = $change =~ /^(.+)(.)$/;
        $value .= " ($requestee)" if $requestee;
        push @result, [ "flag.$name", $value ];
    }
    return @result;
}

# changes to attachment flags come in via flag_end_of_update which has a
# completely different structure for reporting changes than
# object_end_of_update.  this morphs flag to object updates.
sub _morph_flag_updates {
    my ($args) = @_;

    my @removed = _morph_flag_update($args->{'old_flags'});
    my @added = _morph_flag_update($args->{'new_flags'});
    delete $args->{'old_flags'};
    delete $args->{'new_flags'};

    my $changes = {};
    foreach my $ra (@removed, @added) {
        $changes->{$ra->[0]} = ['', ''];
    }
    foreach my $ra (@removed) {
        my ($name, $value) = @$ra;
        $changes->{$name}->[0] = $value;
    }
    foreach my $ra (@added) {
        my ($name, $value) = @$ra;
        $changes->{$name}->[1] = $value;
    }

    foreach my $flag (keys %$changes) {
        if ($changes->{$flag}->[0] eq $changes->{$flag}->[1]) {
            delete $changes->{$flag};
        }
    }

    $args->{'changes'} = $changes;
}

sub _morph_flag_update {
    my ($values) = @_;
    my @result;
    foreach my $change (@$values) {
        $change =~ s/^[^:]+://;
        my $requestee = '';
        if ($change =~ s/\(([^\)]+)\)$//) {
            $requestee = $1;
        }
        my ($name, $value) = $change =~ /^(.+)(.)$/;
        $value .= " ($requestee)" if $requestee;
        push @result, [ "flag.$name", $value ];
    }
    return @result;
}

#
# serialise and insert into the table
#

sub _push {
    my ($self, $message_type, $object, $changes) = @_;
    my $rh;

    # serialise the object
    my ($rh_object, $name) = _serialiser()->object_to_hash($object);
    if (!$rh_object) {
        if (DEBUGGING) {
            die "empty hash from serialiser ($message_type $object)\n";
        }
        warn "empty hash from serialiser ($message_type $object)\n";
        return;
    }
    $rh->{$name} = $rh_object;

    # add in the events hash
    my $rh_event = _serialiser()->changes_to_event($changes);
    return unless $rh_event;
    $rh_event->{'action'} = $message_type;
    $rh_event->{'target'} = $name;
    $rh->{'event'} = $rh_event;

    # insert into push table
    Bugzilla::Extension::Push::Message->create({
        payload => $self->_to_json($rh)
    });

    if (DEBUGGING) {
        open(FH, '>>' . bz_locations()->{datadir} . '/push.log');
        print FH $self->_to_json($rh) . "\n\n";
        close FH;
    }
}

#
# helpers
#

sub _serialiser {
    my ($self) = @_;
    my $cache = Bugzilla->request_cache->{'push'};
    if (!exists $cache->{'seriliaser'}) {
        $cache->{'serialiser'} = Bugzilla::Extension::Push::Serialise->new();
    }
    return $cache->{'serialiser'};
}

sub _to_json {
    my ($self, $rh) = @_;
    my $cache = Bugzilla->request_cache->{'push'};
    my $json;
    if (!exists $cache->{'json'}) {
        $json = JSON->new();
        $json->shrink(1);
        $json->canonical(1) if DEBUGGING;
        $cache->{'json'} = $json;
    } else {
        $json = $cache->{'json'};
    }
    
    return DEBUGGING
        ? $json->pretty->encode($rh)
        : $json->encode($rh);
}

#
# update/create hooks
#

sub object_end_of_create {
    my ($self, $args) = @_;
    return unless Bugzilla->params->{'push-enabled'} eq 'on';

    # it's better to process objects from a non-generic end_of_create where
    # possible; don't process them here to avoid duplicate messages
    my $object = _get_object_from_args($args);
    return if !$object ||
        $object->isa('Bugzilla::Bug');

    $self->_object_created($args);
}

sub object_end_of_update {
    my ($self, $args) = @_;
    return unless Bugzilla->params->{'push-enabled'} eq 'on';

    # it's better to process objects from a non-generic end_of_update where
    # possible; don't process them here to avoid duplicate messages
    my $object = _get_object_from_args($args);
    return if !$object ||
        $object->isa('Bugzilla::Bug') ||
        $object->isa('Bugzilla::Flag');

    $self->_object_modified($args);
}

# process bugs once they are fully formed
# object_end_of_update is triggered while a bug is being created
sub bug_end_of_create {
    my ($self, $args) = @_;
    return unless Bugzilla->params->{'push-enabled'} eq 'on';
    $self->_object_created($args);
}

sub bug_end_of_update {
    my ($self, $args) = @_;
    return unless Bugzilla->params->{'push-enabled'} eq 'on';
    $self->_object_modified($args);
}

sub flag_end_of_update {
    my ($self, $args) = @_;
    return unless Bugzilla->params->{'push-enabled'} eq 'on';
    _morph_flag_updates($args);
    $self->_object_modified($args);
}

#
# installation/config hooks
#

sub db_schema_abstract_schema {
    my ($self, $args) = @_;
    $args->{'schema'}->{'push'} = {
        FIELDS => [
            id => {
                TYPE => 'MEDIUMSERIAL',
                NOTNULL => 1,
                PRIMARYKEY => 1,
            },
            push_ts => {
                TYPE => 'DATETIME',
                NOTNULL => 1,
            },
            payload => {
                TYPE => 'LONGTEXT',
                NOTNULL => 1,
            },
        ],
    };
    $args->{'schema'}->{'push_backlog'} = {
        FIELDS => [
            id => {
                TYPE => 'MEDIUMSERIAL',
                NOTNULL => 1,
                PRIMARYKEY => 1,
            },
            push_ts => {
                TYPE => 'DATETIME',
                NOTNULL => 1,
            },
            payload => {
                TYPE => 'LONGTEXT',
                NOTNULL => 1,
            },
            connector => {
                TYPE => 'TINYTEXT',
                NOTNULL => 1,
            },
            attempt_ts => {
                TYPE => 'DATETIME',
            },
            attempts => {
                TYPE => 'INT2',
                NOTNULL => 1,
            },
        ],
    };
}

sub config_add_panels {
    my ($self, $args) = @_;
    my $modules = $args->{'panel_modules'};
    $modules->{'push'} = 'Bugzilla::Extension::Push::Params';
}

sub install_filesystem {
    my ($self, $args) = @_;
    my $files = $args->{'files'};

    my $extensionsdir = bz_locations()->{'extensionsdir'};
    my $scriptname = $extensionsdir . "/Push/bin/bugzilla-pushd.pl";

    $files->{$scriptname} = {
        perms => Bugzilla::Install::Filesystem::WS_EXECUTE
    };
}

__PACKAGE__->NAME;

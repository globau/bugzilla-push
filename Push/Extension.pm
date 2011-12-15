# boilerplate

package Bugzilla::Extension::Push;

use strict;
use warnings;

use base qw(Bugzilla::Extension);

use Bugzilla::Extension::Push::Util;
use Bugzilla::Extension::Push::Serialise;

use JSON qw(-convert_blessed_universally);
use Scalar::Util 'blessed';

our $VERSION = '1';

#
# deal with creation and updated events
#

sub _object_created {
    my ($self, $args) = @_;

    my $object = _get_object_from_args($args);
    return unless $object;
    return unless _should_push($object);
    return unless is_public($object, 0);

    $self->_push('create', $object, { timestamp => $args->{'timestamp'} });
}

sub _object_modified {
    my ($self, $args) = @_;

    my $changes = $args->{'changes'} || {};
    return unless scalar keys %$changes;

    my $object = _get_object_from_args($args);
    return unless $object;
    return unless _should_push($object);
    return unless is_public($object, 1);

    # make flagtypes changes easier to process
    if (exists $changes->{'flagtypes.name'}) {
        _split_flagtypes($changes);
    }

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
# serialise and insert into the queue
#

sub _push {
    my ($self, $message_type, $object, $changes) = @_;
    my $rh;

    # serialise the object
    my ($rh_object, $name) = _serialiser()->object_to_hash($object);
    if (!$rh_object) {
        # XXX this die should become a warn when out of dev
        die "empty hash from serialiser ($message_type $object)\n";
        return;
    }
    $rh->{$name} = $rh_object;

    # add in the events hash
    my $rh_event = _serialiser()->changes_to_event($changes);
    return unless $rh_event;
    $rh_event->{'action'} = $message_type;
    $rh_event->{'target'} = $name;
    $rh->{'event'} = $rh_event;

    # TODO insert into a table instead :)
    open(FH, ">>data/pulse");
    print FH $self->_to_json($rh);
    print FH "\n\n";
    close FH;
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
        $json->canonical(1); # debugging only XXX
        $cache->{'json'} = $json;
    } else {
        $json = $cache->{'json'};
    }
    return $json->pretty->encode($rh); # debugging only XXX
    return $json->encode($rh);
}

#
# hooks
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
    _morph_flag_updates($args);
    $self->_object_modified($args);
}

sub config_add_panels {
    my ($self, $args) = @_;
    my $modules = $args->{'panel_modules'};
    $modules->{'push'} = 'Bugzilla::Extension::Push::Params';
}

__PACKAGE__->NAME;

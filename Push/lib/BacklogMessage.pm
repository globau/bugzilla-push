# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::BacklogMessage;

use strict;
use warnings;

use base 'Bugzilla::Object';

use Bugzilla;
use Bugzilla::Error;
use Bugzilla::Util;

#
# initialisation
#

use constant DB_TABLE => 'push_backlog';
use constant DB_COLUMNS => qw(
    id
    message_id
    push_ts
    payload
    connector
    attempt_ts
    attempts
);
use constant UPDATE_COLUMNS => qw(
    attempt_ts
    attempts
);
use constant LIST_ORDER => 'push_ts';
use constant VALIDATORS => {
    payload   => \&_check_payload,
    connector => \&_check_connector,
    attempts  => \&_check_attempts,
};

#
# constructors
#

sub create_from_message {
    my ($class, $message, $connector) = @_;
    my $self = $class->create({
        message_id => $message->id,
        push_ts => $message->push_ts,
        payload => $message->payload,
        connector => $connector->name,
        attempt_ts => undef,
        attempts => 0,
    });
    return $self;
}

#
# accessors
#

sub message_id { return $_[0]->{'message_id'}  }
sub push_ts    { return $_[0]->{'push_ts'};    }
sub payload    { return $_[0]->{'payload'};    }
sub connector  { return $_[0]->{'connector'};  }
sub attempt_ts { return $_[0]->{'attempt_ts'}; }
sub attempts   { return $_[0]->{'attempts'};   }

sub attempt_time {
    my ($self) = @_;
    if (!exists $self->{'attempt_time'}) {
        $self->{'attempt_time'} = datetime_from($self->attempt_ts)->epoch;
    }
    return $self->{'attempt_time'};
}

#
# mutators
#

sub inc_attempts {
    my ($self) = @_;
    $self->{attempt_ts} = Bugzilla->dbh->selectrow_array('SELECT NOW()');
    $self->{attempts} = $self->{attempts} + 1;
    $self->update;
}

#
# validators
#

sub _check_payload {
    my ($invocant, $value) = @_;
    length($value) || ThrowCodeError('push_invalid_payload');
    return $value;
}

sub _check_connector {
    my ($invocant, $value) = @_;
    Bugzilla->push_ext->connectors->exists($value) || ThrowCodeError('push_invalid_connector');
    return $value;
}

sub _check_attempts {
    my ($invocant, $value) = @_;
    return $value || 0;
}

1;


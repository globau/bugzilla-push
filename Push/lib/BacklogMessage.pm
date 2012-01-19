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

#
# initialisation
#

use constant DB_TABLE => 'push_backlog';
use constant DB_COLUMNS => qw(
    id
    push_ts
    payload
    connector
    attempt_ts
    attempts
);
use constant LIST_ORDER => 'push_ts';
use constant VALIDATORS => {
    payload   => \&_check_payload,
    connector => \&_check_connector,
};

#
# constructors
#

sub create_from_message {
    my ($class, $message, $connector) = @_;
    my $now = Bugzilla->dbh->selectrow_array('SELECT NOW()');
    my $self = $class->create({
        push_ts => $message->push_ts,
        payload => $message->payload,
        connector => $connector->name,
        attempt_ts => $now,
        attempts => 1,
    });
}

#
# accessors
#

sub push_ts    { return $_[0]->{'push_ts'};    }
sub payload    { return $_[0]->{'payload'};    }
sub connector  { return $_[0]->{'connector'};  }
sub attempt_ts { return $_[0]->{'attempt_ts'}; }
sub attempts   { return $_[0]->{'attempts'};   }

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
    # XXX check the connector
    return $value;
}

1;


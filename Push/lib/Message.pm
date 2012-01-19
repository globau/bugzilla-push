# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Message;

use strict;
use warnings;

use base 'Bugzilla::Object';

use Bugzilla;
use Bugzilla::Error;

#
# initialisation
#

use constant DB_TABLE => 'push';
use constant DB_COLUMNS => qw(
    id
    push_ts
    payload
);
use constant LIST_ORDER => 'push_ts';
use constant VALIDATORS => {
    push_ts => \&_check_push_ts,
    payload => \&_check_payload,
};

#
# accessors
#

sub push_ts { return $_[0]->{'push_ts'}; }
sub payload { return $_[0]->{'payload'}; }

#
# validators
#

sub _check_push_ts {
    my ($invocant, $value) = @_;
    $value ||= Bugzilla->dbh->selectrow_array('SELECT NOW()');
    return $value;
}

sub _check_payload {
    my ($invocant, $value) = @_;
    length($value) || ThrowCodeError('push_invalid_payload');
    return $value;
}

1;


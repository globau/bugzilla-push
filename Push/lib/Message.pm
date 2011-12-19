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
# validators
#

sub _check_push_ts {
    my $dbh = Bugzilla->dbh;
    return $dbh->selectrow_array('SELECT NOW()');
}

sub _check_payload {
    my ($invocant, $value) = @_;
    length($value) || ThrowCodeError('push_invalid_payload');
    return $value;
}

1;


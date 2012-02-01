# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Constants;

use strict;
use base 'Exporter';

our @EXPORT = qw(
    PUSH_RESULT_OK
    PUSH_RESULT_TRANSIENT
    PUSH_RESULT_ERROR
    push_result_to_string

    POLL_INTERVAL_SECONDS
);

use constant PUSH_RESULT_OK => 1;
use constant PUSH_RESULT_TRANSIENT => 2;
use constant PUSH_RESULT_ERROR => 3;

sub push_result_to_string {
    my ($result) = @_;
    return 'OK'              if $result == PUSH_RESULT_OK;
    return 'TRANSIENT-ERROR' if $result == PUSH_RESULT_TRANSIENT;
    return 'FATAL-ERROR'     if $result == PUSH_RESULT_ERROR;
}

use constant POLL_INTERVAL_SECONDS => 5;

1;

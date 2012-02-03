# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Connector::File;

use strict;
use warnings;

use base 'Bugzilla::Extension::Push::Connector::Base';

use Bugzilla::Constants;
use Bugzilla::Extension::Push::Constants;
use FileHandle;

sub send {
    my ($self, $message) = @_;

    my $fh = FileHandle->new('>>' . bz_locations()->{'datadir'} . '/push.log');
    $fh->binmode(':utf8');
    $fh->print(
        "[" . scalar(localtime) . "]\n" .
        $message->payload . "\n\n"
    );
    $fh->close;

    return PUSH_RESULT_OK;
}

1;


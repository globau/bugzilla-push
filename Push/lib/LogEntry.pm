# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::LogEntry;

use strict;
use warnings;

use base 'Bugzilla::Object';

use Bugzilla;
use Bugzilla::Error;

#
# initialisation
#

use constant DB_TABLE => 'push_log';
use constant DB_COLUMNS => qw(
    id
    message_id
    push_ts
    processed_ts
    result
    error
);

#
# accessors
#

sub message_id   { return $_[0]->{'message_id'};   }
sub push_ts      { return $_[0]->{'push_ts'};      }
sub processed_ts { return $_[0]->{'processed_ts'}; }
sub result       { return $_[0]->{'result'};       }
sub error        { return $_[0]->{'error'};        }

1;


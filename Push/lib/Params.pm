# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Params;

use strict;
use warnings;

use Bugzilla::Config::Common;
use Bugzilla::Util;

our $sortkey = 1250;

use constant get_param_list => (
    {
        name => 'push-enabled',
        type => 's',
        choices => [ 'off', 'on' ],
        default => 'off',
    },
);

=cut
    {
        name => 'push-hostname',
        type => 't',
        default => ''
    },
    {
        name => 'push-port',
        type => 't',
        default => ''
    },
    {
        name => 'push-username',
        type => 't',
        default => ''
    },
    {
        name => 'push-password',
        type => 'p',
        default => ''
    },
    {
        name => 'AMQP-spec-xml-path',
        type => 't',
        default => ''
    },
    {
        name => 'push-object-created-exchange',
        type => 't',
        default => ''
    },
    {
        name => 'push-object-created-vhost',
        type => 't',
        default => '/'
    },
    {
        name => 'push-object-created-routingkey',
        type => 't',
        default => '%type%.new'
    },
    {
        name => 'push-object-modified-exchange',
        type => 't',
        default => ''
    },
    {
        name => 'push-object-modified-vhost',
        type => 't',
        default => '/'
    },
    {
        name => 'push-object-data-changed-routingkey',
        type => 't',
        default => '%type%.changed.%field%'
    },
);
=cut

1;

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Admin;

use strict;
use warnings;

use Bugzilla;
use Bugzilla::Error;
use Bugzilla::Extension::Push::Util;
use Bugzilla::Util qw(trim);

use base qw(Exporter);
our @EXPORT = qw(
    admin_config
    admin_queues
    admin_log
);

sub admin_config {
    my ($vars) = @_;
    my $push = Bugzilla->push_ext;
    my $input = Bugzilla->input_params;

    if ($input->{save}) {
        my $dbh = Bugzilla->dbh;
        $dbh->bz_start_transaction();
        foreach my $connector ($push->connectors->list) {
            my $config = $connector->config;

            # read values from form
            my $values = {};
            foreach my $option ($config->options) {
                my $name = $option->{name};
                $values->{$name} = trim($input->{$connector->name . ".$name"});
            }

            # validate
            if ($values->{enabled} eq 'Enabled') {
                eval {
                    $config->validate($values);
                };
                if ($@) {
                    ThrowUserError('push_error', { error_message => clean_error($@) });
                }
            }

            # update
            foreach my $option ($config->options) {
                my $name = $option->{name};
                $config->{$name} = $values->{$name};
            }
            $config->update();
        }
        $push->set_config_last_modified();
        $dbh->bz_commit_transaction();
        $vars->{message} = 'push_config_updated';
    }

    $vars->{connectors} = $push->connectors;
}

sub admin_queues {
    my ($vars) = @_;
}

sub admin_log {
    my ($vars) = @_;
}

1;

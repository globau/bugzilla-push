# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Push;

use strict;
use warnings;

use Bugzilla::Extension::Push::Constants;
use Bugzilla::Extension::Push::Connector::Pulse;
use Bugzilla::Extension::Push::Message;
use Bugzilla::Extension::Push::BacklogMessage;
use POE;

sub new {
    my ($class) = @_;
    my $self = {};
    bless($self, $class);

    $self->{connectors} = [
        Bugzilla::Extension::Push::Connector::Pulse->new(),
    ];

    return $self;
}

sub push {
    my $self = $_[HEAP]->{push};

    print "check at " . (scalar localtime) . "\n";

    # process each message
    while(my $message = $self->get_oldest_message) {

        foreach my $connector (@{$self->{connectors}}) {
            printf "pushing to %s\n", $connector->name;

            my $is_backlogged = $connector->backlog_count;

            if (!$is_backlogged) {
                # connector isn't backlogged, immediate send
                print "immediate send\n";
                my $result = $connector->send($message);

                if ($result == PUSH_RESULT_TRANSIENT) {
                    # TODO log transient failure
                    print "transient failure\n";
                    $is_backlogged = 1;

                } elsif ($result == PUSH_RESULT_ERROR) {
                    # TODO log failure
                    print "error\n";

                } else {
                    # TODO log success
                    print "ok\n";
                }
            }

            # if the connector is backlogged, push to the backlog queue
            if ($is_backlogged) {
                Bugzilla::Extension::Push::BacklogMessage->create_from_message($message, $connector);
            }
        }

        # message processed
        $message->remove_from_db();
    }

    # process backlog
    foreach my $connector (@{$self->{connectors}}) {
        while(my $message = $connector->get_oldest_backlog()) {
            printf "processing backlog for %s\n", $connector->name;
            my $result = $connector->send($message);

            if ($result == PUSH_RESULT_TRANSIENT) {
                # TODO log transient failure
                print "transient failure, still broken\n";
                # connector is still down, stop trying
                last;

            } elsif ($result == PUSH_RESULT_ERROR) {
                # TODO log failure
                print "error\n";

            } else {
                # TODO log success
                print "ok\n";
            }

            # message was processed
            $message->remove_from_db();
        }
    }

    $_[KERNEL]->delay(push => POLL_INTERVAL_SECONDS);
}

sub get_oldest_message {
    my ($self) = @_;
    my $dbh = Bugzilla->dbh;
    # XXX use bz's generic sql limiter
    my ($id, $push_ts, $payload) = $dbh->selectrow_array("
        SELECT id, push_ts, payload
          FROM push
         ORDER BY push_ts
         LIMIT 1") or return;
    my $message = Bugzilla::Extension::Push::Message->new({
        id => $id,
        push_ts => $push_ts,
        payload => $payload,
    });
    return $message;
}
    
1;

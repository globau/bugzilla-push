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
use Bugzilla::Extension::Push::Connectors;
use Bugzilla::Extension::Push::Message;
use Bugzilla::Extension::Push::BacklogMessage;

BEGIN {
    *Bugzilla::push_ext = \&_get_instance;
}   

my $_instance;
sub _get_instance {
    if (!$_instance) {
        $_instance = Bugzilla::Extension::Push::Push->_new();
    }
    return $_instance;
}

sub _new {
    my ($class) = @_;
    my $self = {};
    bless($self, $class);

    $self->logger(Bugzilla::Extension::Push::Logger->new());
    $self->connectors(Bugzilla::Extension::Push::Connectors->new());

    return $self;
}

sub start {
    my ($self) = @_;
    my $connectors = $self->connectors;
    $connectors->start();

    foreach my $connector ($connectors->list) {
        $connector->reset_backoff();
    }

    while(1) {
        $self->push();
        sleep(POLL_INTERVAL_SECONDS);
    }
}

sub push {
    my ($self) = @_;
    my $logger = $self->logger;
    my $connectors = $self->connectors;

    $logger->debug("polling");

    # process each message
    while(my $message = $self->get_oldest_message) {
        foreach my $connector ($connectors->list) {
            $logger->debug("pushing to " . $connector->name);

            my $is_backlogged = $connector->backlog_count;

            if (!$is_backlogged) {
                # connector isn't backlogged, immediate send
                $logger->debug("immediate send");
                my($result, $error) = $connector->send($message);
                $logger->result($connector, $message, $result, $error);

                if ($result == PUSH_RESULT_TRANSIENT) {
                    $is_backlogged = 1;
                }
            }

            # if the connector is backlogged, push to the backlog queue
            if ($is_backlogged) {
                my $backlog = Bugzilla::Extension::Push::BacklogMessage->create_from_message($message, $connector);
                $backlog->inc_attempts;
            }
        }

        # message processed
        $message->remove_from_db();
    }

    # process backlog
    foreach my $connector ($connectors->list) {
        my $message = $connector->get_oldest_backlog();
        next unless $message;

        $logger->debug("processing backlog for " . $connector->name);
        while ($message) {
            my($result, $error) = $connector->send($message);
            $message->inc_attempts;
            $logger->result($connector, $message, $result, $error);

            if ($result == PUSH_RESULT_TRANSIENT) {
                # connector is still down, stop trying
                $connector->inc_backoff();
                last;
            }

            # message was processed
            $message->remove_from_db();
            
            $message = $connector->get_oldest_backlog();
        }
    }
}

sub get_oldest_message {
    my ($self) = @_;
    my $dbh = Bugzilla->dbh;
    my ($id, $push_ts, $payload) = $dbh->selectrow_array("
        SELECT id, push_ts, payload
          FROM push
         ORDER BY push_ts " .
        $dbh->sql_limit(1)) or return;
    my $message = Bugzilla::Extension::Push::Message->new({
        id => $id,
        push_ts => $push_ts,
        payload => $payload,
    });
    return $message;
}

sub logger {
    my ($self, $value) = @_;
    $self->{logger} = $value if $value;
    return $self->{logger};
}

sub connectors {
    my ($self, $value) = @_;
    $self->{connectors} = $value if $value;
    return $self->{connectors};
}

1;

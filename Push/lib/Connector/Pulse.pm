# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Connector::Pulse;

use strict;
use warnings;

use base 'Bugzilla::Extension::Push::Connector::Base';

use Bugzilla::Constants;
use Bugzilla::Extension::Push::Constants;
use Data::Dumper;
use Net::AMQP::Common 'show_ascii';
use POE;
use POE::Component::Client::AMQP;
use Term::ANSIColor ':constants';

sub init {
    my ($self) = @_;
    Net::AMQP::Protocol->load_xml_spec(bz_locations()->{extensionsdir} . '/Push/data/amqp0-8.xml');
    $self->_connect();
}

sub send {
    my ($self, $message) = @_;

    if (!$self->{amq}->{is_started}) {
        return PUSH_RESULT_TRANSIENT;
    }

    # XXX need to set timestamp, and other message data
    my $channel = $self->{amq}->channel();
    my $queue = $channel->queue(
        'message_queue',
        {
            auto_delete => 0,
            exclusive   => 0,
        },
    );
    $queue->publish($message->payload);
}

sub _connect {
    my $self = shift;

    $self->{amq} = POE::Component::Client::AMQP->create(
        RemoteAddress => 'mac',
        Reconnect     => 1,
        Debug         => {
            logic => 0,
            frame_input => 0,
            frame_output => 0,
            frame_dumper => sub {
                my $output = Dumper(shift);
                chomp($output);
                return "\n" . BLUE . $output . RESET;
            },
            raw_input => 0,
            raw_output => 0,
            raw_dumper => sub {
                my $raw = shift;
                my $output = "raw [".length($raw)."]: ".show_ascii($raw);
                return "\n" . YELLOW . $output . RESET;
            },
        }
    );
}

1;


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
use Net::RabbitMQ;

sub init {
    my ($self) = @_;
    $self->{mq} = 0;
    $self->{channel} = 1;
    $self->{queue} = 'test.q';
    $self->{exchange} = 'amq.direct';
    $self->{routing_key} = 'foobar';
}

sub send {
    my ($self, $message) = @_;

    # verify existing connection
    if ($self->{mq}) {
        eval {
            $self->{logger}->debug('Pulse: Opening channel ' . $self->{channel});
            $self->{mq}->channel_open($self->{channel});
        };
        if ($@) {
            $self->{logger}->debug('Pulse: ' . $self->_format_error($@));
            $self->{mq} = 0;
        }
    }

    # connect if required
    if (!$self->{mq}) {
        eval {
            $self->{logger}->debug('Pulse: Connecting to RabbitMQ');
            my $mq = Net::RabbitMQ->new();
            $mq->connect('mac', { user => 'guest', password => 'guest' });
            $self->{mq} = $mq;
            $self->{logger}->debug('Pulse: Opening channel ' . $self->{channel});
            $self->{mq}->channel_open($self->{channel});
        };
        if ($@) {
            $self->{mq} = 0;
            return (PUSH_RESULT_TRANSIENT, $self->_format_error($@));
        }
    }

    # send message
    eval {
        $self->{logger}->debug('Pulse: Publishing message');
        $self->{mq}->publish(
            $self->{channel},
            $self->{queue},
            $message->payload,
            {
                exchange => $self->{exchange},
            },
            {
                content_type => 'text/plain',
                content_encoding => '8bit',
            },
        );
        $self->{logger}->debug('Pulse: Closing channel ' . $self->{channel});
        $self->{mq}->channel_close($self->{channel});
    };
    if ($@) {
        return (PUSH_RESULT_TRANSIENT, $self->_format_error($@));
    }

    return PUSH_RESULT_OK;
}

sub _format_error {
    my ($self, $error) = @_;
    my $path = bz_locations->{'extensionsdir'};
    $error = $1 if $error =~ /^(.+?) at \Q$path/s;
    $error =~ s/(^\s+|\s+$)//g;
    return $error;
}

1;


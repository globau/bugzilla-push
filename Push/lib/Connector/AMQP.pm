# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Connector::AMQP;

use strict;
use warnings;

use base 'Bugzilla::Extension::Push::Connector::Base';

use Bugzilla::Constants;
use Bugzilla::Extension::Push::Constants;
use Bugzilla::Extension::Push::Util;
use DateTime;
use Net::RabbitMQ;

sub init {
    my ($self) = @_;
    $self->{mq} = 0;
    $self->{channel} = 1;

    my $queue = Bugzilla->params->{'urlbase'};
    $queue =~ s#^https?://##;
    $queue .= DateTime->now->ymd;
    $self->{queue} = $queue;
}

sub options {
    return (
        {
            name     => 'host',
            label    => 'AMQP Hostname',
            type     => 'string',
            default  => 'localhost',
            required => 1,
        },
        {
            name     => 'port',
            label    => 'AMQP Port',
            type     => 'string',
            default  => '5672',
            required => 1,
            validate => sub {
                $_[0] =~ /\D/ && die "Invalid port (must be numeric)\n";
            },
        },
        {
            name     => 'username',
            label    => 'Username',
            type     => 'string',
            default  => 'guest',
            required => 1,
        },
        {
            name     => 'password',
            label    => 'Password',
            type     => 'string',
            default  => 'guest',
            required => 1,
        },
        {
            name     => 'exchange',
            label    => 'Exchange',
            type     => 'string',
            default  => '',
        },
        {
            name     => 'vhost',
            label    => 'Virtual Host',
            type     => 'string',
            default  => '/',
            required => 1,
        },
    );
}

# XXX
# name    => 'routing_key',
# label   => 'Routing Key Template',
# type    => 'string',
# default => '%target%.%action%.%field%',

sub stop {
    my ($self) = @_;
    my $logger = Bugzilla->push_ext->logger;

    if ($self->{mq}) {
        $logger->debug('AMQP: disconnecting');
        $self->{mq}->disconnect();
        $self->{mq} = 0;
    }
}

sub _connect {
    my ($self) = @_;
    my $logger = Bugzilla->push_ext->logger;
    my $config = $self->config;

    $self->stop();

    $logger->debug('AMQP: Connecting to RabbitMQ ' . $config->{host} . ':' . $config->{port});
    my $mq = Net::RabbitMQ->new();
    $mq->connect(
        $config->{host},
        {
            port => $config->{port},
            user => $config->{username},
            password => $config->{password},
        }
    );
    $self->{mq} = $mq;

    $self->_open();
}

sub _open {
    my ($self) = @_;
    Bugzilla->push_ext->logger->debug('AMQP: Opening channel ' . $self->{channel});
    $self->{mq}->channel_open($self->{channel});
}

sub _close {
    my ($self) = @_;
    Bugzilla->push_ext->logger->debug('AMQP: Closing channel ' . $self->{channel});
    $self->{mq}->channel_close($self->{channel});
}

sub send {
    my ($self, $message) = @_;
    my $logger = Bugzilla->push_ext->logger;
    my $config = $self->config;

    # open channel (also acts to verify the connection is still valid)
    if ($self->{mq}) {
        eval {
            $self->_open();
        };
        if ($@) {
            $logger->debug('AMQP: ' . clean_error($@));
            $self->{mq} = 0;
        }
    }

    eval {
        # reconnect if required
        if (!$self->{mq}) {
            $self->_connect();
        }

        # send message
        $logger->debug('AMQP: Publishing message');
        $self->{mq}->publish(
            $self->{channel},
            $self->{queue},
            $message->payload,
            {
                exchange => $config->{exchange},
            },
            {
                content_type => 'text/plain',
                content_encoding => '8bit',
            },
        );

        # close channel
        $self->_close();
    };
    if ($@) {
        return (PUSH_RESULT_TRANSIENT, clean_error($@));
    }

    return PUSH_RESULT_OK;
}

1;


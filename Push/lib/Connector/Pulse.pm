package Bugzilla::Extension::Push::Connector::Pulse;

use strict;
use warnings;

use Bugzilla::Constants;
use POE;
use POE::Component::Client::AMQP;
use Term::ANSIColor ':constants';
use Net::AMQP::Common 'show_ascii';
use Data::Dumper;
use Bugzilla::Extension::Push::Constants;

sub new {
    my $class = shift;
    my $self = {};
    bless($self, $class);
    $self->init();
    return $self;
}

sub init {
    my $self = shift;
    Net::AMQP::Protocol->load_xml_spec(bz_locations()->{extensionsdir} . '/Push/data/amqp0-8.xml');
    $self->_connect();
}

sub send {
    my ($self, $message) = @_;

    if (!$self->{amq}->{is_started}) {
        return PUSH_RESULT_TRANSIENT;
    }

    my $channel = $self->{amq}->channel();
    print "pulse: channel: $channel\n";
    my $queue = $channel->queue(
        'message_queue',
        {
            auto_delete => 0,
            exclusive   => 0,
        },
    );
    $queue->publish($message);
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


# boilerplate

package Bugzilla::Extension::Push::Daemon;

use strict;
use warnings;

use Bugzilla::Constants;
use File::Basename;
use Daemon::Generic;
use Pod::Usage;
use POE;

use Bugzilla::Extension::Push::Constants;
use Bugzilla::Extension::Push::Connector::Pulse;

sub start {
    newdaemon();
}

#
# daemon::generic config
#

sub gd_preconfig {
    my $self = shift;
    my $pidfile = $self->{gd_args}{pidfile};
    if (!$pidfile) {
        $pidfile = bz_locations()->{datadir} . '/' . $self->{gd_progname} . ".pid";
    }
    return (pidfile => $pidfile);
}

sub gd_getopt {
    my $self = shift;
    $self->SUPER::gd_getopt();
    if ($self->{gd_args}{progname}) {
        $self->{gd_progname} = $self->{gd_args}{progname};
    } else {
        $self->{gd_progname} = basename($0);
    }
    $self->{_original_zero} = $0;
    $0 = $self->{gd_progname};
}

sub gd_postconfig {
    my $self = shift;
    $0 = delete $self->{_original_zero};
}

sub gd_more_opt {
    my $self = shift;
    return (
        'pidfile=s' => \$self->{gd_args}{pidfile},
        'n=s'       => \$self->{gd_args}{progname},
    );
}

sub gd_usage {
    pod2usage({ -verbose => 0, -exitval => 'NOEXIT' });
    return 0;
};

sub gd_redirect_output {
    my $self = shift;

    my $filename = _filename('log');
    open(STDERR, ">>$filename") or (print "could not open stderr: $!" && exit(1));
    close(STDOUT);
    open(STDOUT, ">&STDERR") or die "redirect STDOUT -> STDERR: $!";
    $SIG{HUP} = sub {
        close(STDERR);
        open(STDERR, ">>$filename") or (print "could not open stderr: $!" && exit(1));
    };
}

sub gd_setup_signals {
    my $self = shift;
    $self->SUPER::gd_setup_signals();
    $SIG{TERM} = sub { $self->gd_quit_event(); }
}

#
# POE
#

sub gd_run {
    my $self = shift;

    my @connectors = (
        Bugzilla::Extension::Push::Connector::Pulse->new(),
    );

    POE::Session->create(
        inline_states => {
            _start => sub {
                $_[KERNEL]->delay(push => 5);
            },
            push => sub {
                print "push at " . time() . "\n";
                foreach my $connector (@connectors) {
                    my $result = $connector->send('hello world');
                    if ($result == PUSH_RESULT_OK) {
                        print "ok\n";
                    } elsif ($result == PUSH_RESULT_TRANSIENT) {
                        print "transient failure\n";
                    } elsif ($result == PUSH_RESULT_ERROR) {
                        print "error\n";
                    }
                }
                $_[KERNEL]->delay(push => 10);
            },
        },
    );
    $poe_kernel->run();
}

1;


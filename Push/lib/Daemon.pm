# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Daemon;

use strict;
use warnings;

use Bugzilla::Constants;
use Bugzilla::Extension::Push::Push;
use Bugzilla::Extension::Push::Logger;
use Daemon::Generic;
use File::Basename;
use Pod::Usage;
use POE;

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

    my $logger = Bugzilla::Extension::Push::Logger->new();
    $logger->{debug} = $self->{debug};

    my $connectors = Bugzilla::Extension::Push::Connectors->new(
        Logger => $logger,
    );

    my $push = Bugzilla::Extension::Push::Push->new();

    POE::Session->create(
        package_states => [ 'Bugzilla::Extension::Push::Daemon' => ['_start'] ],
        object_states => [ $push => ['push'] ],
        heap => {
            push => $push,
            logger => $logger,
            connectors => $connectors,
            debug => $self->{debug},
            is_first_push => 1,
        },
    );
    $poe_kernel->run();
}

sub _start {
    my $connectors = $_[HEAP]->{connectors};
    $connectors->start();
    # initiate a push soon after startup
    $_[KERNEL]->delay(push => 1);
    return;
}

1;


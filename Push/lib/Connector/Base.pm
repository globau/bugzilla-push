# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Connector::Base;

use strict;
use warnings;

use Bugzilla;
use Bugzilla::Extension::Push::ConnectorConfig;
use Bugzilla::Extension::Push::BacklogMessage;
use Bugzilla::Extension::Push::BacklogQueue;
use Bugzilla::Extension::Push::Backoff;

sub new {
    my ($class) = @_;
    my $self = {};
    bless($self, $class);
    ($self->{name}) = $class =~ /^.+:(.+)$/;
    $self->init();
    return $self;
}

sub name {
    my $self = shift;
    return $self->{name};
}

sub init {
    my ($self) = @_;
    # abstract
    # perform any initialisation here
    # will be run when created by the web pages or by the daemon
}

sub stop {
    my ($self) = @_;
    # abstract
    # run from the daemon only; disconnect from remote hosts, etc
}

sub send {
    my ($self, $message) = @_;
    # abstract
    # deliver the message, daemon only
}

sub options {
    my ($self) = @_;
    # abstract
    # return an array of configuration variables
    return ();
}

#
#
#

sub config {
    my ($self) = @_;
    if (!$self->{config}) {
        $self->load_config();
    }
    return $self->{config};
}

sub load_config {
    my ($self) = @_;
    my $config = Bugzilla::Extension::Push::ConnectorConfig->new($self);
    $config->load();
    $self->{config} = $config;
}

sub enabled {
    my ($self) = @_;
    return $self->config->{enabled} eq 'Enabled';
}

sub backlog {
    my ($self) = @_;
    $self->{backlog} ||= Bugzilla::Extension::Push::BacklogQueue->new($self->name);
    return $self->{backlog};
}

#
# backoff
#

sub backoff {
    my ($self) = @_;
    my $ra = Bugzilla::Extension::Push::Backoff->match({
        connector => $self->name
    });
    return $ra->[0] if @$ra;
    return Bugzilla::Extension::Push::Backoff->create({
        connector => $self->name
    });
}

sub reset_backoff {
    my ($self) = @_;
    my $backoff = $self->backoff;
    $backoff->reset();
    $backoff->update();
}

sub inc_backoff {
    my ($self) = @_;
    my $backoff = $self->backoff;
    $backoff->inc();
    $backoff->update();
}

1;


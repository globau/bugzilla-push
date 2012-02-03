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
use Bugzilla::Extension::Push::BacklogMessage;

sub new {
    my ($class, %args) = @_;
    my $self = {};
    bless($self, $class);
    ($self->{name}) = $class =~ /^.+:(.+)$/;
    $self->{logger} = $args{Logger};
    $self->init();
    if ($args{Start}) {
        $self->start();
    }
    return $self;
}

sub name {
    my $self = shift;
    return $self->{name};
}

sub init {
    my ($self) = @_;
    # abstract
}

sub start {
    my ($self) = @_;
    # abstract
}

sub send {
    my ($self, $message) = @_;
    # abstract
}

sub backlog_count {
    my ($self) = @_;
    my $dbh = Bugzilla->dbh;
    return $dbh->selectrow_array("
        SELECT COUNT(*)
          FROM push_backlog
         WHERE connector = ?",
        undef,
        $self->name);
}

sub get_oldest_backlog {
    my ($self) = @_;
    my $dbh = Bugzilla->dbh;
    my ($id, $message_id, $push_ts, $payload, $attempt_ts, $attempts) = $dbh->selectrow_array("
        SELECT id, message_id, push_ts, payload, attempt_ts, attempts
          FROM push_backlog
         WHERE connector = ?
         ORDER BY push_ts " .
         $dbh->sql_limit(1),
        undef,
        $self->name) or return;
    my $message = Bugzilla::Extension::Push::BacklogMessage->new({
        id => $id,
        message_id => $message_id,
        push_ts => $push_ts,
        payload => $payload,
        connector => $self->name,
        attempt_ts => $attempt_ts,
        attempts => $attempts,
    });
    return $message;
}


1;


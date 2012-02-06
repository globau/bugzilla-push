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
use Bugzilla::Extension::Push::Backoff;

sub new {
    my ($class, %args) = @_;
    my $self = {};
    bless($self, $class);
    ($self->{name}) = $class =~ /^.+:(.+)$/;
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
        SELECT log.id, message_id, push_ts, payload, attempt_ts, log.attempts
          FROM push_backlog log
               LEFT JOIN push_backoff off ON off.connector = log.connector
         WHERE log.connector = ?
               AND (
                (next_attempt_ts IS NULL)
                OR (next_attempt_ts <= NOW())
               )
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


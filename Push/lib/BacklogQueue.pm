# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::BacklogQueue;

use strict;
use warnings;

use Bugzilla;
use Bugzilla::Extension::Push::BacklogMessage;

sub new {
    my ($class, $connector) = @_;
    my $self = {};
    bless($self, $class);
    $self->{connector} = $connector;
    return $self;
}

sub count {
    my ($self) = @_;
    my $dbh = Bugzilla->dbh;
    return $dbh->selectrow_array("
        SELECT COUNT(*)
          FROM push_backlog
         WHERE connector = ?",
        undef,
        $self->{connector});
}

sub oldest {
    my ($self) = @_;
    my @messages = $self->list(1);
    return scalar(@messages) ? $messages[0] : undef;
}

sub list {
    my ($self, $limit) = @_;
    $limit ||= 10;
    my @result;
    my $dbh = Bugzilla->dbh;

    my $sth = $dbh->prepare("
        SELECT log.id, message_id, push_ts, payload, routing_key, attempt_ts, log.attempts
          FROM push_backlog log
               LEFT JOIN push_backoff off ON off.connector = log.connector
         WHERE log.connector = ?
               AND (
                (next_attempt_ts IS NULL)
                OR (next_attempt_ts <= NOW())
               )
         ORDER BY push_ts " .
         $dbh->sql_limit($limit)
    );
    $sth->execute($self->{connector});
    while (my $row = $sth->fetchrow_hashref()) {
        push @result, Bugzilla::Extension::Push::BacklogMessage->new({
            id          => $row->{id},
            message_id  => $row->{message_id},
            push_ts     => $row->{push_ts},
            payload     => $row->{payload},
            routing_key => $row->{routing_key},
            connector   => $self->{connector},
            attempt_ts  => $row->{attempt_ts},
            attempts    => $row->{attempts},
        });
    }
    return @result;
}

1;

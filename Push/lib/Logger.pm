# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Logger;

use strict;
use warnings;

use Bugzilla::Extension::Push::Constants;
use Bugzilla::Extension::Push::LogEntry;

sub new {
    my ($class, %self) = @_;
    return bless \%self, $class;
}

sub info  { shift->_log_it('INFO', @_) }
sub error { shift->_log_it('ERROR', @_) }
sub debug { shift->_log_it('DEBUG', @_) }

sub _log_it {
    my ($self, $method, $message) = @_;
    return if $method eq 'DEBUG' && ! $self->{debug};
    chomp $message;
    print '[' . localtime(time) ."] $method: $message\n";
}

sub result {
    my ($self, $connector, $message, $result, $error) = @_;

    if ($result == PUSH_RESULT_OK) {
        $result = 'OK';
    } elsif ($result == PUSH_RESULT_TRANSIENT) {
        $result = 'TRANSIENT-ERROR';
    } elsif ($result == PUSH_RESULT_ERROR) {
        $result = 'FATAL-ERROR';
    }

    $error ||= '';

    $self->info(sprintf(
        "%s: Message #%s: %s %s",
        $connector->name,
        $message->message_id,
        push_result_to_string($result),
        $error
    ));

    Bugzilla::Extension::Push::LogEntry->create({
        message_id   => $message->message_id,
        connector    => $connector->name,
        push_ts      => $message->push_ts,
        processed_ts => Bugzilla->dbh->selectrow_array('SELECT NOW()'),
        result       => $result,
        error        => $error,
    });
}

1;

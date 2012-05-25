# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Connector::ServiceNow;

use strict;
use warnings;

use base 'Bugzilla::Extension::Push::Connector::Base';

use Bugzilla::Bug;
use Bugzilla::Constants;
use Bugzilla::Extension::Push::Constants;
use Bugzilla::Extension::Push::Util;
use Bugzilla::Field;
use Bugzilla::Mailer;
use Bugzilla::User;
use Email::MIME;
use FileHandle;
use JSON;
use SOAP::Lite;

sub options {
    return (
        {
            name     => 'bugzilla_user',
            label    => 'Bugzilla Service-Now User',
            type     => 'string',
            default  => 'service.now@bugzilla.tld',
            required => 1,
            validate => sub {
                Bugzilla::User->new({ name => $_[0] })
                    || die "Invalid Bugzilla user ($_[0])\n";
            },
        },
        {
            name     => 'bugzilla_cf',
            label    => 'Bugzilla Service-Now Custom Field',
            type     => 'string',
            default  => 'cf_service_now',
            required => 1,
            validate => sub {
                $_[0] =~ /^cf_/
                    || die "Service-Now field name must start with cf_\n";
                Bugzilla::Field->new({ name => $_[0] })
                    || die "Invalid Service-Now field ($_[0])\n";
            },
        },
        {
            name     => 'ldap_host',
            label    => 'Mozilla LDAP Host',
            type     => 'string',
            default  => '',
            required => 1,
        },
        {
            name     => 'ldap_user',
            label    => 'Mozilla LDAP Username',
            type     => 'string',
            default  => '',
            required => 1,
        },
        {
            name     => 'ldap_pass',
            label    => 'Mozilla LDAP Password',
            type     => 'string',
            default  => '',
            required => 1,
        },
        {
            name     => 'service_now_url',
            label    => 'Service Now SOAP URL',
            type     => 'string',
            default  => 'https://mozilladev.service-now.com',
            required => 1,
            help     => "Must start with https:// and cannot end with /",
            validate => sub {
                $_[0] =~ m#^https://[^\.]+\.service-now\.com$#
                    || die "Invalid Service Now host URL\n";
            },
        },
        {
            name     => 'service_now_user',
            label    => 'Service Now SOAP Username',
            type     => 'string',
            default  => '',
            required => 1,
        },
        {
            name     => 'service_now_pass',
            label    => 'Service Now SOAP Password',
            type     => 'string',
            default  => '',
            required => 1,
        },
    );
}

my $_instance;

sub init {
    my ($self) = @_;
    $_instance = $self;
}

sub should_send {
    my ($self, $message) = @_;

    my $data = $message->payload_decoded;
    my $bug_id = $self->_get_bug_id($data)
        || return 0;

    # ensure the service-now user can see the bug
    $self->{bugzilla_user} ||= Bugzilla::User->new({ name => $self->config->{bugzilla_user} });
    if (!$self->{bugzilla_user} || !$self->{bugzilla_user}->is_enabled) {
        return 0;
    }
    $self->{bugzilla_user}->can_see_bug($bug_id)
        || return 0;

    # filter based on the custom field (non-emtpy = send)
    my $bug = Bugzilla::Bug->new($bug_id);
    return $bug->{$self->config->{bugzilla_cf}} ne '';
}

sub send {
    my ($self, $message) = @_;
    my $logger = Bugzilla->push_ext->logger;
    my $config = $self->config;

    # ignore filtered messages
    $self->should_send($message)
        || return PUSH_RESULT_IGNORED;

    # should_send intiailises bugzilla_user; make sure we return a useful error message
    if (!$self->{bugzilla_user}) {
        return (PUSH_RESULT_TRANSIENT, "Invalid bugzilla-user (" . $self->config->{bugzilla_user} . ")");
    }

    # load the bug
    my $data = $message->payload_decoded;
    my $bug_id = $self->_get_bug_id($data);
    my $bug = Bugzilla::Bug->new($bug_id);

    # map bmo login to ldap login and insert into json payload
    $self->_add_ldap_logins($data, {});

    # send to service-now
    eval {
        my $soap = SOAP::Lite->proxy($self->config->{service_now_url} . "/ecc_queue.do?SOAP");
        my $method = SOAP::Data->name('insert')->attr({xmlns =>   'http://www.service-now.com/'});

        my @params = (
            SOAP::Data->name(agent   => 'InboundEmail'),
            SOAP::Data->name(queue   => 'input'),
            SOAP::Data->name(name    => 'Inbound Email Processing'),
            SOAP::Data->name(source  => Bugzilla->params->{urlbase}),
            SOAP::Data->name(payload => $self->_build_mail($data, $bug)),
        );

        my $result = $soap->call($method => @params);
        if ($result->fault) {
            die $result->fault->{faultstring} . "\n";
        }

    };
    if ($@) {
        return (PUSH_RESULT_TRANSIENT, clean_error($@));
    }

    return PUSH_RESULT_OK;
}

sub _get_bug_id {
    my ($self, $data) = @_;
    my $target = $data->{event}->{target};
    if ($target eq 'bug') {
        return $data->{bug}->{id};
    } elsif (exists $data->{$target}->{bug}) {
        return $data->{$target}->{bug}->{id};
    } else {
        return;
    }
}

sub _build_mail {
    my ($self, $data, $bug) = @_;

    my $email = Email::MIME->create(
        header => [
            From    => Bugzilla->params->{'mailfrom'},
            Subject => sprintf("Bug %s: %s", $bug->id, $bug->short_desc),
        ],
        parts => [
            Email::MIME->create(
                attributes => {
                    charset      => 'utf8',
                    content_type => 'application/json',
                    encoding     => 'quoted-printable',
                    filename     => $data->{event}->{change_set} . '.txt',
                    name         => $data->{event}->{change_set} . '.txt',
                },
                body => encode_json($data),
            ),
        ],
    );

    return $email->as_string;
}

sub _add_ldap_logins {
    my ($self, $rh, $cache) = @_;
    if (exists $rh->{login}) {
        my $login = $rh->{login};
        $cache->{$login} ||= $self->_bmo_to_ldap($login);
        $rh->{ldap} = $cache->{$login};
    }
    foreach my $key (keys %$rh) {
        next unless ref($rh->{$key}) eq 'HASH';
        $self->_add_ldap_logins($rh->{$key}, $cache);
    }
}

sub _bmo_to_ldap {
    my ($login) = @_;
    # XXX map login to ldap login
    return '?';
}

sub SOAP::Transport::HTTP::Client::get_basic_credentials {
    return $_instance->config->{service_now_user} => $_instance->config->{service_now_pass};
}

1;


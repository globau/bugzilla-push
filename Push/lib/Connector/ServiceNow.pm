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
use Bugzilla::Extension::Push::Serialise;
use Bugzilla::Extension::Push::Util;
use Bugzilla::Field;
use Bugzilla::Mailer;
use Bugzilla::User;
use Bugzilla::Util qw(trim);
use Email::MIME;
use FileHandle;
use JSON;
use Net::LDAP;
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
            name     => 'ldap_poll',
            label    => 'Mozilla LDAP Poll Frequency',
            type     => 'string',
            default  => '3',
            required => 1,
            help     => 'minutes',
            validate => sub {
                $_[0] =~ /\D/
                    && die "LDAP Poll Frequency must be an integer\n";
                $_[0]  == 0
                    && die "LDAP Poll Frequency cannot be less than one minute\n";
            },
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
    my $bug_data = $self->_get_bug_data($data)
        || return 0;

    # we don't want to send the initial comment in a separate message
    # because we fold it into the inital message
    if ($message->routing_key eq 'comment.create' && $data->{comment}->{number} == 0) {
        return 0;
    }

    # ensure the service-now user can see the bug
    $self->{bugzilla_user} ||= Bugzilla::User->new({ name => $self->config->{bugzilla_user} });
    if (!$self->{bugzilla_user} || !$self->{bugzilla_user}->is_enabled) {
        return 0;
    }
    $self->{bugzilla_user}->can_see_bug($bug_data->{id})
        || return 0;

    # don't push changes made by the service-now account
    $data->{event}->{user}->{id} == $self->{bugzilla_user}->id
        && return 0;

    # filter based on the custom field (non-emtpy = send)
    my $bug = Bugzilla::Bug->new($bug_data->{id});
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
    my $bug_data = $self->_get_bug_data($data);
    my $bug = Bugzilla::Bug->new($bug_data->{id});

    # inject the comment into the data for new bugs
    if ($message->routing_key eq 'bug.create') {
        my $comment = shift @{ $bug->comments };
        if ($comment->body ne '') {
            $bug_data->{comment} = Bugzilla::Extension::Push::Serialise->instance->object_to_hash($comment, 1);
        }
    }

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

sub _get_bug_data {
    my ($self, $data) = @_;
    my $target = $data->{event}->{target};
    if ($target eq 'bug') {
        return $data->{bug};
    } elsif (exists $data->{$target}->{bug}) {
        return $data->{$target}->{bug};
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
        Bugzilla->push_ext->logger->debug("BMO($login) --> LDAP(" . $cache->{$login} . ")");
        $rh->{ldap} = $cache->{$login};
    }
    foreach my $key (keys %$rh) {
        next unless ref($rh->{$key}) eq 'HASH';
        $self->_add_ldap_logins($rh->{$key}, $cache);
    }
}

sub _bmo_to_ldap {
    my ($self, $login) = @_;
    my $ldap = $self->_ldap_cache();

    return '' unless $login =~ /\@mozilla\.(?:com|org)$/;

    foreach my $check ($login, canon_email($login)) {
        # check for matching bugmail entry
        foreach my $mail (keys %$ldap) {
            next unless $ldap->{$mail}{bugmail_canon} eq $check;
            return $mail;
        }

        # check for matching mail
        if (exists $ldap->{$check}) {
            return $check;
        }

        # check for matching email alias
        foreach my $mail (sort keys %$ldap) {
            next unless grep { $check eq $_ } @{$ldap->{$mail}{aliases}};
            return $mail;
        }
    }

    return '';
}

sub _ldap_cache {
    my ($self) = @_;
    my $logger = Bugzilla->push_ext->logger;
    my $config = $self->config;

    # cache of all ldap entries; updated infrequently
    if (!$self->{ldap_cache_time} || (time) - $self->{ldap_cache_time} > $config->{ldap_poll} * 60) {
        $logger->debug('refreshing LDAP cache');

        my $cache = {};

        my $ldap = Net::LDAP->new($config->{ldap_host}, scheme => 'ldaps', onerror => 'die')
            or die "$@";
        $ldap->bind('mail=' . $config->{ldap_user} . ',o=com,dc=mozilla', password => $config->{ldap_pass});
        my $result = $ldap->search(
            base => 'o=com,dc=mozilla',
            scope => 'sub',
            filter => '(mail=*)',
            attrs => ['mail', 'bugzillaEmail', 'emailAlias', 'cn', 'employeeType'],
        );
        foreach my $entry ($result->entries) {
            my ($name, $bugMail, $mail, $type) =
                map { $entry->get_value($_) || '' }
                qw(cn bugzillaEmail mail employeeType);
            next if $type eq 'DISABLED';
            $mail = lc $mail;
            $bugMail = '' if $bugMail !~ /\@/;
            $bugMail = trim($bugMail);
            if ($bugMail =~ / /) {
                $bugMail = (grep { /\@/ } split / /, $bugMail)[0];
            }
            $name =~ s/\s+/ /g;
            $cache->{$mail}{name} = trim($name);
            $cache->{$mail}{bugmail} = $bugMail;
            $cache->{$mail}{bugmail_canon} = canon_email($bugMail);
            $cache->{$mail}{aliases} = [];
            foreach my $alias (
                @{$entry->get_value('emailAlias', asref => 1) || []}
            ) {
                push @{$cache->{$mail}{aliases}}, canon_email($alias);
            }
        }

        $self->{ldap_cache}      = $cache;
        $self->{ldap_cache_time} = (time);
    }

    return $self->{ldap_cache};
}

sub SOAP::Transport::HTTP::Client::get_basic_credentials {
    return $_instance->config->{service_now_user} => $_instance->config->{service_now_pass};
}

1;


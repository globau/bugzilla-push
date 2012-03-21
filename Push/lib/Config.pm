# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Config;

use strict;
use warnings;

use Bugzilla::Extension::Push::Option;

sub new {
    my ($class, $name, @options) = @_;
    my $self = {
        _name => $name
    };
    bless($self, $class);

    $self->{_options} = [@options];
    unshift @{$self->{_options}}, {
        name     => 'enabled',
        label    => 'Status',
        type     => 'select',
        values   => [ 'Enabled', 'Disabled' ],
        default  => 'Disabled',
    };

    return $self;
}

sub options {
    my ($self) = @_;
    return @{$self->{_options}};
}

sub load {
    my ($self) = @_;
    my $config = {};
    my $logger = Bugzilla->push_ext->logger;

    # prime $config with defaults
    foreach my $rh ($self->options) {
        $config->{$rh->{name}} = $rh->{default};
    }

    # override defaults with values from database
    my $options = Bugzilla::Extension::Push::Option->match({
        connector => $self->{_name},
    });
    foreach my $option (@$options) {
        $config->{$option->name} = $option->value;
    }

    # validate
    $self->_validate_config($config);

    # done, update self
    foreach my $name (keys %$config) {
        $logger->debug(sprintf("%s: set %s=%s\n", $self->{_name}, $name, $config->{$name}));
        $self->{$name} = $config->{$name};
    }
}

sub validate {
    my ($self, $config) = @_;
    $self->_validate_mandatory($config);
    $self->_validate_config($config);
}

sub update {
    my ($self) = @_;

    my @valid_options = map { $_->{name} } $self->options;

    my %options;
    my $options_list = Bugzilla::Extension::Push::Option->match({
        connector => $self->{_name},
    });
    foreach my $option (@$options_list) {
        $options{$option->name} = $option;
    }

    # delete options which are no longer valid
    foreach my $name (keys %options) {
        if (!grep { $_ eq $name } @valid_options) {
            $options{$name}->remove_from_db();
            delete $options{$name};
        }
    }

    # update options
    foreach my $name (keys %options) {
        my $option = $options{$name};
        $option->set_value($self->{$name});
        $option->update();
    }

    # add missing options
    foreach my $name (@valid_options) {
        next if exists $options{$name};
        Bugzilla::Extension::Push::Option->create({
            connector    => $self->{_name},
            option_name  => $name,
            option_value => $self->{$name},
        });
    }
}

sub _remove_invalid_options {
    my ($self, $config) = @_;
    my @names;
    foreach my $rh ($self->options) {
        push @names, $rh->{name};
    }
    foreach my $name (keys %$config) {
        if ($name =~ /^_/ || !grep { $_ eq $name } @names) {
            delete $config->{$name};
        }
    }
}

sub _validate_mandatory {
    my ($self, $config) = @_;
    $self->_remove_invalid_options($config);

    my @missing;
    foreach my $option ($self->options) {
        next unless $option->{required};
        my $name = $option->{name};
        if (!exists $config->{$name} || !defined($config->{$name}) || $config->{$name} eq '') {
            push @missing, $name;
        }
    }
    if (@missing) {
        my $connector = $self->{_name};
        if (scalar @missing == 1) {
            die "The option '$missing[0]' for the connector '$connector' is mandatory\n";
        } else {
            die "The following options for the connector '$connector' are mandatory:\n  "
                . join("\n  ", @missing) . "\n";
        }
    }
}

sub _validate_config {
    my ($self, $config) = @_;
    $self->_remove_invalid_options($config);

    my @errors;
    foreach my $option ($self->options) {
        my $name = $option->{name};
        next unless exists $config->{$name} && exists $option->{validate};
        eval {
            $option->{validate}->($config->{$name});
        };
        push @errors, $@ if $@;
    }
    die join("\n", @errors) if @errors;
}

1;

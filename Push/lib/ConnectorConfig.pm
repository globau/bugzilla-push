# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::ConnectorConfig;

use strict;
use warnings;

use Bugzilla::Extension::Push::Option;

sub new {
    my ($class, $connector) = @_;
    my $self = {
        _connector => $connector
    };
    bless($self, $class);
    return $self;
}

sub options {
    my ($self) = @_;
    return $self->{_connector}->options;
}

sub load {
    my ($self) = @_;

    # prime $config with defaults
    my $config = {};
    foreach my $rh ($self->options) {
        $config->{$rh->{name}} = $rh->{default};
    }

    # override defaults with values from database
    my $options = Bugzilla::Extension::Push::Option->match({
        connector => $self->{_connector}->name,
    });
    foreach my $option (@$options) {
        $config->{$option->option_name} = $option->option_value;
    }

    # validate
    $self->_validate_config($config);
    foreach my $key (keys %$config) {
        $self->{$key} = $config->{$key};
    }
}

sub validate {
    my ($self, $config) = @_;
    $self->_validate_mandatory($config);
    $self->_validate_config($config);
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
    # XXX todo
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

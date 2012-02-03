# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::Push::Connectors;

use strict;
use warnings;

use Bugzilla::Constants;
use File::Basename;

sub new {
    my ($class, %args) = @_;
    my $self = {};
    bless($self, $class);

    $self->{names} = [];
    $self->{objects} = {};
    $self->{path} = bz_locations->{'extensionsdir'} . '/Push/lib/Connector';
    $self->{logger} = $args{Logger};

    foreach my $file (glob($self->{path} . '/*.pm')) {
        my $name = basename($file);
        $name =~ s/\.pm$//;
        next if $name eq 'Base';
        push @{$self->{names}}, $name;
    }

    return $self;
}

sub start {
    my ($self) = @_;
    foreach my $name (@{$self->{names}}) {
        next if exists $self->{objects}->{$name};
        my $file = $self->{path} . "/$name.pm";
        require $file;
        my $package = "Bugzilla::Extension::Push::Connector::$name";
        $self->{objects}->{$name} = $package->new(Start => 1, Logger => $self->{logger});
    }
}

sub names {
    my ($self) = @_;
    return @{$self->{names}};
}

sub list {
    my ($self) = @_;
    return values %{$self->{objects}};
}

1;


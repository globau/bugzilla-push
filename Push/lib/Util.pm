# boilerplate

package Bugzilla::Extension::Push::Util;

use strict;
use warnings;

use Bugzilla::Util 'datetime_from';
use Data::Dumper;
use Scalar::Util 'blessed';

use base qw(Exporter);
our @EXPORT = qw(
    datetime_to_timestamp
    debug_dump
    get_first_value   
    hash_undef_to_empty
    is_public
    mapr
);

# returns true if the specified object is public
sub is_public {
    my ($object) = @_;

    my $default_user = Bugzilla::User->new();

    if ($object->isa('Bugzilla::Bug')) {
        return unless $default_user->can_see_bug($object->bug_id);
        return 1;

    } elsif ($object->isa('Bugzilla::Comment')) {
        return if $object->is_private;
        return unless $default_user->can_see_bug($object->bug_id);
        return 1;

    } elsif ($object->isa('Bugzilla::Attachment')) {
        return if $object->isprivate;
        return unless $default_user->can_see_bug($object->bug_id);
        return 1;

    } else {
        warn "Unsupported class " . blessed($object) . " passed to is_public()\n";
    }

    return 1;
}

# return the first existing value from the hashref for the given list of keys
sub get_first_value {
    my ($rh, @keys) = @_;
    foreach my $field (@keys) {
        return $rh->{$field} if exists $rh->{$field};
    }
    return;
}

# wrapper for map that works on array references
sub mapr(&$) {
    my ($filter, $ra) = @_;
    my @result = map(&$filter, @$ra);
    return \@result;
}


# convert datetime string (from db) to a UTC json friendly datetime
sub datetime_to_timestamp {
    my ($datetime_string) = @_;
    return '' unless $datetime_string;
    return datetime_from($datetime_string, 'UTC')->datetime();
}

# replaces all undef values in a hashref with an empty string (deep)
sub hash_undef_to_empty {
    my ($rh) = @_;
    foreach my $key (keys %$rh) {
        my $value = $rh->{$key};
        if (!defined($value)) {
            $rh->{$key} = '';
        } elsif (ref($value) eq 'HASH') {
            hash_undef_to_empty($value);
        }
    }
}

# debugging method
sub debug_dump {
    my ($object) = @_;
    local $Data::Dumper::Sortkeys = 1;
    my $output = Dumper($object);
    $output =~ s/</&lt;/g;
    print "<pre>$output</pre>";
}

1;

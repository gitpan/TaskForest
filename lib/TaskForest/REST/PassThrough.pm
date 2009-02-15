package TaskForest::REST::PassThrough;

use strict;
use warnings;

sub handle {
    my ($q, $parent_hash, $h) = @_;
    my $hash = {};
    
    foreach (keys (%$h)) { $hash->{"__$_"} = $h->{$_} }

    # inherit the settings from the parent hash
    foreach (keys (%$parent_hash)) { $hash->{$_} = $parent_hash->{$_} }
    
    return $hash;
}

1;

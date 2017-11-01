use strict;
use warnings;
use base 'basetest';

has 'fruit' => 1;

sub run { die "Not implemented in base class"; }

sub more_fruit { shift->{fruit}++ }
1;

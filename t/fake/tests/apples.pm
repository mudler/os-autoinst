use strict;
use warnings;
use base 'basetest';

has 'apples' => sub { 1 };

sub run { print "Apples are awesomes, and i have " . shift->apples . " of them\n" }

sub more_apples { shift->{apples}++ }

1;

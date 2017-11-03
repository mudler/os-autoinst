use strict;
use warnings;
use OpenQA::Test 'basetest';

has banana => 1;

sub run {
    print "Bananas are awesomes, and i have " . shift->banana . " of them\n";
    die "Not fatal test!";
}

sub more_banana { shift->{banana}++ }
1;

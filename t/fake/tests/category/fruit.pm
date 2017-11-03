use strict;
use warnings;
use OpenQA::Test 'basetest';

has fruit => 1;

sub run { die "Not implemented in base class"; }

sub more_fruit { shift->{fruit}++ }
1;

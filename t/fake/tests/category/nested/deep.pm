use strict;
use warnings;
use base 'basetest';

has 'deep' => 1;

sub run { die "Not implemented in base class"; }

sub more_deep { shift->{deep}++ }
1;

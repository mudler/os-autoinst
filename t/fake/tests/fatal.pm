use strict;
use warnings;
use base 'basetest';

sub run { die 'This test is fatal!'; }

sub test_flags { {fatal => 1} }

1;

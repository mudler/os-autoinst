use strict;
use warnings;
use OpenQA::Test 'basetest';

# If we compile-check the single tests, inheriting from basetest is not enough.
# In real tests cases use base 'basetest' will still work.
# this means or we either do:
# use OpenQA::Test 'basetest';
# or
# use base 'basetest'; will have same effect
#
# In compile phase to make attributes available you need to declare use OpenQA::Test 'basetest';
# Otherwise tests are run regardless if they inherits from basetest as well.

has deep => 1;

sub run { die "Not implemented in base class"; }

sub more_deep { shift->{deep}++ }

1;

use strict;
use warnings;
use OpenQA::Test 'basetest';

has parent_test => sub { [qw(bananas)] };

sub run {
    my $self = shift;
    $self->more_banana;
    $self->more_banana;
    $self->more_banana;
    $self->more_banana;

    print "Child have " . $self->banana . " bananas\n";
    die "Not fatal test!";
}
1;

use strict;
use warnings;
use OpenQA::Test 'basetest';

has parent_test => sub { [qw( apples bananas )] };    # Order is respected!

sub run {
    my $self = shift;
    $self->more_banana;
    $self->more_banana;
    $self->more_apples;
    $self->more_apples;

    $self->SUPER::run;                                # Apples will print!
    die "Not fatal test!";
}
1;
use strict;
use warnings;
use OpenQA::Test 'basetest';

has parent_test => sub { [qw( doubleparenttestinverted )] };    # Order is respected!

sub run {
    my $self = shift;
    $self->more_banana;
    $self->more_banana;
    $self->more_apples;
    $self->more_apples;

    $self->more_deep;
    $self->more_fruit;
    print "We have a total of: " . $self->deep() . " of deep and " . $self->fruit . " fruit\n";

    $self->SUPER::run;    # Bananas will print!

    die "Not fatal test!";
}
1;

use strict;
use warnings;
use base 'basetest';

has 'parent_test' => sub { [qw( bananas apples category::fruit category/nested/deep)] };    # Order is respected!

sub run {
    my $self = shift;
    $self->more_banana;
    $self->more_banana;
    $self->more_apples;
    $self->more_apples;

    $self->SUPER::run;                                                                      # Bananas will print!
    die "Not fatal test!";
}
1;

package load::bar;
use Mojo::Base -base;
has load => sub { $ENV{FOO_BAR_BAR} };
has 'prepared';

sub prepare {
    shift->prepared(1);
}

1;

package backend::component;

use Mojo::Base -base;
use bmwqemu;
use POSIX;
use Carp 'confess';

has 'verbose' => 1;

sub prepare { confess "component method not implemented in base class" }

sub startup { confess "component method not implemented in base class" }

sub _diag {
    my ($self, @messages) = @_;
    my $caller = (caller(1))[3];
    bmwqemu::diag ">> ${caller}(): @messages" if $self->verbose;
}

1;

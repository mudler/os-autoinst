package backend::component::process;

use Mojo::Base 'backend::component';
use bmwqemu;
use POSIX;
use Carp 'confess';

has 'process_id';

$SIG{CHLD} = 'IGNORE';

sub _fork {
    my ($self, $code) = @_;
    my $pid = fork;
    die "Cannot fork: $!" unless defined $pid;
    die "Can't spawn child without code" unless ref($code) eq "CODE";

    if ($pid == 0) {
        $code->();
        exit 0;
    }
    $self->process_id($pid);
    return $self;
}

sub start { confess "component method not implemented in base class" }

sub stop { return unless ($_[0]->process_id); kill POSIX::SIGKILL => $_[0]->process_id while (kill 0 => $_[0]->process_id); }

1;

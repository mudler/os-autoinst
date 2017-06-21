package backend::component::dnsserver;
use Mojo::Base -base;
use Net::DNS::Nameserver;
use backend::component::dnsserver::dnsresolver;
use bmwqemu;

has [qw(record_table listening_port listening_address )];
has 'forward_nameserver' => sub { ['8.8.8.8'] };
has 'policy'             => 'SINK';
has 'verbose'            => 1;

sub _forward_resolve {
    my $self = shift;
    my ($qname, $qtype, $qclass) = @_;
    my (@ans, $rcode);
    $self->_diag("Global policy is FORWARD, forwarding request to " . join(", ", @{$self->forward_nameserver()}));

    my $forward_resolver = new Net::DNS::Resolver(
        nameservers => $self->forward_nameserver(),
        recurse     => 1,
        debug       => 0
    );
    my $question = $forward_resolver->query($qname, $qtype, $qclass);

    if (defined $question) {
        @ans = $question->answer();
        $self->_diag("Answer(FWD) " . $_->string) for @ans;
        $rcode = "NOERROR";
    }
    else {
        $rcode = "NXDOMAIN";
    }

    return ($rcode, @ans);
}

sub start {

    my $self = shift;

    $self->_diag("Global Policy is " . $self->policy());

    my $sinkhole = backend::component::dnsserver::dnsresolver->new(%{$self->record_table});

    my $ns = Net::DNS::Nameserver->new(
        LocalPort    => $self->listening_port,
        LocalAddr    => [$self->listening_address],
        ReplyHandler => sub {
            my ($qname, $qclass, $qtype, $peerhost, $query, $conn) = @_;
            my ($rcode, @ans, @auth, @add);

            $self->_diag("Intercepting request for $qname");

            # If the specified domain needs to be forwarded (FORWARD in the record_table), handle it first
            if ($self->record_table()->{$qname} and $self->record_table()->{$qname} eq "FORWARD") {

                $self->_diag("Rule-based forward for $qname");

                ($rcode, @ans) = $self->_forward_resolve($qname, $qtype, $qclass);

                $rcode = "SERVFAIL" if $rcode eq "NXDOMAIN";    # fail softly, so client will try with next dns server instead of giving up.

                return ($rcode, \@ans);
            }
            # If the domain instead needs to be dropped, return NXDOMAIN with empty answers
            elsif ($self->record_table()->{$qname} and $self->record_table()->{$qname} eq "DROP") {
                $rcode = "NXDOMAIN";
                $self->_diag("Drop for $qname , returning $rcode");
                return ($rcode, []);
            }

            # Handle the internal name resolution with our (sinkhole) resolver
            my $question = $sinkhole->query($qname, $qtype, $qclass);

            if (defined $question) {
                @ans = $question->answer();
                $self->_diag("Answer " . $_->string) for @ans;
                $rcode = "NOERROR";
            }
            else {
                $rcode = "NXDOMAIN";
            }

            # If we had no answer from sinkhole and global policy is FORWARD, use external DNS to resolve the domain
            ($rcode, @ans) = $self->_forward_resolve($qname, $qtype, $qclass) if (@ans == 0 && $self->policy() eq "FORWARD");

            return ($rcode, \@ans,);
        },
        Verbose => 0,
    ) || die "couldn't create nameserver object\n";

    $self->_diag("Server started");

    $ns->main_loop;

}

sub _diag {
    my ($self, @messages) = @_;

    bmwqemu::diag __PACKAGE__ . " @messages" if $self->verbose;
}

1;

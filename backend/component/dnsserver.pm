package backend::component::dnsserver;
use Mojo::Base -base;
use Net::DNS::Nameserver;
use backend::component::dnsresolver;
use bmwqemu;

has [qw(record_table listening_port listening_address)];

sub start {

    my $self = shift;

    my $sinkhole = backend::component::dnsresolver->new(%{$self->record_table});

    my $ns = Net::DNS::Nameserver->new(
        LocalPort    => $self->listening_port,
        LocalAddr    => [$self->listening_address],
        ReplyHandler => sub {
            my ($qname, $qclass, $qtype, $peerhost, $query, $conn) = @_;
            my ($rcode, @ans, @auth, @add);

            bmwqemu::diag(">> DNS Server: Intercepting request for $qname");

            if ($self->record_table()->{$qname} and $self->record_table()->{$qname} eq "FORWARD") {
                $rcode = "SERVFAIL";
                bmwqemu::diag(">> Forward for $qname , returning $rcode");
                return ($rcode, []);
            }
            elsif ($self->record_table()->{$qname} and $self->record_table()->{$qname} eq "DROP") {
                $rcode = "NXDOMAIN";
                bmwqemu::diag(">> Drop for $qname , returning $rcode");
                return ($rcode, []);
            }

            my $question = $sinkhole->query($qname, $qtype, $qclass);

            if (defined $question) {
                @ans = $question->answer();
                bmwqemu::diag(">> DNS Server: Answer " . $_->string) for @ans;
                $rcode = "NOERROR";
            }
            else {
                $rcode = "NXDOMAIN";
            }
            return ($rcode, \@ans,);

        },
        Verbose => 0,
    ) || die "couldn't create nameserver object\n";


    bmwqemu::diag("CONNECTIONS_HIJACK: DNS Server started");

    $ns->main_loop;

}
1;

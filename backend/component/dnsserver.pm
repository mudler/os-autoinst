package backend::component::dnsserver;
use Mojo::Base -base;
use Net::DNS::Nameserver;
use backend::component::dnsresolver;
use bmwqemu;

has [qw(record_table dns_server_port dns_server_address)];

sub start {

    my $self = shift;

    my $sinkhole = backend::component::dnsresolver->new(%{$self->record_table});

    my $ns = Net::DNS::Nameserver->new(
        LocalPort    => $self->dns_server_port,
        LocalAddr    => [$self->dns_server_address],
        ReplyHandler => sub {
            my ($qname, $qclass, $qtype, $peerhost, $query, $conn) = @_;
            my ($rcode, @ans, @auth, @add);

            bmwqemu::diag(">> DNS Server: Intercepting request for $qname");

            my $question = $sinkhole->query($qname, $qtype, $qclass);
            if (defined $question) {
                @ans = $question->answer();
                bmwqemu::diag(">> DNS Server: Answer " . $_->address) for @ans;

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

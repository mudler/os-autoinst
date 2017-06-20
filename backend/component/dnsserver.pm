
package backend::component::dnsserver;
use Mojo::Base -base;
use Net::DNS::Nameserver;
use backend::component::dnsresolver;
use bmwqemu;

has [qw(record_table listening_port listening_address )];

has 'forward_nameserver' => sub { ['8.8.8.8'] };

has 'global_policy' => 'SINK';

sub start {

    my $self = shift;

    bmwqemu::diag(">> DNS Server Global Policy is " . $self->global_policy());

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
                bmwqemu::diag(">> Forward for $qname");

                my $forward_resolver = new Net::DNS::Resolver(
                    nameservers => $self->forward_nameserver(),
                    recurse     => 1,
                    debug       => 0
                );
                my $question = $forward_resolver->query($qname, $qtype, $qclass);

                if (defined $question) {
                    @ans = $question->answer();
                    bmwqemu::diag(">> DNS Server: Answer(FWD) " . $_->string) for @ans;
                    $rcode = "NOERROR";
                }

                return ($rcode, \@ans);

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

            if (@ans == 0 && $self->global_policy() eq "FORWARD") {
                bmwqemu::diag(">> DNS Server: Global policy is FORWARD, forwarding request to " . join(", ", @{$self->forward_nameserver()}));

                my $forward_resolver = new Net::DNS::Resolver(
                    nameservers => $self->forward_nameserver(),
                    recurse     => 1,
                    debug       => 0
                );
                my $question = $forward_resolver->query($qname, $qtype, $qclass);

                if (defined $question) {
                    @ans = $question->answer();
                    bmwqemu::diag(">> DNS Server: Answer(FWD-fallback) " . $_->string) for @ans;
                    $rcode = "NOERROR";
                }
                else {
                    $rcode = "NXDOMAIN";
                }

            }

            return ($rcode, \@ans,);

        },
        Verbose => 0,
    ) || die "couldn't create nameserver object\n";


    bmwqemu::diag("CONNECTIONS_HIJACK: DNS Server started");

    $ns->main_loop;

}
1;
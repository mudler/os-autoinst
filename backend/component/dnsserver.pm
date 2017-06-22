package backend::component::dnsserver;
use Mojo::Base "backend::component::process";
use Net::DNS::Nameserver;
use backend::component::dnsserver::dnsresolver;
use bmwqemu;
use Mojo::URL;
use osutils qw(looks_like_ip);

has [qw(record_table listening_port listening_address )];
has 'forward_nameserver' => sub { ['8.8.8.8'] };
has 'policy'             => 'SINK';
has 'verbose'            => 1;

sub prepare {
    my ($self) = @_;
    my $dns_table = $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_ENTRY};
    my $listening_port = $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_SERVER_PORT} || $bmwqemu::vars{VNC} + bmwqemu::PROXY_BASE_PORT + 2;
    $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_SERVER_PORT} = $listening_port
      if !$bmwqemu::vars{CONNECTIONS_HIJACK_DNS_SERVER_PORT} || $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_SERVER_PORT} ne $listening_port;
    my $listening_address = $bmwqemu::vars{CONNECTIONS_HIJACK_DNS_SERVER_ADDRESS} || '127.0.0.1';
    my $hostname = $bmwqemu::vars{WORKER_HOSTNAME} || '10.0.2.2';

    my %record_table;

    if ($dns_table) {
        my @entry = split(/,/, $dns_table);
        $self->_diag("CONNECTIONS_HIJACK_DNS_ENTRY supplied, but no real redirection rules given. Format is: host:ip, host2:ip2 , ...") and return
          unless (@entry > 0);

        # Generate record table from configuration, translate them in DNS entries
        %record_table = map {
            my ($host, $ip) = split(/:/, $_);
            next unless $host and $ip;
            $host => ($ip eq "FORWARD" or $ip eq "DROP") ? $ip : (looks_like_ip($ip)) ? ["$host.     A   $ip"] : ["$host.     CNAME   $ip"];
        } @entry;

    }

    for my $mirror_url ($bmwqemu::vars{MIRROR_HTTP}, $bmwqemu::vars{SUSEMIRROR}) {
        my $mirror = Mojo::URL->new($mirror_url);
        if ($mirror->host()) {
            $record_table{$mirror->host()} = "FORWARD" if !exists $record_table{$mirror->host()};
            $record_table{"download.opensuse.org"}
              = ["download.opensuse.org. A " . ($bmwqemu::vars{CONNECTIONS_HIJACK_FAKEIP} ? bmwqemu::HIJACK_FAKE_IP : $hostname)];
        }
    }

    $self->_diag("Listening on ${listening_address}:${listening_port}") if keys %record_table;

    foreach my $k (keys %record_table) {
        $self->_diag("table entry: $k => @{${record_table{$k}}}") if ref($record_table{$k}) eq "ARRAY";
        $self->_diag("Forward rule: $k => ${record_table{$k}}")   if ref($record_table{$k}) ne "ARRAY";
    }

    $self->_diag("All DNS requests that doesn't match a defined criteria will be redirected to the host: " . $record_table{"*"}) if $record_table{"*"};

    $self->record_table(\%record_table)          if keys %record_table > 0;
    $self->listening_port($listening_port)       if $listening_port;
    $self->listening_address($listening_address) if $listening_address;

}
sub _forward_resolve {
    my $self = shift;
    my ($qname, $qtype, $qclass) = @_;
    my (@ans, $rcode);
    $self->_diag("Forwarding request to " . join(", ", @{$self->forward_nameserver()}));

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

    $self->_fork(sub { $ns->main_loop; });
}

1;

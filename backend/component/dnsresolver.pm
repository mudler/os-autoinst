package backend::component::dnsresolver;

use warnings;
use strict;
use base 'Net::DNS::Resolver';
use Net::DNS::Packet;
use Net::DNS;

use constant TRUE => 1;

sub new {
    my ($self, %options) = @_;

    $self = $self->SUPER::new(%options);
    $self->{records} = \%options;

    return $self;
}

sub send {
    my $self = shift;
    my ($domain, $class, $rr_type, $peerhost, $query, $conn) = @_;

    my $question = Net::DNS::Question->new($domain, $rr_type, $class);
    $domain  = lc($question->qname);
    $rr_type = $question->qtype;
    $class   = $question->qclass;

    $self->_reset_errorstring;

    my ($result, $aa, @answer_rrs);

    if (not defined($result) or defined($Net::DNS::rcodesbyname{$result})) {
        # Valid RCODE, return a packet:
        $aa     = TRUE      if not defined($aa);
        $result = 'NOERROR' if not defined($result);

        if (defined(my $records = $self->{records})) {

            if (my $sink = $records->{"*"}) {
                my $rr_obj = Net::DNS::RR->new("$domain.     A   $sink");
                push(@answer_rrs, $rr_obj);
            }
            elsif (ref(my $rrs_for_domain = $records->{$domain}) eq 'ARRAY') {
                foreach my $rr (@$rrs_for_domain) {
                    my $rr_obj = Net::DNS::RR->new($rr);
                    push(@answer_rrs, $rr_obj)
                      if $rr_obj->name eq $domain
                      and $rr_obj->type eq $rr_type
                      and $rr_obj->class eq $class;
                }
            }
            else {
                #Failure packet, mostly always.
                return;
            }
        }
        my $packet = Net::DNS::Packet->new($domain, $rr_type, $class);
        $packet->header->qr(TRUE);
        $packet->header->rcode($result);
        $packet->header->aa($aa);
        $packet->push(answer => @answer_rrs);

        return $packet;
    }
    else {
        # Invalid RCODE, signal error condition by not returning a packet:
        $self->errorstring($result);
        return undef;
    }
}

1;

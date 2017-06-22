#!/usr/bin/perl

# Copyright (C) 2017 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, see <http://www.gnu.org/licenses/>.

BEGIN {
    unshift @INC, '..';
}

use 5.018;
use warnings;
use Test::More;
use Net::DNS::Resolver;
use POSIX;
use backend::component::dnsserver;

$SIG{CHLD} = 'IGNORE';
my $ip       = "127.0.0.1";
my $port     = "9993";
my $resolver = new Net::DNS::Resolver(
    nameservers => [$ip],
    port        => $port,
    recurse     => 1,
    debug       => 0
);

sub _request {
    my ($qname, $qtype, $qclass) = @_;
    my @ans;

    my $question = $resolver->query($qname, $qtype, $qclass);

    if (defined $question) {
        @ans = map {
            {
                $_->{owner}->string => [$_->class, $_->type, eval { $_->_format_rdata; }]
            }
        } $question->answer();
    }

    return \@ans;
}

sub _start_dnsserver {
    my ($policy, $record_table, $forward_nameserver) = @_;

    $record_table       //= {};
    $forward_nameserver //= [];

    return backend::component::dnsserver->new(
        listening_address  => $ip,
        listening_port     => $port,
        policy             => $policy,
        record_table       => $record_table,
        forward_nameserver => $forward_nameserver,
        verbose            => 1
    )->start;
}

subtest 'dns requests in SINK mode' => sub {
    my $dnsserver = _start_dnsserver(
        "SINK",
        {
            "download.opensuse.org" => ["download.opensuse.org. A 127.0.0.1"],
            "foo.bar.baz"           => ["foo.bar.baz. A 0.0.0.0", "foo.bar.baz. A 1.1.1.1"],
            "my.foo.bar.baz"        => ["my.foo.bar.baz. CNAME foo.bar.baz"],
            "openqa.opensuse.org"   => "FORWARD"
        },
        ['8.8.8.8']);

    my $ans = _request("download.opensuse.org", "A", "IN");
    is_deeply $ans, [{"download.opensuse.org." => ["IN", "A", "127.0.0.1"]}];

    $ans = _request("foo.bar.baz", "A", "IN");
    is_deeply $ans, [{"foo.bar.baz." => ["IN", "A", "0.0.0.0"]}, {"foo.bar.baz." => ["IN", "A", "1.1.1.1"]}];

    $ans = _request("my.foo.bar.baz", "CNAME", "IN");
    is_deeply $ans, [{"my.foo.bar.baz." => ["IN", "CNAME", "foo.bar.baz."]}];

    $ans = _request("foobar.org", "A", "IN");
    is scalar(@$ans), 0, 'No answer expected in SINK mode';

    $ans = _request("openqa.opensuse.org", "A", "IN");
    ok scalar(@$ans) > 0;

    $dnsserver->stop();
};

subtest 'dns requests in FORWARD mode' => sub {
    my $dnsserver = _start_dnsserver(
        "FORWARD",
        {
            "download.opensuse.org" => ["download.opensuse.org. A 127.0.0.1"],
            "foo.bar.baz"           => ["foo.bar.baz. A 0.0.0.0", "foo.bar.baz. A 1.1.1.1"],
            "my.foo.bar.baz"        => ["my.foo.bar.baz. CNAME foo.bar.baz"],
            "openqa.opensuse.org"   => "DROP"
        },
        ['8.8.8.8']);

    my $ans = _request("download.opensuse.org", "A", "IN");
    is_deeply $ans, [{"download.opensuse.org." => ["IN", "A", "127.0.0.1"]}], "Redirect table has predecence";

    $ans = _request("foo.bar.baz", "A", "IN");
    is_deeply $ans, [{"foo.bar.baz." => ["IN", "A", "0.0.0.0"]}, {"foo.bar.baz." => ["IN", "A", "1.1.1.1"]}], "Redirect table has predecence";

    $ans = _request("my.foo.bar.baz", "CNAME", "IN");
    is_deeply $ans, [{"my.foo.bar.baz." => ["IN", "CNAME", "foo.bar.baz."]}], "Redirect table has predecence";

    $ans = _request("open.qa", "A", "IN");
    ok scalar(@$ans) > 0, 'answer expected in FORWARD mode';

    $ans = _request("openqa.opensuse.org", "A", "IN");
    is scalar(@$ans), 0, "Domain rule with DROP won't be forwarded";

    $dnsserver->stop();
};

subtest 'dns requests with wildcard' => sub {
    my $dnsserver = _start_dnsserver(
        "FORWARD",
        {
            "download.opensuse.org" => ["download.opensuse.org. A 127.0.0.1"],
            "foo.bar.baz"           => ["foo.bar.baz. A 0.0.0.0", "foo.bar.baz. A 1.1.1.1"],
            "my.foo.bar.baz"        => ["my.foo.bar.baz. CNAME foo.bar.baz"],
            "openqa.opensuse.org"   => "DROP",
            "open.qa"               => "FORWARD",
            "*"                     => "2.2.2.2"
        },
        ['8.8.8.8']);

    my $ans = _request("download.opensuse.org", "A", "IN");
    is_deeply $ans, [{"download.opensuse.org." => ["IN", "A", "127.0.0.1"]}], "Redirect table has predecence";

    $ans = _request("foo.bar.baz", "A", "IN");
    is_deeply $ans, [{"foo.bar.baz." => ["IN", "A", "0.0.0.0"]}, {"foo.bar.baz." => ["IN", "A", "1.1.1.1"]}], "Redirect table has predecence";

    $ans = _request("my.foo.bar.baz", "CNAME", "IN");
    is_deeply $ans, [{"my.foo.bar.baz." => ["IN", "CNAME", "foo.bar.baz."]}], "Redirect table has predecence";

    $ans = _request("open.qa", "A", "IN");
    ok scalar(@$ans) > 0, 'answer expected in FORWARD mode';

    $ans = _request("openqa.opensuse.org", "A", "IN");
    is scalar(@$ans), 0, "Domain rule with DROP won't be forwarded";

    $ans = _request("foo.opensuse.org", "A", "IN");
    is_deeply $ans, [{"foo.opensuse.org." => ["IN", "A", "2.2.2.2"]}], "Wildcard will answer to all other questions, even in FORWARD mode";

    $ans = _request("baz.org", "A", "IN");
    is_deeply $ans, [{"baz.org." => ["IN", "A", "2.2.2.2"]}], "Wildcard will answer to all other questions, even in FORWARD mode";

    $dnsserver->stop();

    # (almost) same tests but in SINK mode
    $dnsserver = _start_dnsserver(
        "SINK",
        {
            "download.opensuse.org" => ["download.opensuse.org. A 127.0.0.1"],
            "foo.bar.baz"           => ["foo.bar.baz. A 0.0.0.0", "foo.bar.baz. A 1.1.1.1"],
            "my.foo.bar.baz"        => ["my.foo.bar.baz. CNAME foo.bar.baz"],
            "openqa.opensuse.org"   => "DROP",
            "open.qa"               => "FORWARD",
            "*"                     => "2.2.2.2"
        },
        ['8.8.8.8']);

    $ans = _request("download.opensuse.org", "A", "IN");
    is_deeply $ans, [{"download.opensuse.org." => ["IN", "A", "127.0.0.1"]}], "Redirect table has predecence";

    $ans = _request("foo.bar.baz", "A", "IN");
    is_deeply $ans, [{"foo.bar.baz." => ["IN", "A", "0.0.0.0"]}, {"foo.bar.baz." => ["IN", "A", "1.1.1.1"]}], "Redirect table has predecence";

    $ans = _request("my.foo.bar.baz", "CNAME", "IN");
    is_deeply $ans, [{"my.foo.bar.baz." => ["IN", "CNAME", "foo.bar.baz."]}], "Redirect table has predecence";

    $ans = _request("open.qa", "A", "IN");
    ok scalar(@$ans) > 0, 'answer expected, rule specifies FORWARD mode for the specific domain';
    ok defined $ans->[0]->{'open.qa.'}->[2];
    ok $ans->[0]->{'open.qa.'}->[2] ne "2.2.2.2", "domain that are marked to be forwarded does not return the wildcard value";

    $ans = _request("openqa.opensuse.org", "A", "IN");
    is scalar(@$ans), 0, "Domain rule with DROP won't be forwarded";

    $ans = _request("foo.opensuse.org", "A", "IN");
    is_deeply $ans, [{"foo.opensuse.org." => ["IN", "A", "2.2.2.2"]}], "Wildcard will answer to all other questions, even in FORWARD mode";

    $ans = _request("baz.org", "A", "IN");
    is_deeply $ans, [{"baz.org." => ["IN", "A", "2.2.2.2"]}], "Wildcard will answer to all other questions, even in FORWARD mode";

    $dnsserver->stop();
};


done_testing;

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
use Mojo::UserAgent;
use POSIX;
use backend::component::proxy;

$SIG{CHLD} = 'IGNORE';
my $ip   = "127.0.0.1";
my $port = "9991";
my $ua   = Mojo::UserAgent->new;

sub _request {
    my ($host, $path) = @_;
    return $ua->get('http://' . $ip . ':' . $port . $path => {Host => $host})->result;
}

sub _start_proxy {
    my ($policy, $redirect_table) = @_;

    $redirect_table //= {};

    my $pid = fork;
    die "Cannot fork: $!" unless defined $pid;

    if ($pid == 0) {
        backend::component::proxy->new(
            listening_address => $ip,
            listening_port    => $port,
            policy            => $policy,
            redirect_table    => $redirect_table
        )->start;
        exit 0;
    }

    while (1) {
        last if $ua->get('http://' . $ip . ':' . $port)->connection;
    }

    return $pid;
}

subtest 'proxy forward' => sub {
    my $pid = _start_proxy("FORWARD");

    my $res = _request('download.opensuse.org', '/tumbleweed/repo/oss/README');
    ok $res->is_success;
    like $res->body, qr/SUSE Linux Products GmbH/, "HTTP Request was correctly forwarded";

    $res = _request('openqa.opensuse.org', '/');
    ok $res->is_success;
    like $res->body, qr/openQA is licensed/, "HTTP Request was correctly forwarded";

    $res = _request('github.com', '/os-autoinst/openQA');
    ok $res->is_success;
    like $res->body, qr/openQA web-frontend, scheduler and tools\./, "HTTP Request was correctly forwarded";

    kill POSIX::SIGKILL => $pid;
};

subtest 'proxy drop' => sub {
    my $pid = _start_proxy("DROP");

    my $res = _request('download.opensuse.org', '/tumbleweed/repo/oss/README');
    ok !$res->is_success;
    is $res->code, "404", "HTTP Request was dropped correctly with a 404";

    $res = _request('openqa.opensuse.org', '/');
    ok !$res->is_success;
    is $res->code, "404", "HTTP Request was dropped correctly with a 404";

    $res = _request('github.com', '/os-autoinst/openQA');
    ok !$res->is_success;
    is $res->code, "404", "HTTP Request was dropped correctly with a 404";

    kill POSIX::SIGKILL => $pid;
};

subtest 'proxy redirect' => sub {
    my $pid = _start_proxy("REDIRECT", {'github.com' => ['download.opensuse.org']});

    my $res = _request('github.com', '/tumbleweed/repo/oss/README');
    ok $res->is_success;
    like $res->body, qr/SUSE Linux Products GmbH/, "HTTP request correctly redirected";

    $res = _request('github.com', '/os-autoinst/openQA');
    ok !$res->is_success;
    is $res->code, "404", "Redirect is correct, leads to a 404";

    kill POSIX::SIGKILL => $pid;
};

subtest 'proxy urlrewrite' => sub {
    my $pid = _start_proxy(
        "URLREWRITE",
        {
            'download.opensuse.org' => [
                'github.com',          "/tumbleweed/repo/oss/README",
                "FORWARD",             "/os-autoinst/os-autoinst\$",
                "/os-autoinst/openQA", "/os-autoinst/os-autoinst-distri-opensuse",
                "/os-autoinst/os-autoinst-needles-opensuse",
              ]

        });

    my $res = _request('download.opensuse.org', '/tumbleweed/repo/oss/README');
    ok $res->is_success;
    like $res->body, qr/SUSE Linux Products GmbH/, "HTTP Request with rewrite url";

    $res = _request('download.opensuse.org', '/os-autoinst/os-autoinst');
    ok $res->is_success;
    like $res->body, qr/openQA web-frontend, scheduler and tools/, "HTTP Request with rewrite url";

    $res = _request('download.opensuse.org', '/os-autoinst/os-autoinst-distri-opensuse');
    ok $res->is_success;
    like $res->body, qr/os-autoinst needles for openSUSE/, "HTTP Request with rewrite url";

    kill POSIX::SIGKILL => $pid;
};


done_testing;

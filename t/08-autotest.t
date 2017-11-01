#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use Test::Output;
use Test::Fatal;
use Test::MockModule;
use File::Basename ();

BEGIN {
    unshift @INC, '..';
}

use autotest;
use bmwqemu;
$bmwqemu::vars{CASEDIR} = File::Basename::dirname($0) . '/fake';
# array of messages sent with the fake json_send
my @sent;
my $out;

like(exception { autotest::runalltests }, qr/ERROR: no tests loaded/, 'runalltests needs tests loaded first');
stderr_like(
    sub {
        like(exception { autotest::loadtest 'does/not/match' }, qr/loadtest needs a script to match/);
    },
    qr/loadtest needs a script below.*is not/
);

sub loadtest {
    my ($test, $args) = @_;
    stderr_like(sub { autotest::loadtest "tests/$test.pm" }, qr@scheduling $test[0-9]? tests/$test.pm@, \$args);
}

sub fake_send {
    my ($target, $msg) = @_;
    push @sent, $msg;
}

# find the (first) 'tests_done' message from the @sent array and
# return the 'died' and 'completed' values
sub get_tests_done {
    for my $msg (@sent) {
        if (ref($msg) eq "HASH" && $msg->{cmd} eq 'tests_done') {
            return ($msg->{died}, $msg->{completed});
        }
    }
}

my $mock_jsonrpc = new Test::MockModule('myjsonrpc');
$mock_jsonrpc->mock(send_json => \&fake_send);
$mock_jsonrpc->mock(read_json => sub { });
my $mock_bmwqemu = new Test::MockModule('bmwqemu');
$mock_bmwqemu->mock(save_json_file => sub { });
my $mock_basetest = new Test::MockModule('basetest');
$mock_basetest->mock(_result_add_screenshot => sub { });
# stop run_all from quitting at the end
my $mock_autotest = new Test::MockModule('autotest', no_auto => 1);
$mock_autotest->mock(_exit => sub { });

my $died;
my $completed;
# we have to define this to *something* so the `close` in run_all
# doesn't crash us
$autotest::isotovideo = 'foo';
autotest::run_all;
($died, $completed) = get_tests_done;
is($died,      1, 'run_all with no tests should catch runalltests dying');
is($completed, 0, 'run_all with no tests should not complete');
@sent = [];

loadtest 'start';
is(keys %autotest::tests, 1);
loadtest 'next';
is(keys %autotest::tests, 2);
loadtest 'start', 'rescheduling same step later';
is(keys %autotest::tests, 3) || diag explain %autotest::tests;

autotest::run_all;
($died, $completed) = get_tests_done;
is($died,      0, 'start+next+start should not die');
is($completed, 1, 'start+next+start should complete');
@sent = [];

# now let's make the tests fail...but so far none is fatal. We also
# have to mock query_isotovideo so we think snapshots are supported.
# we cause the failure by mocking runtest rather than using a test
# which dies, as runtest does a whole bunch of stuff when the test
# dies that we may not want to run into here
#$mock_basetest->mock(runtest          => sub { die "oh noes!\n"; });
$mock_basetest->mock(
    runtest => sub {
        my $self = shift;
        my $name = ref($self);
        eval {
            open my $handle, '>', \$out;
            local *STDERR = $handle;
            local *STDOUT = $handle;
            $self->pre_run_hook();
            $self->run();
            $self->post_run_hook();
        };
        $self->run_post_fail("test $name died") if $@;
    });
$mock_autotest->mock(query_isotovideo => sub { return 1; });

autotest::run_all;
($died, $completed) = get_tests_done;
is($died,      0, 'non-fatal test failure should not die');
is($completed, 1, 'non-fatal test failure should complete');
@sent = [];

loadtest 'ignore_failure';
autotest::run_all;
($died, $completed) = get_tests_done;
is($died,      0, 'unimportant test failure should not die');
is($completed, 1, 'unimportant test failure should complete');
@sent = [];

$out = undef;
loadtest 'childtest';
autotest::run_all;
($died, $completed) = get_tests_done;
is($died,      0, 'newtest should not die');
is($completed, 1, 'newtest should complete');
like $out, qr/Child have (.*) Bananas/i, "Child output of test is there";
@sent = [];

$out = undef;
loadtest 'doubleparenttest';
autotest::run_all;
($died, $completed) = get_tests_done;
is($died,      0, 'newtest should not die');
is($completed, 1, 'newtest should complete');
@sent = [];
like $out, qr/Apples are awesomes, and i have/, "Child output of test is there";

$out = undef;
loadtest 'doubleparenttestinverted';
autotest::run_all;
($died, $completed) = get_tests_done;
is($died,      0, 'newtest should not die');
is($completed, 1, 'newtest should complete');
@sent = [];
like $out, qr/Bananas are awesomes, and i have/, "Child output of test is there";

$out = undef;
loadtest 'bananas';
autotest::run_all;
($died, $completed) = get_tests_done;
is($died,      0, 'newtest should not die');
is($completed, 1, 'newtest should complete');
@sent = [];
like $out, qr/Bananas are awesomes, and i have/, "Child output of test is there";

$out = undef;
loadtest 'nestedparent';
autotest::run_all;
($died, $completed) = get_tests_done;
is($died,      0, 'newtest should not die');
is($completed, 1, 'newtest should complete');
@sent = [];
like $out, qr/We have a total of: 1 of deep and 1 fruit/,  "Child output of test is there" or explain $out;
like $out, qr/Bananas are awesomes, and i have 4 of them/, "Child output of test is there" or explain $out;

# now let's add a fatal test
loadtest 'fatal';
autotest::run_all;
($died, $completed) = get_tests_done;
is($died,      0, 'fatal test failure should not die');
is($completed, 0, 'fatal test failure should not complete');
@sent = [];

done_testing();

# vim: set sw=4 et:

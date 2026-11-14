#!perl

use strict;
use warnings;
use Config;
use Test::More;

plan skip_all => 'iOS pseudofork support is not enabled'
    unless $^O =~ /darwin-ios/ && $Config::Config{d_pseudofork};
my $wnohang = eval {
    require POSIX;
    POSIX::WNOHANG();
};
plan skip_all => 'no POSIX::WNOHANG' unless defined $wnohang;

$| = 1;

my $parent_pid = $$;
my $pid = fork();
if (!defined $pid) {
    ok(0, 'fork creates a pseudo-child');
}
elsif ($pid == 0) {
    exit($$ < 0 ? 17 : 18);
}
else {
    ok(1, 'fork creates a pseudo-child');
    ok($pid < 0, 'pseudo-child has a negative PID');
    isnt($pid, $parent_pid, 'pseudo-child PID differs from parent PID');
    is(waitpid($pid, 0), $pid, 'waitpid returns the pseudo-child PID');
    is($? >> 8, 17, 'child sees its pseudo-PID');
    is($$, $parent_pid, 'parent interpreter remains usable');
}

$pid = fork();
if ($pid == 0) {
    sleep 1;
    exit 23;
}
else {
    is(waitpid($pid, $wnohang), 0, 'WNOHANG does not reap a running child');
    is(waitpid($pid, 0), $pid, 'WNOHANG child can subsequently be waited for');
    is($? >> 8, 23, 'WNOHANG child status is preserved');
}

my $first = fork();
if ($first == 0) {
    sleep 1;
    exit 31;
}
my $second = fork();
if ($second == 0) {
    exit 37;
}

my $reaped = waitpid(-1, 0);
ok($reaped == $first || $reaped == $second,
   'waitpid(-1) returns one of this interpreter\'s children');
my $reaped_status = $? >> 8;
my $remaining = $reaped == $first ? $second : $first;
is(waitpid($remaining, 0), $remaining,
   'waitpid can reap the remaining child');
my $remaining_status = $? >> 8;
is($reaped_status == 31 || $reaped_status == 37, 1,
   'waitpid(-1) returns a valid child status');
is($remaining_status == 31 || $remaining_status == 37, 1,
   'remaining child returns a valid status');
is($reaped_status + $remaining_status, 68,
   'waitpid(-1) and targeted wait preserve both statuses');

$pid = fork();
if ($pid == 0) {
    my $nested = fork();
    if ($nested == 0) {
        exit 41;
    }
    my $nested_waited = waitpid($nested, 0);
    exit($nested_waited == $nested && $? >> 8 == 41 ? 43 : 44);
}
else {
    is(waitpid($pid, 0), $pid, 'parent waits for nested pseudofork child');
    is($? >> 8, 43, 'nested child joined its own child before exit');
}

$pid = fork();
if ($pid == 0) {
    system($^X, '-e', 'exit 29');
    exit($? >> 8 == 29 ? 0 : 1);
}
else {
    is(waitpid($pid, 0), $pid, 'parent waits for child running system');
    is($? >> 8, 0, 'child can run system and preserve its result');
}

done_testing();

#!./perl

BEGIN {
    chdir 't' if -d 't';
    require './test.pl';
    set_up_inc('../lib');
    require Config;
    skip_all('no pseudofork')
        unless $Config::Config{d_pseudofork};
    skip_all('no POSIX::WNOHANG')
        unless eval 'use POSIX qw(WNOHANG); 1';
}

$| = 1;
watchdog(20);

my $parent_pid = $$;
my $pid = fork();
ok(defined $pid, 'fork creates a pseudo-child');
if ($pid == 0) {
    exit 17;
}
else {
    ok($pid < 0, 'pseudo-child has a negative PID');
    isnt($pid, $parent_pid, 'pseudo-child PID differs from parent PID');
    is(waitpid($pid, 0), $pid, 'waitpid returns the pseudo-child PID');
    is($? >> 8, 17, 'waitpid returns the child exit status');
    is($$, $parent_pid, 'parent interpreter remains usable');
}

$pid = fork();
if ($pid == 0) {
    sleep 1;
    exit 23;
}
else {
    is(waitpid($pid, WNOHANG), 0, 'WNOHANG does not reap a running child');
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

done_testing();


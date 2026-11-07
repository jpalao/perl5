use strict;
use warnings;
use Test::More;

plan skip_all => 'iOS embedded process semantics' unless $^O =~ /darwin-ios/;
require Errno;

my $result = system { $^X } 'different-argv0', '-e', 'exit 7';
my $child_status = $?;
my $native_status = ${^CHILD_ERROR_NATIVE};
is($result, 7 << 8, 'explicit program is selected independently of argv[0]');
is($child_status, 7 << 8, 'explicit program updates child status');
is($native_status, 7 << 8, 'explicit program updates native status');

my $empty_program = '';
$result = system { $empty_program } $^X, '-e', 'exit 8';
is($result, 8 << 8, 'empty explicit program falls back to argv[0]');

$! = 0;
$result = system { 'not-an-executable' } $^X, '-e', 'exit 0';
my $system_errno = 0 + $!;
$native_status = ${^CHILD_ERROR_NATIVE};
is($result, -1, 'invalid explicit program is not replaced by argv[0]');
is($native_status, -1, 'failed explicit program updates native status');
is($system_errno, Errno::ENOENT(), 'invalid explicit program sets ENOENT');

$! = 0;
{
    no warnings 'exec';
    $result = exec { $^X } $^X, '-e', 'exit 0';
}
my $exec_errno = 0 + $!;
is($result, 0, 'exec returns false when process replacement is unavailable');
is($exec_errno, Errno::ENOSYS(), 'unavailable exec sets ENOSYS');

done_testing();

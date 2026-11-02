use strict;
use warnings;
use Test::More;

plan skip_all => 'iOS piped-open behavior' unless $^O =~ /darwin-ios/;
require Errno;

my ($opened, $open_errno);
{
    local $! = 0;
    $opened = open my $pipe, 'ignored command |';
    $open_errno = 0 + $!;
}
ok(!$opened, 'single-string piped open is unsupported');
is($open_errno, Errno::ENOSYS(), 'single-string piped open sets ENOSYS');

{
    local $! = 0;
    $opened = open my $pipe, '-|', 'ignored command', 'argument';
    $open_errno = 0 + $!;
}
ok(!$opened, 'list-form piped open is unsupported');
is($open_errno, Errno::ENOSYS(), 'list-form piped open sets ENOSYS');

done_testing();

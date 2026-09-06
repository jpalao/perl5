use strict;
use warnings;

use Test::More;

BEGIN { require '../lib/ios.pm' if $^O =~ /darwin-ios/ }

if ($^O !~ /darwin-ios/) {
    plan skip_all => 'embedded Perl is only available on iOS';
}

plan tests => 12;

is_deeply(
    ios::_perl_switches_with_environment(['-I../lib']),
    ['-Mios', '-I../lib'],
    'embedded Perl preloads the iOS bridge',
);
is_deeply(
    ios::_perl_switches_with_environment(['-T', '-I../lib']),
    ['-T', '-Mios', '-I../lib'],
    'taint mode remains the first switch',
);
is_deeply(
    ios::_perl_switches_with_environment(['-Mios', '-I../lib']),
    ['-Mios', '-I../lib'],
    'an explicit bridge preload is not duplicated',
);

{
    local @INC = ('../lib');
    my $encoded = eval { ios::_json()->encode({ok => 1}) };
    ok(defined $encoded, 'preloaded JSON encoder survives local INC isolation')
        or diag $@;
}

my $exception = ios::_normalize_capture_result(undef, "native bridge failure\n");
is($exception->[0], 255 << 8, 'bridge exception has a defined wait status');
like(
    $exception->[1],
    qr/^iOS embedded Perl failed: native bridge failure\n\z/,
    'bridge exception is preserved in captured output',
);

my $missing_status = ios::_normalize_capture_result(
    [undef, 'captured child output'], undef);
is($missing_status->[0], 255 << 8, 'missing status becomes a failure status');
like(
    $missing_status->[1],
    qr/^captured child output\niOS embedded Perl failed: .*no wait status\n\z/,
    'captured output is retained when the wait status is missing',
);

{
    no warnings qw(once redefine);
    local *ios::exec_perl_capture = sub { die "capture failed\n" };

    my ($status, $output) = ios::exec_test('', ['perl', __FILE__]);
    is($status, 255 << 8, 'exec_test exception has a defined wait status');
    like($output, qr/^iOS embedded Perl failed: capture failed\n\z/,
        'exec_test exception is preserved in captured output');

    ($status, $output) = ios::exec_cli('', 'perl -e 1');
    is($status, 255 << 8, 'exec_cli exception has a defined wait status');
    like($output, qr/^iOS embedded Perl failed: capture failed\n\z/,
        'exec_cli exception is preserved in captured output');
}

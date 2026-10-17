use strict;
use warnings;
use Test::More;

if ($^O !~ /darwin-ios/) {
    plan skip_all => 'byte-backed stdin is only available on iOS';
}

my $bytes = "alpha\nbeta\0omega\n";
my ($status, $output) = @{ios::exec_perl_capture({
    prog => 'local $/; print <STDIN>',
    stdin_bytes => $bytes,
    switches => [],
    args => [],
})};

is($status, 0, 'embedded Perl exits successfully with byte-backed stdin');
is($output, $bytes, 'STDIN delivers the exact byte sequence');

my ($line_status, $line_output) = @{ios::exec_perl_capture({
    prog => 'print while <>',
    stdin_bytes => $bytes,
    switches => [],
    args => [],
})};

is($line_status, 0, 'readline loop exits successfully at EOF');
is($line_output, $bytes, '<> delivers bytes and reaches EOF');

done_testing();

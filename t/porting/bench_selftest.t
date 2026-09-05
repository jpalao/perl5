#!./perl -w

# run Porting/bench.pl's selftest

use strict;

chdir '..' if -f 'test.pl' && -f 'thread_it.pl';
require './t/test.pl';

if ($^O =~ /darwin-ios/) {
    # iOS cannot spawn $^X. Keep the helper's pure-Perl dependencies local
    # while capturing TAP from an embedded interpreter.
    local @INC = (@INC, 'lib', 'cpan/JSON-PP/lib');
    my ($result) = exec_perl_capture({
        pwd => '.',
        switches => ["-I.", "-MTestInit"],
        progfile => "Porting/bench.pl",
        args => ["--action=selftest"],
    });
    print $result->[1];
    exit $result->[0];
} else {
    system "$^X -I. -MTestInit Porting/bench.pl --action=selftest";
}


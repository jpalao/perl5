#!./perl -w

# run Porting/bench.pl's selftest

use strict;

chdir '..' if -f 'test.pl' && -f 'thread_it.pl';
require './t/test.pl';

if ($^O =~ /darwin-ios/) {
    exec_perl({
        pwd => getcwd(), 
        switches => ["-I.", "-MTestInit"], 
        progfile => "Porting/bench.pl",
        args => ["--action=selftest"]
    });
} else {
    system "$^X -I. -MTestInit Porting/bench.pl --action=selftest";
}


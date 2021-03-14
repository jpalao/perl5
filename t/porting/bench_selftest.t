#!./perl -w

# run Porting/bench.pl's selftest

use strict;

chdir '..' if -f 'test.pl' && -f 'thread_it.pl';
require './t/test.pl';

if (is_darwin_ios())
{
    use Cwd;
    use cbrunperl;    
    warn "getcwd(): " . getcwd() ."\n";
    exec_perl({
        pwd => getcwd(), 
        switches => ["-I.", "-MTestInit"], 
        progfile => "Porting/bench.pl",
        args => ["--action=selftest"]
    });
    chdir 't' if -d 't' && is_darwin_ios;
}
else
{
    system "$^X -I. -MTestInit Porting/bench.pl --action=selftest";
}



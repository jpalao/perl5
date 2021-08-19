#!perl
use strict;
use warnings;

require '../../t/test.pl';

use Config;
if (!$Config{useithreads}) {
    skip_all("keyword_plugin thread test requires threads");
}

plan(1);
my $runperl_args = $^O =~ /darwin-ios/ ? { 'switches' => ['-I', '../../lib'] } : {};
fresh_perl_is( <<'----', <<'====', $runperl_args, "loading XS::APItest in threads works");
use strict;
use warnings;

use threads;

require '../../t/test.pl';
watchdog(5);

for my $t (1 .. 3) {
    threads->create(sub {
        require XS::APItest;
    })->join;
}

print "all is well\n";
----
all is well
====

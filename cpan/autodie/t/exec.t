#!/usr/bin/perl -w
use strict;
use Test::More;

if ($^O =~ /darwin-ios/) {
    plan skip_all => 'exec() not supported';
    done_testing();
}

plan tests => 3;

eval {
    use autodie qw(exec);
    exec("this_command_had_better_not_exist", 1);
};

isa_ok($@,"autodie::exception", "failed execs should die");
ok($@->matches('exec'), "exception should match exec");
ok($@->matches(':system'), "exception should match :system");

#!perl

# Backticks run a nested interpreter in the same process.  Creating and
# destroying it must leave the caller's cache of user-defined \p{}
# properties intact.

use strict;
use warnings;
use Test::More;

my ($perl) = $^X =~ /\A(.*)\z/s;
plan skip_all => 'interpreter path requires shell-specific quoting'
    if !length($perl) || $perl =~ m{[^A-Za-z0-9_./-]};

my $iterations = 20;
plan tests => 2 * $iterations + 4;

our $calls = 0;
sub IsCounted { $calls++; return "0041\n" }

ok(eval q{'A' =~ /\p{IsCounted}/}, 'user-defined property matches');

is(`$perl -le 'sub IsCounted { qq(0042\\n) } print q(B) =~ /\\p{IsCounted}/ ? 1 : 0'`,
    "1\n", 'nested interpreter uses its own property definition');

for my $i (1 .. $iterations) {
    is(`$perl -le "print 1"`, "1\n", "nested interpreter $i runs");

    no strict 'refs';
    *{"main::IsNew$i"} = sub { "0042\n" };
    ok(eval qq{'B' =~ /\\p{IsNew$i}/},
        "new property $i works after a nested interpreter");
}

ok(eval q{'A' =~ /\p{IsCounted}/}, 'cached property still matches');
is($calls, 1, 'property definition is still cached');

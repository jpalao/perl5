#!perl

# iOS has no /bin/sh, so backticks and single-string system() are split by
# the embedded runner.  The result must match POSIX sh: inside double quotes
# a backslash only escapes $ ` " \ and newline.

use strict;
use warnings;
use Test::More;

my ($perl) = $^X =~ /\A(.*)\z/s;
plan skip_all => 'interpreter path requires shell-specific quoting'
    if !length($perl) || $perl =~ m{[^A-Za-z0-9_./-]};

my @readpipe = (
    [ q{-le "print q(a\pb)"},   "a\\pb\n", 'other backslashes are kept' ],
    [ q{-le "print q(a\\\\b)"}, "a\\b\n",  'backslash escapes backslash' ],
    [ q{-le "print q(a\"b)"},   "a\"b\n",  'backslash escapes double quote' ],
    [ q{-le "print q(a\$b)"},   "a\$b\n",  'backslash escapes dollar' ],
    [ q{-le "print q(a\`b)"},   "a`b\n",   'backslash escapes backtick' ],
    [ q{-le "print q(x\ny)"},   "x\\ny\n", 'backslash before n is kept' ],
    [ q{-le 'print q(a\pb)'},   "a\\pb\n", 'single quotes keep backslashes' ],
);
my @system = (
    [ q{-e "exit length q(a\pb)"},   4, 'other backslashes are kept' ],
    [ q{-e "exit length q(a\\\\b)"}, 3, 'backslash escapes backslash' ],
    [ q{-e "exit length q(a\"b)"},   3, 'backslash escapes double quote' ],
);

plan tests => @readpipe + @system;

for my $case (@readpipe) {
    my ($args, $expected, $name) = @$case;
    is(scalar `$perl $args`, $expected, "backticks: $name");
}

for my $case (@system) {
    my ($args, $expected, $name) = @$case;
    system("$perl $args");
    is($? >> 8, $expected, "system: $name");
}

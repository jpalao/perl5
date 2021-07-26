#!/usr/bin/perl -w
use strict;
use warnings;
use Config;

use Test2::Util qw/CAN_FORK/;
BEGIN {
    unless(CAN_FORK && $Config{'archname'} !~ /darwin-ios/) {
        require Test::More;
        Test::More->import(skip_all => "fork is not supported");
    }
}

BEGIN {
    if( $ENV{PERL_CORE} ) {
        chdir 't';
        use lib '../lib';
    }
}

use Test::More;
plan tests => 1;

if( fork ) { # parent
    pass("Only the parent should process the ending, not the child");
}
else {
    exit;   # child
}


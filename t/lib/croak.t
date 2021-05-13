#!./perl

chdir 't' if -d 't';
use lib '../lib';

$FATAL = 1; # we expect all the tests to croak
require "../t/lib/common.pl";

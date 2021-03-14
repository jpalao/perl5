#!./perl

chdir 't' if -d 't';
use lib ( '.', '../lib' );

our $UTF8 = (${^OPEN} || "") =~ /:utf8/;
require "../t/lib/common.pl";

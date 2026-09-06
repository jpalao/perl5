#!./perl

chdir 't' if -d 't';
@INC = $^O =~ /darwin-ios/ ? ('.', '../lib', @INC) : ('.', '../lib');

our $UTF8 = (${^OPEN} || "") =~ /:utf8/;
require "../t/lib/common.pl";

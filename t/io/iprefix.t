#!./perl
use strict;
chdir 't' if -d 't';
require './test.pl';

$^I = 'bak.*';

# Modified from the original inplace.t to test adding prefixes

plan( tests => 2 );

my @tfiles     = (tempfile(), tempfile(), tempfile());
my @tfiles_bak = map "bak.$_", @tfiles;

END { unlink_all(@tfiles_bak); }

for my $file (@tfiles) {
    my $result = runperl( prog => 'print qq(foo\n);');
    open my $fh, '>', $file or die "Cannot open >$file: $!";
    print $fh $result;
    close $fh;
}

@ARGV = @tfiles;

while (<>) {
    s/foo/bar/;
}
continue {
    print;
}

is ( runperl( prog => 'print<>;', args => \@tfiles ),
     "bar\nbar\nbar\n", 
     "file contents properly replaced" );

is ( runperl( prog => 'print<>;', args => \@tfiles_bak ), 
     "foo\nfoo\nfoo\n", 
     "backup file contents stay the same" );


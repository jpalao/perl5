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

sub create_input_file {
    my ($file, $prog) = @_;
    if ($^O eq 'darwin-ios') {
        my $result = runperl(prog => $prog);
        open my $fh, '>', $file or die "Cannot open >$file: $!";
        print $fh $result or die "Cannot write >$file: $!";
        close $fh or die "Cannot close >$file: $!";
    } else {
        runperl(prog => $prog, args => ['>', $file]);
    }
}

for my $file (@tfiles) {
    create_input_file($file, 'print qq(foo\n);');
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

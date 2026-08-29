use strict;
use warnings;
use Config;
use Cwd qw(abs_path getcwd);
use File::Copy qw(copy);
use File::Path qw(make_path remove_tree);
use File::Spec;
use Test::More;

if ($^O !~ /darwin-ios/) {
    plan skip_all => 'embedded make is only available on iOS';
}

require ios;

my $fixture_source = abs_path(File::Spec->catdir(
    getcwd(), 't', 'fixtures', 'Perla-Pure'));
my $documents = abs_path(File::Spec->catdir(getcwd(), File::Spec->updir()));
my $fixture = File::Spec->catdir($documents, 'Perla-Pure-work');
my $blib = File::Spec->catdir($fixture, 'blib');
my $makefile = File::Spec->catfile($fixture, 'Makefile');
my $marker = File::Spec->catfile($fixture, 'pm_to_blib');
my $cwd_marker = File::Spec->catfile($fixture, 'nested-cwd.txt');

remove_tree($fixture);
make_path(File::Spec->catdir($fixture, 'lib', 'Perla'));
copy(File::Spec->catfile($fixture_source, 'Makefile.PL'), $makefile . '.PL')
    or die "Could not copy Makefile.PL: $!";
copy(
    File::Spec->catfile($fixture_source, 'lib', 'Perla', 'Pure.pm'),
    File::Spec->catfile($fixture, 'lib', 'Perla', 'Pure.pm'),
) or die "Could not copy Pure.pm: $!";

my $probe = ios::exec_perl({
    pwd => $fixture,
    prog => 'use Cwd qw(getcwd); open my $fh, q{>}, q{nested-cwd.txt} or die $!; print {$fh} getcwd();',
    switches => [],
    args => [],
});
is($probe, 0, 'nested Perl can write in requested directory');
open my $cwd_fh, '<', $cwd_marker or die "Could not read $cwd_marker: $!";
is(<$cwd_fh>, $fixture, 'nested Perl uses requested directory');
close $cwd_fh;

my $generate = ios::exec_perl({
    pwd => $fixture,
    progfile => 'Makefile.PL',
    switches => [],
    args => ['PERL=perl', 'FULLPERL=perl'],
});
is($generate, 0, 'Makefile.PL succeeds');
ok(-f $makefile, 'Makefile is generated');

is(ios::make($fixture, 'pure_all'), 0, 'embedded make pure_all succeeds');
ok(-f File::Spec->catfile($blib, 'lib', 'Perla', 'Pure.pm'),
    'module is copied into blib');

my $load = ios::exec_perl({
    pwd => $fixture,
    prog => 'use Perla::Pure; die unless Perla::Pure::proof() eq q{embedded-make-ok};',
    switches => ['-Iblib/lib'],
    args => [],
});
is($load, 0, 'module loads from blib');

done_testing();
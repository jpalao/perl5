use strict;
use warnings;
use Config;
use Cwd qw(abs_path getcwd);
use File::Copy qw(copy);
use File::Path qw(make_path remove_tree);
use File::Spec;
use Test::More;

BEGIN { require ios if $^O =~ /darwin-ios/ }

if ($^O !~ /darwin-ios/) {
    plan skip_all => 'embedded make is only available on iOS';
}

my $fixture_source = abs_path(File::Spec->catdir(
    getcwd(), 't', 'fixtures', 'Perla-Pure'));
my $fixture = File::Spec->catdir(File::Spec->tmpdir(), 'Perla-Pure-work');
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

my $old_pwd = getcwd();
chdir $fixture or die "Could not chdir to $fixture: $!";
my $make_output = qx{"$Config{make}" pure_all 2>&1};
my $make_status = $?;
chdir $old_pwd or die "Could not restore directory $old_pwd: $!";
is($make_status, 0, 'embedded make backtick status succeeds');
like($make_output, qr/\bPure\.pm\b/,
    'embedded make backticks capture recipe output');
ok(-f File::Spec->catfile($blib, 'lib', 'Perla', 'Pure.pm'),
    'module is copied into blib');
is(ios::make($fixture, 'pure_all'), 0,
    'embedded make can run repeatedly');

my $load = ios::exec_perl({
    pwd => $fixture,
    prog => 'use Perla::Pure; die unless Perla::Pure::proof() eq q{embedded-make-ok};',
    switches => ['-Iblib/lib'],
    args => [],
});
is($load, 0, 'module loads from blib');

done_testing();
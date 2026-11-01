use strict;
use warnings;

use File::Copy qw(copy);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use IPC::Open3;
use Symbol qw(gensym);
use Test::More;

plan skip_all => 'host-only test: requires subprocess execution'
    if $^O eq 'darwin-ios';

my $source = File::Spec->rel2abs(File::Spec->catdir($FindBin::Bin, '..', '..', '..'));
my $runner = File::Spec->catfile($source, 'ios', 'test', 'ios_harness');
my $temp = tempdir('perl-ios-discovery-XXXXXXXX', TMPDIR => 1, CLEANUP => 1);
my $root = "$temp/tree";
my $stubs = "$temp/stubs";

sub write_file {
    my ($path, $content) = @_;
    open my $file, '>', $path or die "Cannot write $path: $!";
    print {$file} $content or die "Cannot write $path: $!";
    close $file or die "Cannot close $path: $!";
}

for my $directory (qw(base comp run cmd io re opbasic op uni mro lib porting perf)) {
    make_path("$root/t/$directory");
}
make_path(
    "$root/ext/ios/t/nested", "$root/dist/Example/t",
    "$root/ios/ios/CPAN/t", "$root/ios/test/t",
    "$stubs/TAP/Parser/Iterator", "$stubs/TAP/Parser/SourceHandler",
);
copy("$source/t/TEST", "$root/t/TEST") or die "Cannot copy t/TEST: $!";
write_file("$root/t/harness", 'print "$_\n" for @ARGV; 1;' . "\n");
write_file("$root/config.sh",
    "extensions='ios Example ExtUtils/MakeMaker Test/Harness IPC/Cmd'\n"
    . "known_extensions='ios Example ExtUtils/MakeMaker Test/Harness IPC/Cmd'\n");
write_file("$root/MANIFEST", <<'MANIFEST');
dist/Example/t/example.t                 Example test
ext/ios/t/listed.t                       Listed iOS test
cpan/ExtUtils-MakeMaker/t/basic.t         Unsupported make test
cpan/Test-Harness/t/basic.t              Unsupported pipe test
cpan/IPC-Cmd/t/01_IPC-Cmd.t              Unsupported pipeline test
ios/ios/CPAN/t/source-only.t             Source copy, not the generated extension
ios/test/t/host-only.t                   Host-only test
MANIFEST

for my $file (qw(
    t/base/basic.t dist/Example/t/example.t
    ext/ios/t/listed.t ext/ios/t/unlisted.t ext/ios/t/nested/extra.t
    ext/ios/t/fixture.txt ios/ios/CPAN/t/source-only.t ios/test/t/host-only.t
)) {
    write_file("$root/$file", "");
}
for my $module (qw(ios TAP::Parser::Iterator::iOS
                   TAP::Parser::SourceHandler::iOSExecutable
                   TAP::Parser::SourceHandler::iOSPerl)) {
    (my $path = $module) =~ s{::}{/}g;
    write_file("$stubs/$path.pm", "package $module;\n1;\n");
}

sub run_harness {
    my @arguments = @_;
    my $stderr = gensym;
    my $pid = open3(my $in, my $out, $stderr, $^X, "-I$stubs", '-e',
        'my ($directory, $runner) = splice @ARGV, 0, 2;'
        . 'chdir $directory or die "Cannot chdir: $!";'
        . 'do $runner; die $@ if $@; die "Harness did not exit\n";',
        "$root/t", $runner, @arguments);
    close $in;
    local $/;
    my $stdout = <$out> // '';
    my $errors = <$stderr> // '';
    waitpid($pid, 0);
    return ($?, [split /\n/, $stdout], $errors);
}

my @expected = qw(
    base/basic.t
    ../dist/Example/t/example.t
    ../ext/ios/t/listed.t
    ../ext/ios/t/nested/extra.t
    ../ext/ios/t/unlisted.t
);
my ($status, $selected, $errors) = run_harness();
is($status, 0, 'default discovery succeeds') or diag $errors;
is($errors, '', 'default discovery emits no warnings');
is_deeply($selected, \@expected,
    'core, manifest and iOS tests are selected once; host tests and fixtures are excluded');

($status, $selected, $errors) = run_harness('-v');
is($status, 0, 'option-only discovery succeeds') or diag $errors;
is($errors, '', 'option-only discovery emits no warnings');
is_deeply($selected, ['-v', @expected], 'discovery preserves harness options');

($status, $selected, $errors) = run_harness('-v', '../ext/ios/t/unlisted.t');
is($status, 0, 'explicit selection succeeds') or diag $errors;
is($errors, '', 'explicit selection emits no warnings');
is_deeply($selected, ['-v', '../ext/ios/t/unlisted.t'],
    'explicit selection is not expanded');

rename "$root/ext/ios/t", "$root/ext/ios/saved"
    or die "Cannot move fixture test directory: $!";
($status, $selected, $errors) = run_harness();
isnt($status, 0, 'missing generated iOS tests fail discovery');
like($errors, qr/Trouble opening \.\.\/ext\/ios\/t:/,
    'missing test directory is reported explicitly');

done_testing();

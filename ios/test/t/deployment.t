use strict;
use warnings;

use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use IPC::Open3;
use Symbol qw(gensym);
use Test::More;

plan skip_all => 'requires a Unix shell' if $^O eq 'MSWin32';

my $source = File::Spec->rel2abs(File::Spec->catdir($FindBin::Bin, '..', '..', '..'));
my $script = File::Spec->catfile($source, 'ios', 'test.sh');
my $direct_build = File::Spec->catfile($source, 'ios', 'build.sh');
my $temp = tempdir('perl-ios-deployment-XXXXXXXX', TMPDIR => 1, CLEANUP => 1);
my $bin = "$temp/bin";
make_path($bin);

my $setup = "$temp/setup.sh";
open my $setup_file, '>', $setup or die "$setup: $!";
close $setup_file or die "$setup: $!";

my $build_stub = "$temp/build.sh";
open my $build_file, '>', $build_stub or die "$build_stub: $!";
print {$build_file} <<'BUILD';
#!/bin/sh
printf '%s\n%s\n' "$IOS_DEPLOYMENT_TARGET" "$MIN_VERSION" > "$MOCK_WORK/build-env"
exit 0
BUILD
close $build_file or die "$build_stub: $!";

my $mock = "$bin/mock";
open my $mock_file, '>', $mock or die "$mock: $!";
print {$mock_file} "#!$^X\n";
print {$mock_file} <<'MOCK';
use strict;
use warnings;
use File::Basename qw(basename dirname);
use File::Copy qw(copy);
use File::Path qw(make_path);

my $command = basename($0);
if ($command eq 'git') {
    if (grep { $_ eq 'clone' } @ARGV) {
        my $build = $ARGV[-1];
        die "build path is outside the fixture" unless index($build, "$ENV{MOCK_WORK}/") == 0;
        make_path("$build/ios/test", "$build/t");
        copy($ENV{MOCK_BUILD_STUB}, "$build/ios/build.sh") or die $!;
        for my $file (qw(
            lib/auto/XS/APItest/APItest.bs
            lib/auto/XS/APItest/APItest.bundle
            lib/auto/XS/Typemap/Typemap.bundle
            lib/XS/APItest.pm
            lib/TAP/Parser/Iterator/iOS.pm
            lib/TAP/Parser/SourceHandler/iOSExecutable.pm
            lib/TAP/Parser/SourceHandler/iOSPerl.pm
        )) {
            make_path(dirname("$build/$file"));
            open my $output, '>', "$build/$file" or die $!;
            close $output or die $!;
        }
        open my $output, '>', "$ENV{MOCK_WORK}/git-env" or die $!;
        print {$output} "$ENV{IOS_DEPLOYMENT_TARGET}\n$ENV{MIN_VERSION}\n";
        close $output or die $!;
    } elsif (grep { $_ eq 'rev-parse' } @ARGV) {
        print "fixture-revision\n";
    }
    exit 0;
}
if ($command eq 'awk') {
    open my $output, '>', "$ENV{MOCK_WORK}/direct-build-env" or die $!;
    print {$output} "$ENV{IOS_DEPLOYMENT_TARGET}\n$ENV{MIN_VERSION}\n";
    close $output or die $!;
    print "37\n";
    exit 0;
}
if ($command eq 'xcodebuild') {
    open my $output, '>', "$ENV{MOCK_WORK}/xcode-args" or die $!;
    print {$output} "$_\n" for @ARGV;
    close $output or die $!;
    exit 19;
}
die "unexpected external command: $command";
MOCK
close $mock_file or die "$mock: $!";
chmod 0755, $mock or die "chmod $mock: $!";
for my $name (qw(awk git xcodebuild xcrun)) {
    symlink 'mock', "$bin/$name" or die "symlink $name: $!";
}

sub read_file {
    my ($path) = @_;
    return undef unless -f $path;
    open my $input, '<', $path or die "$path: $!";
    local $/;
    return <$input>;
}

sub run_script {
    my ($name, $extra_env) = @_;
    my $work = "$temp/$name";
    make_path($work);
    local %ENV = (
        PATH => "$bin:/usr/bin:/bin:/usr/sbin:/sbin",
        HOME => $temp,
        IOS_SETUP_FILE => $setup,
        PERL_IOS_WORKDIR => $work,
        PERL5_SOURCE_ROOT => $source,
        MACOS_PERL_PATH => $^X,
        HARNESS_APP_ID => 'net.example.fixture',
        SIMULATOR_DEVICE_UUID => 'fixture-simulator',
        IOS_TEST_APP => 'foundation-runner',
        BUILD_CAMELBONES => 0,
        MOCK_WORK => $work,
        MOCK_BUILD_STUB => $build_stub,
        %$extra_env,
    );
    my $stderr = gensym;
    my $pid = open3(my $in, my $out, $stderr, '/bin/bash', $script);
    close $in;
    local $/;
    my $stdout = <$out> // '';
    my $errors = <$stderr> // '';
    waitpid($pid, 0);
    return ($? >> 8, $stdout, $errors, $work);
}

for my $case (
    [ default => { HARNESS_TARGET => 'iphonesimulator' }, '12.0', 'IPHONEOS' ],
    [ ios => { HARNESS_TARGET => 'iphonesimulator', IOS_DEPLOYMENT_TARGET => '10.1' },
      '10.1', 'IPHONEOS' ],
    [ tv => { HARNESS_TARGET => 'appletvsimulator', MIN_VERSION => '11.2' },
      '11.2', 'TVOS' ],
    [ watch => { HARNESS_TARGET => 'watchsimulator', IOS_DEPLOYMENT_TARGET => '9.0' },
      '9.0', 'WATCHOS' ],
    [ matching => { HARNESS_TARGET => 'iphonesimulator',
                    IOS_DEPLOYMENT_TARGET => '13.0', MIN_VERSION => '13.0' },
      '13.0', 'IPHONEOS' ],
) {
    my ($name, $env, $version, $platform) = @$case;
    subtest $name => sub {
        my ($status, $stdout, $stderr, $work) = run_script($name, $env);
        is($status, 19, 'stops at the mocked Xcode build') or diag "$stdout\n$stderr";
        is(read_file("$work/git-env"), "$version\n$version\n",
            'test and compiler deployment targets match during setup');
        is(read_file("$work/build-env"), "$version\n$version\n",
            'build script receives both deployment targets');
        like(read_file("$work/xcode-args") // '',
            qr/^\Q${platform}_DEPLOYMENT_TARGET=$version\E$/m,
            'harness receives the same platform deployment target');
        done_testing;
    };
}

subtest 'conflicting targets' => sub {
    my ($status, $stdout, $stderr, $work) = run_script('conflict', {
        HARNESS_TARGET => 'iphonesimulator',
        IOS_DEPLOYMENT_TARGET => '10.0',
        MIN_VERSION => '12.0',
    });
    is($status, 1, 'rejects conflicting values');
    like($stderr, qr/IOS_DEPLOYMENT_TARGET and MIN_VERSION must match/,
        'reports the conflict');
    ok(!-e "$work/git-env" && !-e "$work/xcode-args",
        'rejects the conflict before preparing or installing anything');
    done_testing;
};

subtest 'direct build target settings' => sub {
    for my $case (
        [ default => {}, '12.0' ],
        [ min_version => { MIN_VERSION => '11.2' }, '11.2' ],
        [ deployment_target => { IOS_DEPLOYMENT_TARGET => '10.1' }, '10.1' ],
        [ matching => { IOS_DEPLOYMENT_TARGET => '13.0', MIN_VERSION => '13.0' },
          '13.0' ],
    ) {
        my ($name, $extra_env, $version) = @$case;
        my $work = "$temp/direct-$name";
        make_path($work);
        local %ENV = (
            PATH => "$bin:/usr/bin:/bin:/usr/sbin:/sbin",
            HOME => $temp,
            MOCK_WORK => $work,
            IOS_TARGET => 'invalid',
            %$extra_env,
        );
        my $stderr = gensym;
        my $pid = open3(my $in, my $out, $stderr, '/bin/sh', $direct_build);
        close $in;
        local $/;
        my $stdout = <$out> // '';
        my $errors = <$stderr> // '';
        waitpid($pid, 0);
        is($? >> 8, 1, "$name stops before creating build directories")
            or diag "$stdout\n$errors";
        like($errors, qr/Unsupported target SDK/, "$name reaches target validation");
        is(read_file("$work/direct-build-env"), "$version\n$version\n",
            "$name exports matching deployment targets");
    }

    my $work = "$temp/direct-conflict";
    make_path($work);
    local %ENV = (
        PATH => "$bin:/usr/bin:/bin:/usr/sbin:/sbin",
        HOME => $temp,
        MOCK_WORK => $work,
        IOS_TARGET => 'invalid',
        IOS_DEPLOYMENT_TARGET => '10.0',
        MIN_VERSION => '12.0',
    );
    my $stderr = gensym;
    my $pid = open3(my $in, my $out, $stderr, '/bin/sh', $direct_build);
    close $in;
    local $/;
    my $stdout = <$out> // '';
    my $errors = <$stderr> // '';
    waitpid($pid, 0);
    is($? >> 8, 1, 'direct build rejects conflicting targets') or diag $stdout;
    like($errors, qr/IOS_DEPLOYMENT_TARGET and MIN_VERSION must match/,
        'direct build reports the conflict');
    ok(!-e "$work/direct-build-env", 'direct build rejects the conflict before setup');
    done_testing;
};

subtest 'Darwin hints and deployment settings' => sub {
    my $tools = "$temp/hints-tools";
    make_path($tools);
    my $compiler = "$tools/cc";
    open my $compiler_file, '>', $compiler or die "$compiler: $!";
    print {$compiler_file} "#!/bin/sh\nprintf 'fixture compiler\\n' >&2\nexit 1\n";
    close $compiler_file or die "$compiler: $!";
    chmod 0755, $compiler or die "chmod $compiler: $!";

    my $sw_vers = "$tools/sw_vers";
    open my $sw_vers_file, '>', $sw_vers or die "$sw_vers: $!";
    print {$sw_vers_file} <<'SW_VERS';
#!/bin/sh
printf 'called\n' >> "$HINTS_MARKER"
printf 'ProductVersion:\t13.7.1\n'
SW_VERS
    close $sw_vers_file or die "$sw_vers: $!";
    chmod 0755, $sw_vers or die "chmod $sw_vers: $!";

    my $program = <<'SHELL';
cd "$1" || exit 1
src=$2
cc=$3
define=define
d_syscall=define
darwin_distribution=undef
optimize=-O2
ccflags=target-cc
ldflags=target-ld
exec 4>&1
. "$src/hints/darwin.sh"
printf 'ccflags=%s\nld=%s\nldflags=%s\nlddlflags=%s\nd_syscall=%s\n' \
    "$ccflags" "$ld" "$ldflags" "$lddlflags" "$d_syscall"
SHELL

    for my $case (
        [ mobile_empty => 'darwin-ios', '', '', 0, 'define', undef, 0 ],
        [ mobile_invalid_macos => 'darwin-ios', '', 'invalid', 0, 'define', undef, 0 ],
        [ mobile_version => 'darwin-ios', '22.0.0', '10.11', 0, 'define', undef, 0 ],
        [ mobile_old_version => 'darwin-ios', '8.0.0', '10.11', 0, 'define', undef, 0 ],
        [ native_new => '', '22.0.0', '10.11', 0, 'undef', '10.11', 1 ],
        [ native_old => '', '15.0.0', '10.11', 0, 'define', '10.11', 0 ],
        [ native_legacy => '', '8.0.0', '', 0, 'define', undef, 0 ],
        [ native_default => '', '22.0.0', '', 0, 'undef', '13.7', 0 ],
        [ other_runner => 'remote', '22.0.0', '10.11', 0, 'undef', '10.11', 1 ],
        [ native_invalid => '', '22.0.0', 'invalid', 1, undef, undef, 0 ],
    ) {
        my ($name, $runner, $osvers, $deployment, $exit, $syscall,
            $minimum, $old_clock) = @$case;
        my $work = "$temp/hints-$name";
        make_path("$work/UU");
        local %ENV = (
            PATH => "$tools:/usr/bin:/bin",
            HOME => $temp,
            HINTS_MARKER => "$work/sw-vers-calls",
            targetrun => $runner,
            osvers => $osvers,
            MACOSX_DEPLOYMENT_TARGET => $deployment,
        );
        my $stderr = gensym;
        my $pid = open3(my $in, my $out, $stderr, '/bin/sh', '-c', $program,
                        'darwin-hints', $work, $source, $compiler);
        close $in;
        local $/;
        my $stdout = <$out> // '';
        my $errors = <$stderr> // '';
        waitpid($pid, 0);
        is($?, $exit << 8, "$name exits as expected") or diag "$stdout\n$errors";
        is($errors, '', "$name emits no shell warnings");
        if ($exit) {
            like($stdout, qr/Unexpected MACOSX_DEPLOYMENT_TARGET=invalid/,
                "$name rejects an invalid macOS deployment target");
            next;
        }
        like($stdout, qr/^d_syscall=\Q$syscall\E$/m, "$name keeps the right syscall hint");
        like($stdout, qr/^lddlflags=target-ld(?: .*)? -bundle -undefined dynamic_lookup$/m,
            "$name keeps bundle linker flags");
        if (defined $minimum) {
            like($stdout, qr/^ccflags=.*-mmacosx-version-min=\Q$minimum\E(?: |$)/m,
                "$name selects the expected macOS minimum");
            ok(-e "$work/sw-vers-calls", "$name checks the macOS product version");
        } else {
            unlike($stdout, qr/-mmacosx-version-min|_DARWIN_FEATURE_CLOCK_GETTIME/,
                "$name does not inherit macOS deployment settings");
            if ($runner eq 'darwin-ios') {
                like($stdout, qr/^ld=\Q$compiler\E$/m, "$name leaves the linker unchanged");
            } else {
                like($stdout, qr/^ld=env MACOSX_DEPLOYMENT_TARGET=10\.3 \Q$compiler\E$/m,
                    "$name retains the legacy macOS linker setting");
            }
            ok(!-e "$work/sw-vers-calls", "$name does not inspect the host macOS version");
        }
        if ($old_clock) {
            like($stdout, qr/-D_DARWIN_FEATURE_CLOCK_GETTIME=0/,
                "$name retains the legacy clock workaround");
        } else {
            unlike($stdout, qr/-D_DARWIN_FEATURE_CLOCK_GETTIME=0/,
                "$name does not enable the legacy clock workaround");
        }
    }
    done_testing;
};

done_testing;

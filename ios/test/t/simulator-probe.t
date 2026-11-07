use strict;
use warnings;

use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);
use FindBin;
use IPC::Open3;
use Symbol qw(gensym);
use Test::More;

plan skip_all => 'host-only test: requires a Unix shell'
    if $^O eq 'darwin-ios' || $^O eq 'MSWin32';

my $source = File::Spec->rel2abs(File::Spec->catdir($FindBin::Bin, '..', '..', '..'));
my $runner = File::Spec->catfile($source, 'Cross', 'run-ios');

sub read_file {
    my ($path) = @_;
    open my $input, '<', $path or die "$path: $!";
    local $/;
    return <$input>;
}

sub write_file {
    my ($path, $content) = @_;
    open my $output, '>', $path or die "$path: $!";
    print {$output} $content or die "$path: $!";
    close $output or die "$path: $!";
}

my $runner_source = read_file($runner);

# Exercise the runner's simulator packaging and no-environment execution path.
my ($packaging) = $runner_source =~
    /^(bundle_root=\$IOS_PROBE_BUILD_ROOT\/probe\.app\n.*?)(?=^    set \+e\n    if \[ -n "\$env_spec" \])/ms;
my ($spawn) = $runner_source =~ /^        (xcrun simctl spawn .*?)$/m;
my ($filter) = $runner_source =~ /^    (sed -e .*? "\$IOS_PROBE_BUILD_ROOT\/output")$/m;
BAIL_OUT('Cannot locate simulator probe commands')
    unless defined $packaging && defined $spawn && defined $filter;

my $temp = tempdir('perl-ios-probe-XXXXXXXX', TMPDIR => 1, CLEANUP => 1);
my $bin = "$temp/bin";
my $sdk = "$temp/sdk";
make_path($bin, "$sdk/Library/Application Support/WatchKit");
write_file("$sdk/Library/Application Support/WatchKit/WK", "watch stub\n");

my $fixture = "$temp/simulator-probe.sh";
write_file($fixture, "#!/bin/sh\nset -eu\n$packaging"
    . "    set +e\n    $spawn\n    status=\$?\n    set -e\n"
    . "    $filter\n    exit \"\$status\"\nfi\n");

my $xcrun = "$bin/xcrun";
write_file($xcrun, <<'SHELL');
#!/bin/sh
set -eu
if [ "$#" -lt 3 ] || [ "$1" != simctl ] || [ "$3" != "$IOS_DEVICE_UUID" ]; then
    echo "unexpected simctl arguments" >&2
    exit 64
fi
printf '%s\n' "$2" >> "$MOCK_WORK/trace"
case "$2" in
    uninstall)
        [ "$4" = "$probe_bundle_id" ] || exit 65
        [ "$MOCK_FAIL" != uninstall ] || exit 17
        ;;
    install)
        [ -f "$4/Info.plist" ] || exit 66
        if [ "$MOCK_FAIL" = install ]; then
            echo "fixture install failure" >&2
            exit 19
        fi
        printf '%s\n' "$4" > "$MOCK_WORK/container"
        ;;
    get_app_container)
        [ "$4" = "$probe_bundle_id" ] && [ "$5" = app ] || exit 67
        cat "$MOCK_WORK/container"
        ;;
    spawn)
        [ -f "$4" ] || exit 68
        printf '%s\n' "$4" > "$MOCK_WORK/spawn-path"
        shift 4
        printf '%s\n' "$@" > "$MOCK_WORK/spawn-args"
        if [ "$MOCK_FAIL" = spawn ]; then
            echo "fixture spawn failure" >&2
            exit 23
        fi
        printf 'Ok\nExit status: 0\n'
        ;;
    *)
        echo "unexpected simctl command: $2" >&2
        exit 69
        ;;
esac
SHELL
chmod 0755, $xcrun or die "chmod $xcrun: $!";

my $codesign = "$bin/codesign";
write_file($codesign, <<'SHELL');
#!/bin/sh
echo "unexpected simulator signing" >&2
printf 'called\n' > "$MOCK_WORK/codesign"
exit 70
SHELL
chmod 0755, $codesign or die "chmod $codesign: $!";

sub run_probe {
    my ($name, $platform, $failure) = @_;
    my $work = "$temp/$name with spaces";
    my $root = "$work/build";
    make_path($work);
    my $executable = "$work/try";
    write_file($executable, "probe executable\n");
    local %ENV = (
        PATH => "$bin:/usr/bin:/bin",
        IOS_PROBE_BUILD_ROOT => $root,
        IOS_PLATFORM => $platform,
        IOS_SDKROOT => $sdk,
        IOS_DEVICE_UUID => 'fixture-simulator',
        simulator_probe => 'true',
        executable_path => $executable,
        probe_bundle_id => 'net.example.fixture',
        watch_companion_bundle_id => 'net.example.watch',
        MOCK_WORK => $work,
        MOCK_FAIL => $failure,
    );
    my $output = gensym;
    my $pid = open3(my $in, $output, $output, '/bin/sh', $fixture,
        'argument with spaces', 'second-argument');
    close $in;
    my $combined = do { local $/; <$output> // '' };
    waitpid($pid, 0);
    return ($?, $combined, $work, $root);
}

for my $platform (qw(iphonesimulator appletvsimulator watchsimulator)) {
    subtest "$platform unsigned probe" => sub {
        my ($status, $output, $work, $root) = run_probe($platform, $platform, '');
        is($status, 0, 'probe succeeds');
        is($output, "Ok\n", 'combined output matches the Configure coherency check');
        ok(!-e "$work/codesign", 'does not invoke codesign');
        is(read_file("$work/trace"), "uninstall\ninstall\nget_app_container\nspawn\n",
            'installs and runs the simulator probe');
        my $probe = $platform eq 'watchsimulator'
            ? "$root/probe.app/PlugIns/probe.appex/probe" : "$root/probe.app/probe";
        is(read_file("$work/spawn-path"), "$probe\n", 'runs the packaged executable');
        is(read_file($probe), "probe executable\n", 'copies the probe without modification');
        is(read_file("$work/spawn-args"), "argument with spaces\nsecond-argument\n",
            'passes executable arguments unchanged');
        if ($platform eq 'watchsimulator') {
            is(read_file("$root/probe.app/probe-app"), "watch stub\n",
                'copies the WatchKit app stub');
            ok(-f "$root/probe.app/PlugIns/probe.appex/Info.plist",
                'creates the Watch extension bundle');
        }
    };
}

subtest 'simulator installation failure' => sub {
    my ($status, $output, $work) = run_probe('install-failure', 'watchsimulator', 'install');
    isnt($status, 0, 'installation failure stops the runner');
    like($output, qr/fixture install failure/, 'installation error remains visible');
    is(read_file("$work/trace"), "uninstall\ninstall\n", 'does not run a failed installation');
};

subtest 'simulator execution failure' => sub {
    my ($status, $output, $work) = run_probe('spawn-failure', 'watchsimulator', 'spawn');
    is($status >> 8, 23, 'returns the probe execution status');
    is($output, "fixture spawn failure\n", 'execution error remains visible');
    ok(!-e "$work/codesign", 'does not invoke codesign');
};

subtest 'missing previous simulator app' => sub {
    my ($status, $output, $work) = run_probe('uninstall-failure', 'watchsimulator', 'uninstall');
    is($status, 0, 'continues if the previous app cannot be uninstalled');
    is($output, "Ok\n", 'probe output remains unchanged');
    is(read_file("$work/trace"), "uninstall\ninstall\nget_app_container\nspawn\n",
        'installs and runs the replacement');
};

like($runner_source,
    qr/^codesign --force --sign "\$IOS_PROBE_SIGNING_IDENTITY" --entitlements "\$entitlements" "\$bundle_root"$/m,
    'physical-device probes still use the configured signing identity');
like($runner_source, qr/^codesign --verify --deep --strict "\$bundle_root"$/m,
    'physical-device probe signatures are still verified');

done_testing();

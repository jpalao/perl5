#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PERL5_SOURCE_ROOT="${PERL5_SOURCE_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd -P)}"
WORKDIR="${PERL_IOS_WORKDIR:-$(pwd -P)}"
PERL5_REVISION="${PERL5_REVISION:-HEAD}"

if [ -e $HOME/perl5/perlbrew/etc/bashrc ];
    then source $HOME/perl5/perlbrew/etc/bashrc;
    else echo "$HOME/perl5/perlbrew/etc/bashrc not found" && exit 0;
fi

if [ -e "$WORKDIR/setup_test.sh" ];
    then source "$WORKDIR/setup_test.sh";
elif [ -e "$SCRIPT_DIR/setup_test.sh" ];
    then source "$SCRIPT_DIR/setup_test.sh";
fi

if [ -z ${IOS_DEVICE_UUID+x} ];
    then echo "IOS_DEVICE_UUID is unset. Please set it and try again" && exit 0;
    else echo "IOS_DEVICE_UUID is set to '$IOS_DEVICE_UUID'";
fi

if [ -z ${HARNESS_APP_ID+x} ];
    then echo "HARNESS_APP_ID is unset. Please set it and try again" && exit 0;
    else echo "HARNESS_APP_ID is set to '$HARNESS_APP_ID'";
fi

# Tested on macOS Catalina 10.15.7 w/ XCode 12.4
# check README.ios for details

: "${PERL_MAJOR_VERSION:=37}"
: "${PERL_MINOR_VERSION:=2}"

export PERL_VERSION="5.$PERL_MAJOR_VERSION.$PERL_MINOR_VERSION"

: "${PERL_5_BRANCH:=ios_blead_test}"
: "${INSTALL_DIR:=local}"
: "${ARCHS:=arm64}"

: "${CAMELBONES_GIT:=https://github.com/jpalao/camelbones.git}"
: "${CAMELBONES_BRANCH:=original}"
: "${CAMELBONES_PREFIX:=$WORKDIR}"
: "${BUILD_CAMELBONES:=1}"

: "${PERL_IOS_PREFIX:=$WORKDIR}"

: "${HARNESS_TARGET:=iphoneos}"
: "${HARNESS_BUILD_CONFIGURATION:=Debug}"
: "${IOS_TEST_APP:=foundation-runner}"
case "$IOS_TEST_APP" in
    harness)
        : "${HARNESS_SCHEME:=harness}"
        : "${HARNESS_PRODUCT_NAME:=harness}"
        ;;
    foundation-runner|runner)
        : "${HARNESS_SCHEME:=foundation-runner}"
        : "${HARNESS_PRODUCT_NAME:=foundation-runner}"
        ;;
    *)
        echo >&2 "IOS_TEST_APP must be harness, runner, or foundation-runner"
        exit 1
        ;;
esac
# Device transport is the real install/copy/launch mechanism.
# Supported values are devicectl and ios-deploy (ios-deploy is the pipeline default).
: "${DEVICE_TRANSPORT:=ios-deploy}"
: "${AUTO_LAUNCH:=1}"
: "${TEST_LOG_WAIT_TIMEOUT:=120}"

PERL_INSTALL_PREFIX="$WORKDIR/$INSTALL_DIR"
REMOTE_DOCUMENTS_DIR="Documents"
TEST_STATUS_SOURCE=""
TRANSFER_TRANSPORT=""
DEVICECTL_AVAILABLE=0
DEVICECTL_CONNECTED=0
IOS_DEPLOY_AVAILABLE=0
RUN_LOCK_DIR="$WORKDIR/.perl-ios-test.lock"
RUN_LOCK_OWNED=0

# CAMELBONES #
export CAMELBONES_PREFIX="$CAMELBONES_PREFIX"
export CAMELBONES_TARGET=$HARNESS_TARGET
export CAMELBONES_BUILD_CONFIGURATION=$HARNESS_BUILD_CONFIGURATION
export CAMELBONES_CI=1
export CAMELBONES_VERSION='1.3.0'
export CAMELBONES_CPAN_DIR="$WORKDIR/perl-$PERL_VERSION/ext/CamelBones-$CAMELBONES_VERSION"
export CAMELBONES_FRAMEWORK_DIR="$PERL_IOS_PREFIX/camelbones/CamelBones"
export BUILD_CAMELBONES="$BUILD_CAMELBONES"
export INSTALL_CAMELBONES_FRAMEWORK=0
export OVERWRITE_CAMELBONES_FRAMEWORK=0

# IOS #
export PERL_IOS_PREFIX="$PERL_IOS_PREFIX"
export IOS_TARGET=$HARNESS_TARGET
export IOS_BUILD_CONFIGURATION=$HARNESS_BUILD_CONFIGURATION
export IOS_VERSION='0.0.1'
export IOS_FRAMEWORK_DIR="$PERL_IOS_PREFIX/perl-$PERL_VERSION/ios/ios"
export IOS_MODULE_PATH="$PERL_IOS_PREFIX/perl-$PERL_VERSION/ios/ios"
export IOS_CPAN_DIR="$IOS_MODULE_PATH/CPAN"
export IOS_CPAN_EXT_DIR="$PERL_IOS_PREFIX/perl-$PERL_VERSION/ext/ios"
export INSTALL_IOS_FRAMEWORK=0
export OVERWRITE_IOS_FRAMEWORK=0

export ARCHS="$ARCHS"
export PERL_DIST_PATH="$PERL_INSTALL_PREFIX/lib/perl5"
export LIBPERL_PATH="$PERL_IOS_PREFIX/perl-$PERL_VERSION"

use_perlbrew() {
    if ! perlbrew use "perl-$PERL_VERSION"; then
        echo "perlbrew: failed to use perl for macOS, attempting to install"
        build_macos_perl
        perlbrew use "perl-$PERL_VERSION" || check_exit_code $? "perlbrew selection"
    fi
    check_host_perl_version || check_exit_code $? "host Perl selection"
}

check_host_perl_version() {
    if perl -e "exit(\$^V eq v$PERL_VERSION ? 0 : 1)"; then
        echo "perl $PERL_VERSION seems installed at:"
        command -v perl
        return 0
    fi
    echo "Failed to detect perl version $PERL_VERSION"
    return 1
}

devicectl_device_visible() {
    [ "$DEVICECTL_AVAILABLE" -eq 1 ] || return 1
    xcrun devicectl device info details --device "$IOS_DEVICE_UUID" >/dev/null 2>&1
}

ios_deploy_device_visible() {
    [ "$IOS_DEPLOY_AVAILABLE" -eq 1 ] || return 1
    ios-deploy -c -i "$IOS_DEVICE_UUID" >/dev/null 2>&1
}

check_dependencies() {
    local requested_transport="$DEVICE_TRANSPORT"

    deps=( "xcodebuild" "xcrun" "git" "perl" "perlbrew" "rsync" )
    for i in "${deps[@]}"
    do
        command -v $i >/dev/null 2>&1 || {
            echo >&2 "$i is required. Please install it and try again"
            exit 1
        }
    done

    if xcrun devicectl --version >/dev/null 2>&1; then
        DEVICECTL_AVAILABLE=1
    fi
    if command -v ios-deploy >/dev/null 2>&1; then
        IOS_DEPLOY_AVAILABLE=1
    fi
    DEVICECTL_CONNECTED=0
    IOS_DEPLOY_CONNECTED=0

    if [ "$DEVICECTL_AVAILABLE" -eq 1 ]; then
        if devicectl_device_visible; then
            DEVICECTL_CONNECTED=1
            echo "devicectl sees device $IOS_DEVICE_UUID"
        elif [ "$IOS_DEPLOY_AVAILABLE" -eq 1 ] && ios_deploy_device_visible; then
            IOS_DEPLOY_CONNECTED=1
            echo "ios-deploy sees device $IOS_DEVICE_UUID"
        else
            echo "ios-deploy cannot see device $IOS_DEVICE_UUID"
        fi
    elif [ "$IOS_DEPLOY_AVAILABLE" -eq 1 ] && ios_deploy_device_visible; then
        IOS_DEPLOY_CONNECTED=1
        echo "ios-deploy sees device $IOS_DEVICE_UUID"
    else
        echo "ios-deploy cannot see device $IOS_DEVICE_UUID"
    fi

    case "$requested_transport" in
        devicectl)
            if [ "$DEVICECTL_CONNECTED" -eq 1 ]; then
                echo "devicectl can reach device $IOS_DEVICE_UUID; using devicectl"
            elif [ "$IOS_DEPLOY_CONNECTED" -eq 1 ]; then
                echo "falling back to ios-deploy"
                requested_transport="ios-deploy"
            else
                echo >&2 "No available transport: device UUID is not seen with either devicectl or ios-deploy"
                exit 1
            fi
            ;;
        ios-deploy)
            if [ "$IOS_DEPLOY_CONNECTED" -ne 1 ]; then
                echo >&2 "No available transport: device UUID is not seen with either devicectl or ios-deploy"
                exit 1
            fi
            echo "ios-deploy can reach device $IOS_DEVICE_UUID; using ios-deploy"
            ;;
        auto)
            if [ "$DEVICECTL_CONNECTED" -eq 1 ]; then
                requested_transport="devicectl"
                echo "auto-selected transport: devicectl for device $IOS_DEVICE_UUID"
            elif [ "$IOS_DEPLOY_CONNECTED" -eq 1 ]; then
                requested_transport="ios-deploy"
                echo "auto-selected transport: ios-deploy for device $IOS_DEVICE_UUID"
            else
                echo >&2 "No available transport: device UUID is not seen with either devicectl or ios-deploy"
                exit 1
            fi
            ;;
        *)
            echo >&2 "DEVICE_TRANSPORT must be devicectl, ios-deploy, or auto"
            exit 1
            ;;
    esac

    TRANSFER_TRANSPORT="$requested_transport"

    case "$AUTO_LAUNCH" in
        0|1)
            ;;
        *)
            echo >&2 "AUTO_LAUNCH must be 0 or 1"
            exit 1
            ;;
    esac

    echo "Device file transport: $TRANSFER_TRANSPORT"
}

check_exit_code() {
    local status=${1:-$?}
    local stage_name=${2:-"build step"}
    if [ "$status" -ne 0 ]; then
        echo "Failed during $stage_name for $HARNESS_TARGET" >&2
        exit "$status"
    fi
}

prepare_camelbones() {
    rm -Rf "$WORKDIR/camelbones"
    git clone --single-branch --branch "$CAMELBONES_BRANCH" "$CAMELBONES_GIT" "$WORKDIR/camelbones"
}

prepare_perl() {
    local perl_build_dir
    local perl_revision

    perl_build_dir="$WORKDIR/perl-$PERL_VERSION"
    rm -Rf "$perl_build_dir"
    git clone --no-checkout "$PERL5_SOURCE_ROOT" "$perl_build_dir"
    git -C "$perl_build_dir" checkout --detach "$PERL5_REVISION"
    perl_revision=$(git -C "$perl_build_dir" rev-parse HEAD)
    echo "Building perl5 revision $perl_revision"
}

acquire_run_lock() {
    local existing_pid=""

    if ! mkdir "$RUN_LOCK_DIR" 2>/dev/null; then
        if [ -f "$RUN_LOCK_DIR/pid" ]; then
            read -r existing_pid < "$RUN_LOCK_DIR/pid" || true
        fi
        if [ -n "$existing_pid" ] && kill -0 "$existing_pid" >/dev/null 2>&1; then
            echo >&2 "Another iOS test run is already using $WORKDIR (PID $existing_pid)"
            exit 1
        fi
        rm -Rf "$RUN_LOCK_DIR"
        mkdir "$RUN_LOCK_DIR" || exit 1
    fi
    printf '%s\n' "$$" > "$RUN_LOCK_DIR/pid"
    RUN_LOCK_OWNED=1
}

cleanup() {
    rm -Rf "$WORKDIR/.device-transfer-download" "$WORKDIR/.device-transfer-upload"
    if [ "$RUN_LOCK_OWNED" -eq 1 ]; then
        rm -Rf "$RUN_LOCK_DIR"
        RUN_LOCK_OWNED=0
    fi
}

refresh_generated_config_timestamps() {
    local tree="$1"
    local config_sh="$tree/config.sh"
    local config_pm="$tree/lib/Config.pm"
    local config_h="$tree/config.h"

    [ -f "$config_sh" ] && [ -f "$config_pm" ] && [ -f "$config_h" ] || return 0
    perl -e '
        my $mtime = (stat $ARGV[0])[9] + 1;
        utime $mtime, $mtime, @ARGV[1, 2] or die "utime: $!\n";
    ' "$config_sh" "$config_pm" "$config_h"
}

stage_tree_for_upload() {
    local source_dir="$1"
    local upload_dir="$2"

    echo "Staging Perl tree for devicectl upload ..."
    rm -Rf "$upload_dir"
    mkdir -p "$upload_dir"
    if ! capture_command_output rsync -aL \
        --exclude '.git/' \
        --exclude 'Build/' \
        --exclude 'build/' \
        --exclude '/ios/test/Build/' \
        --exclude '*.bundle' \
        --exclude '*.sh' \
        --exclude '*.SH' \
        --exclude 'Configure' \
        --exclude 'plan9/' \
        --exclude 'win32/' \
        --exclude 'Win32/' \
        --exclude 'vms/' \
        --exclude 'VMS/' \
        --exclude 'os2/' \
        --exclude 'cygwin/' \
        --exclude 'amigaos4/' \
        "$source_dir/" "$upload_dir/"; then
        echo >&2 "rsync staging failed for $source_dir"
        return 1
    fi
    refresh_generated_config_timestamps "$upload_dir" || return 1
    echo "Perl tree staging complete."
    return 0
}

capture_command_output() {
    local output_file="$WORKDIR/.device-command-output.log"
    local status

    rm -f "$output_file"
    "$@" >"$output_file" 2>&1
    status=$?
    if [ "$status" -ne 0 ]; then
        echo "Command failed: $*" >&2
        cat "$output_file" >&2
    fi
    return "$status"
}

upload_tree_with_devicectl() {
    local source_dir="$1"
    local upload_dir="$WORKDIR/.device-transfer-upload"
    local status

    stage_tree_for_upload "$source_dir" "$upload_dir"
    status=$?
    if [ "$status" -ne 0 ]; then
        rm -Rf "$upload_dir"
        return "$status"
    fi
    echo "Uploading staged Perl tree to $HARNESS_APP_ID/$REMOTE_DOCUMENTS_DIR with devicectl..."
    capture_command_output xcrun devicectl device copy to \
        --device "$IOS_DEVICE_UUID" \
        --user mobile \
        --domain-type appDataContainer \
        --domain-identifier "$HARNESS_APP_ID" \
        --source "$upload_dir" \
        --destination "$REMOTE_DOCUMENTS_DIR"
    status=$?
    if [ "$status" -ne 0 ]; then
        rm -Rf "$upload_dir"
        return "$status"
    fi
    echo "devicectl Perl tree upload complete."
    rm -Rf "$upload_dir"
    return 0
}

download_test_status() {
    [ -f "$TEST_STATUS_SOURCE" ]
}

launch_harness_with_idevicedebug() {
    local status

    # ios-deploy --noinstall always starts debugserver, even without --debug,
    # and therefore requires DeviceSupport Symbols that Xcode lacks for iOS 12.
    command -v idevicedebug >/dev/null 2>&1 || {
        echo >&2 "idevicedebug is required to launch the harness on this device"
        return 1
    }
    echo "Launching $HARNESS_APP_ID with idevicedebug on $IOS_DEVICE_UUID"
    idevicedebug -u "$IOS_DEVICE_UUID" run "$HARNESS_APP_ID"
    status=$?
    if [ "$status" -eq 0 ]; then
        echo "idevicedebug session exited successfully"
    else
        echo >&2 "idevicedebug exited unsuccessfully for $HARNESS_APP_ID (status $status)"
    fi
    return "$status"
}

try_launch_harness() {
    local status

    case "$TRANSFER_TRANSPORT" in
        devicectl)
            if [ "$DEVICECTL_AVAILABLE" -eq 1 ]; then
                if capture_command_output xcrun devicectl device process launch \
                        --device "$IOS_DEVICE_UUID" \
                        --terminate-existing \
                        "$HARNESS_APP_ID"; then
                    return 0
                fi
            fi
            if command -v idevicedebug >/dev/null 2>&1; then
                echo "devicectl launch failed; retrying with idevicedebug"
                if launch_harness_with_idevicedebug; then
                    return 0
                else
                    status=$?
                    return "$status"
                fi
            fi
            ;;
        ios-deploy)
            if launch_harness_with_idevicedebug; then
                return 0
            else
                status=$?
                return "$status"
            fi
            ;;
    esac
    return 1
}

launch_harness() {
    local status

    if [ "$AUTO_LAUNCH" = "1" ]; then
        if try_launch_harness; then
            return 0
        else
            status=$?
            echo >&2 "Automatic launch failed; not retrying (status $status)"
            return "$status"
        fi
    fi

    if [ -t 0 ]; then
        read -r -p "Launch the harness manually, then press Return to continue: "
        return 0
    fi

    echo >&2 "Launch the harness manually and rerun in an interactive terminal"
    return 1
}

copy_tree_to_device() {
    local source_dir="$1"
    local upload_dir="$WORKDIR/.device-transfer-upload"
    local status

    if [ "$TRANSFER_TRANSPORT" = "ios-deploy" ]; then
        stage_tree_for_upload "$source_dir" "$upload_dir"
        status=$?
        if [ "$status" -ne 0 ]; then
            rm -Rf "$upload_dir"
            return "$status"
        fi
        echo "Uploading staged Perl tree to $HARNESS_APP_ID/$REMOTE_DOCUMENTS_DIR with ios-deploy..."
        capture_command_output ios-deploy \
            -i "$IOS_DEVICE_UUID" \
            --bundle_id "$HARNESS_APP_ID" \
            --upload "$upload_dir" \
            --to "/$REMOTE_DOCUMENTS_DIR"
        status=$?
        rm -Rf "$upload_dir"
        [ "$status" -eq 0 ] || return "$status"
        build_destination_dir="$HARNESS_APP_ID/$REMOTE_DOCUMENTS_DIR (ios-deploy)"
        return 0
    fi

    if [ "$TRANSFER_TRANSPORT" = "devicectl" ]; then
        build_destination_dir="$HARNESS_APP_ID/$REMOTE_DOCUMENTS_DIR (devicectl)"
        upload_tree_with_devicectl "$source_dir"
        return $?
    fi

    build_destination_dir="$HARNESS_APP_ID/$REMOTE_DOCUMENTS_DIR (devicectl)"
    upload_tree_with_devicectl "$source_dir"
}

install_harness() {
    local app_path="$1"
    local status

    case "$TRANSFER_TRANSPORT" in
        ios-deploy)
            capture_command_output ios-deploy -i "$IOS_DEVICE_UUID" --uninstall --bundle "$app_path"
            return $?
            ;;
        *)
            xcrun devicectl device uninstall app \
                --device "$IOS_DEVICE_UUID" "$HARNESS_APP_ID" >/dev/null 2>&1 || true
            capture_command_output xcrun devicectl device install app \
                --device "$IOS_DEVICE_UUID" "$app_path"
            status=$?
            if [ "$status" -eq 0 ]; then
                return 0
            fi
            if [ "$IOS_DEPLOY_AVAILABLE" -eq 1 ]; then
                echo "devicectl install failed; retrying with ios-deploy" >&2
                capture_command_output ios-deploy -i "$IOS_DEVICE_UUID" --bundle "$app_path"
                return $?
            fi
            return "$status"
            ;;
    esac
}

test_perl_device() {
    pushd "perl-$PERL_VERSION/ios/test"
    check_exit_code

    local install_root="$PWD/Build/Install"

    BUILD_CAMELBONES_BOOLEAN="NO"
    if [ $BUILD_CAMELBONES -eq 1 ]; then
        BUILD_CAMELBONES_BOOLEAN="YES"
    fi

    xcodebuild ARCHS="$ARCHS" \
        EMBED_CAMELBONES_FRAMEWORK="$BUILD_CAMELBONES_BOOLEAN" \
        CAMELBONES_FRAMEWORK_PATH="$CAMELBONES_PREFIX/camelbones/CamelBones/build/Products/$CAMELBONES_BUILD_CONFIGURATION-$CAMELBONES_TARGET" \
        IOS_FRAMEWORK_PATH="$PERL_IOS_PREFIX/perl-$PERL_VERSION/ios/ios/build/Products/$IOS_BUILD_CONFIGURATION-$IOS_TARGET" \
        PERL_DIST_PATH="$PERL_INSTALL_PREFIX/lib/perl5" \
        LIBPERL_PATH="$PERL_INSTALL_PREFIX/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/CORE" \
        PERL_VERSION="$PERL_VERSION" ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO \
        DSTROOT="$install_root" -configuration "$HARNESS_BUILD_CONFIGURATION" \
        -allowProvisioningUpdates -scheme "$HARNESS_SCHEME" clean install
    check_exit_code

    # install the app so it can receive files in Documents
    simulator_build=`echo "$ARCHS" | grep -c "x86_64"` # x86_64 simulator
    test_app="$install_root/Applications/$HARNESS_PRODUCT_NAME.app"
    if [ "$simulator_build" -eq "0" ]; then
        install_harness "$test_app"
        check_exit_code
    else
        xcrun simctl uninstall "$IOS_DEVICE_UUID" "$HARNESS_APP_ID"
        xcrun simctl install "$IOS_DEVICE_UUID" "$test_app"
        check_exit_code
    fi

    echo "Copy perl build directory to iOS device..."

    if [ "$simulator_build" -eq "0" ]; then
        copy_tree_to_device "$WORKDIR/perl-$PERL_VERSION"
        check_exit_code
    else
        build_destination_dir=`xcrun simctl get_app_container "$IOS_DEVICE_UUID" "$HARNESS_APP_ID" data`
        build_destination_dir="$build_destination_dir/Documents/"
        simulator_stage_dir="$WORKDIR/.ios-test-stage"
        stage_tree_for_upload "$WORKDIR/perl-$PERL_VERSION" "$simulator_stage_dir"
        check_exit_code $? "simulator tree staging"
        cp -RL "$simulator_stage_dir/." "$build_destination_dir"
        rm -Rf "$simulator_stage_dir"
        check_exit_code
    fi

    echo "App Documents dir is '$build_destination_dir'"

    if [ "$simulator_build" -eq "0" ]; then
        echo "Starting device harness launch"
        launch_harness
        check_exit_code $? "device harness launch"
    else
        TRANSFER_TRANSPORT="simulator"
        TEST_STATUS_SOURCE="$build_destination_dir/perl-tests.status"
        xcrun simctl launch --console "$IOS_DEVICE_UUID" "$HARNESS_APP_ID"
        check_exit_code
    fi

    popd

    if [ "$simulator_build" -eq "0" ]; then
        return 0
    fi

    test_status_waited=0
    while ! download_test_status || ! grep -Eq '^-?[0-9]+$' "$TEST_STATUS_SOURCE"; do
        if [ "$test_status_waited" -ge "$TEST_LOG_WAIT_TIMEOUT" ]; then
            echo >&2 "Timed out waiting for the simulator test status after ${TEST_LOG_WAIT_TIMEOUT}s"
            check_exit_code 1 "simulator test status"
        fi
        sleep 2
        test_status_waited=$((test_status_waited + 2))
    done
    test_status=$(cat "$TEST_STATUS_SOURCE")
    check_exit_code "$test_status" "simulator harness test"
}

build_macos_perl() {
    # uninstall perl-blead
    echo "Uninstalling perl-blead"
    perlbrew uninstall -q perl-blead

    echo "Installing perl-blead"
    # macOS generate_uudmap and miniperl are used in cross builds
    # -DPERL_USE_SAFE_PUTENV warns redefined, 5.37.1, maybe before
    MACOSX_DEPLOYMENT_TARGET=10.5 perlbrew install -Dusedevel -Duselargefiles \
        -Dcccdlflags='-fPIC -DPERL_USE_SAFE_PUTENV' -Doptimize=-O3 -Duseshrplib \
        -Duse64bitall --thread --multi --64int --clan blead
    perlbrew alias create perl-blead "perl-$PERL_VERSION"

    pushd ~/perl5/perlbrew/build
    ln -s blead/perl5-blead "perl-$PERL_VERSION"
    popd

    perlbrew use "perl-$PERL_VERSION"

    # for test app build to re-link and sign binaries, see fix_ios_dylibs.sh
    cpanm File::Copy::Recursive
    cpanm File::Find::Rule
}

####################################################################

cd "$WORKDIR" || exit 1

echo "Build started: $(date)"

trap cleanup EXIT
trap 'exit 130' SIGINT SIGTERM SIGHUP

acquire_run_lock

check_dependencies

use_perlbrew

mkdir -p ext
rm -f "ext/CamelBones-$CAMELBONES_VERSION".tar.gz

prepare_perl
check_exit_code

prepare_camelbones
check_exit_code

rm -Rf "$INSTALL_DIR"

PERL_ARCH="$ARCHS" DEBUG=1 sh -x "perl-$PERL_VERSION/ios/build.sh"
check_exit_code

# enable APItest.bundle and Typemap.bundle loading
mkdir -p "$INSTALL_DIR/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/auto/XS/APItest"
mkdir -p "$INSTALL_DIR/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/auto/XS/Typemap"
cp "perl-$PERL_VERSION/lib/auto/XS/APItest/APItest.bs" "$INSTALL_DIR/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/auto/XS/APItest"
cp "perl-$PERL_VERSION/lib/auto/XS/APItest/APItest.bundle" "$INSTALL_DIR/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/auto/XS/APItest"
cp "perl-$PERL_VERSION/lib/auto/XS/Typemap/Typemap.bundle" "$INSTALL_DIR/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/auto/XS/Typemap"

mkdir -p "$INSTALL_DIR/lib/perl5/$PERL_VERSION/XS/"
chmod u+w "$INSTALL_DIR/lib/perl5/$PERL_VERSION/XS/APItest.pm" 2>/dev/null || true
cp "perl-$PERL_VERSION/lib/XS/APItest.pm" "$INSTALL_DIR/lib/perl5/$PERL_VERSION/XS/"
check_exit_code $? "APItest.pm installation"

test_perl_device

echo "Build finished: $(date)"

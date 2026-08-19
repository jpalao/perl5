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

: "${PERL5_GIT:=https://github.com/jpalao/perl5.git}"
: "${PERL_5_BRANCH:=ios_blead_test}"
: "${INSTALL_DIR:=local}"
: "${ARCHS:=arm64}"

: "${CAMELBONES_GIT:=https://github.com/jpalao/camelbones.git}"
: "${CAMELBONES_BRANCH:=original}"
: "${CAMELBONES_PREFIX:=$WORKDIR}"
: "${BUILD_CAMELBONES:=1}"

: "${IOS_GIT:=https://github.com/jpalao/ios.git}"
: "${IOS_BRANCH:=master}"
: "${PERL_IOS_PREFIX:=$WORKDIR}"
: "${IOS_MOUNTPOINT:=$WORKDIR/_ios_mount}"

: "${HARNESS_TARGET:=iphoneos}"
: "${HARNESS_BUILD_CONFIGURATION:=Debug}"
# Device transport is the real install/copy/launch mechanism.
# Supported values are devicectl (default) and ios-deploy.
: "${DEVICE_TRANSPORT:=devicectl}"
# USE_IFUSE is a separate developer convenience for mounted Documents access.
# It is optional and not assumed to be present in the general open-source user environment.
: "${USE_IFUSE:=auto}"
: "${AUTO_LAUNCH:=1}"
: "${TEST_LOG_PREFIX:=perl-tests}"
: "${IFUSE_MOUNT_TIMEOUT:=30}"
: "${TEST_LOG_WAIT_TIMEOUT:=120}"

PERL_INSTALL_PREFIX="$WORKDIR/$INSTALL_DIR"
REMOTE_DOCUMENTS_DIR="Documents"
REMOTE_TEST_LOG="$REMOTE_DOCUMENTS_DIR/perl-tests.txt"
PERL_TEST_LOG=""
TEST_LOG_SOURCE=""
TRANSFER_TRANSPORT=""
DEVICECTL_AVAILABLE=0
DEVICECTL_CONNECTED=0
IOS_DEPLOY_AVAILABLE=0
IFUSE_AVAILABLE=0
IFUSE_IN_USE=0
HARNESS_APP_PATH=""
REFRESH_PID=""
MOUNT_REFRESH_PID=""

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
    perlbrew use "perl-$PERL_VERSION"
    if [ $? -ne 0 ]; then
        echo "perlbrew: failed to use perl for macOS, attempting to install"
        build_macos_perl
        perlbrew use "perl-$PERL_VERSION"
        check_exit_code
    fi
    check_host_perl_version
}

check_host_perl_version () {
    macos_perl_version=`perl -v`
    macos_perl_version_grep=`echo "$macos_perl_version" | grep -o "$PERL_VERSION"`
    if [ "$macos_perl_version_grep" = "$PERL_VERSION" ]; then
        echo "perl $PERL_VERSION seems installed at:"
        echo `which perl`
        return 1
    else
        echo "Failed to detect perl version $PERL_VERSION"
        return 0
    fi
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
    if command -v ifuse >/dev/null 2>&1; then
        IFUSE_AVAILABLE=1
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
    if [ "$USE_IFUSE" = "1" ] || [ "$USE_IFUSE" = "auto" ] && [ "$IFUSE_AVAILABLE" -eq 1 ]; then
        echo "ifuse facility enabled"
    fi
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

prepare_ios() {
    rm -Rf "$WORKDIR/$1"
    git clone --single-branch --branch "$IOS_BRANCH" "$IOS_GIT" "$WORKDIR/$1"
}

prepare_perl() {
    local perl_revision
    local test_timestamp

    perl_build_dir="$WORKDIR/perl-$PERL_VERSION"
    rm -Rf "$perl_build_dir"
    git clone --no-checkout "$PERL5_SOURCE_ROOT" "$perl_build_dir"
    git -C "$perl_build_dir" checkout --detach "$PERL5_REVISION"
    perl_revision=$(git -C "$perl_build_dir" rev-parse HEAD)
    test_timestamp=$(date -u "+%Y%m%dT%H%M%SZ")
    PERL_TEST_LOG="$WORKDIR/$TEST_LOG_PREFIX-$test_timestamp-$perl_revision.txt"
    echo "Building perl5 revision $perl_revision"
    echo "Test log: $PERL_TEST_LOG"
}

_term() {
    if [ -n "$REFRESH_PID" ]; then
        echo "Killing refresh process..."
        kill -TERM "$REFRESH_PID" >/dev/null 2>&1 || true
    fi
    if [ -n "$MOUNT_REFRESH_PID" ]; then
        kill -TERM "$MOUNT_REFRESH_PID" >/dev/null 2>&1 || true
    fi
    if [ "$IFUSE_IN_USE" -eq 1 ]; then
        umount -f "$IOS_MOUNTPOINT" >/dev/null 2>&1 || true
    fi
    rm -Rf "$WORKDIR/.device-transfer-download" "$WORKDIR/.device-transfer-upload"
    exit 0
}

mount_harness_documents() {
    umount -f "$IOS_MOUNTPOINT" >/dev/null 2>&1 || true
    mkdir -p "$IOS_MOUNTPOINT"
    ifuse "$IOS_MOUNTPOINT" -u "$IOS_DEVICE_UUID" -o volname=harness --documents "$HARNESS_APP_ID"
}

run_with_timeout() {
    local timeout_seconds="$1"
    local command_pid
    local elapsed=0
    shift

    "$@" &
    command_pid=$!
    while kill -0 "$command_pid" >/dev/null 2>&1; do
        if [ "$elapsed" -ge "$timeout_seconds" ]; then
            kill "$command_pid" >/dev/null 2>&1 || true
            wait "$command_pid" >/dev/null 2>&1 || true
            return 124
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    wait "$command_pid"
}

transfer_fallback_allowed() {
    [ "$DEVICE_TRANSPORT" = "auto" ]
}

ifuse_requested() {
    if [ "$USE_IFUSE" = "1" ]; then
        return 0
    fi
    if [ "$USE_IFUSE" = "auto" ] && [ "$IFUSE_AVAILABLE" -eq 1 ]; then
        return 0
    fi
    return 1
}

stage_tree_for_upload() {
    local source_dir="$1"
    local upload_dir="$2"

    rm -Rf "$upload_dir"
    mkdir -p "$upload_dir"
    if ! capture_command_output rsync -aL \
        --exclude '/ios/test/Build/' \
        --exclude '*.bundle' \
        "$source_dir/" "$upload_dir/"; then
        echo >&2 "rsync staging failed for $source_dir"
        return 1
    fi
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

    stage_tree_for_upload "$source_dir" "$upload_dir"
    if ! capture_command_output xcrun devicectl device copy to \
        --device "$IOS_DEVICE_UUID" \
        --user mobile \
        --domain-type appDataContainer \
        --domain-identifier "$HARNESS_APP_ID" \
        --source "$upload_dir" \
        --destination "$REMOTE_DOCUMENTS_DIR"; then
        rm -Rf "$upload_dir"
        return 1
    fi
    rm -Rf "$upload_dir"
    return 0
}

update_local_test_log() {
    local downloaded_log="$1"
    local local_size=0
    local remote_size

    [ -f "$downloaded_log" ] || return 1

    if [ -f "$PERL_TEST_LOG" ]; then
        local_size=$(wc -c < "$PERL_TEST_LOG" | tr -d ' ')
    fi
    remote_size=$(wc -c < "$downloaded_log" | tr -d ' ')

    if [ "$remote_size" -lt "$local_size" ]; then
        cat "$downloaded_log" > "$PERL_TEST_LOG"
    elif [ "$remote_size" -gt "$local_size" ]; then
        tail -c "+$((local_size + 1))" "$downloaded_log" >> "$PERL_TEST_LOG"
    fi
}

download_test_log_with_devicectl() {
    local download_dir="$WORKDIR/.device-transfer-download"
    local downloaded_log="$download_dir/perl-tests.txt"

    rm -Rf "$download_dir"
    mkdir -p "$download_dir"
    xcrun devicectl device copy from \
        --device "$IOS_DEVICE_UUID" \
        --user mobile \
        --domain-type appDataContainer \
        --domain-identifier "$HARNESS_APP_ID" \
        --source "$REMOTE_TEST_LOG" \
        --destination "$downloaded_log" >/dev/null 2>&1 || return 1
    update_local_test_log "$downloaded_log"
}

download_test_log() {
    if [ "$IFUSE_IN_USE" -eq 1 ]; then
        update_local_test_log "$TEST_LOG_SOURCE"
        return $?
    fi

    case "$TRANSFER_TRANSPORT" in
        devicectl)
            download_test_log_with_devicectl
            ;;
        simulator)
            update_local_test_log "$TEST_LOG_SOURCE"
            ;;
        *)
            return 1
            ;;
    esac
}

refresh_test_log() {
    while true; do
        download_test_log || true
        sleep 2
    done
}

launch_harness_with_idevicedebug() {
    # ios-deploy --noinstall always starts debugserver, even without --debug,
    # and therefore requires DeviceSupport Symbols that Xcode lacks for iOS 12.
    command -v idevicedebug >/dev/null 2>&1 || {
        echo >&2 "idevicedebug is required to launch the harness on this device"
        return 1
    }
    idevicedebug -u "$IOS_DEVICE_UUID" --detach run "$HARNESS_APP_ID"
}

try_launch_harness() {
    case "$TRANSFER_TRANSPORT" in
        devicectl)
            if [ "$DEVICECTL_AVAILABLE" -eq 1 ]; then
                if capture_command_output xcrun devicectl device process launch \
                        --device "$IOS_DEVICE_UUID" \
                        --terminate-existing \
                        "$HARNESS_APP_ID"; then
                    return 0
                fi
                if grep -qi "locked" "$WORKDIR/.device-command-output.log"; then
                    echo >&2 "The device is locked; unlock it before retrying launch."
                fi
            fi
            if command -v idevicedebug >/dev/null 2>&1; then
                echo "devicectl launch failed; retrying with idevicedebug"
                if launch_harness_with_idevicedebug; then
                    return 0
                fi
            fi
            ;;
        ios-deploy)
            if launch_harness_with_idevicedebug; then
                return 0
            fi
            ;;
    esac
    return 1
}

launch_harness() {
    if [ "$AUTO_LAUNCH" = "1" ]; then
        if try_launch_harness; then
            return 0
        fi
        if [ -t 0 ]; then
            read -r -p "Automatic launch failed. Unlock the device, then press Return to retry: "
            if try_launch_harness; then
                return 0
            fi
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
    local copy_errors="$WORKDIR/.device-copy-errors.log"

    if ifuse_requested && mount_harness_documents; then
        IFUSE_IN_USE=1
        build_destination_dir="$IOS_MOUNTPOINT"
        echo "Copying $source_dir to mounted Documents at $build_destination_dir (verbose)"
        rm -f "$copy_errors"
        # ifuse/macFUSE does not implement every chmod or extended-attribute
        # operation used by cp. The file data is copied, but cp returns nonzero.
        cp -RvL "$source_dir/." "$build_destination_dir" 2>"$copy_errors"
        if [ $? -ne 0 ]; then
            echo >&2 "ifuse copy completed with filesystem warnings; continuing"
            echo >&2 "Copy diagnostics: $copy_errors"
        else
            rm -f "$copy_errors"
        fi
        rm -Rf "$build_destination_dir/ios/test/Build"
        echo "Cleaning bundle artifacts under $build_destination_dir"
        if ! capture_command_output find "$build_destination_dir" -name "*.bundle" -type f -delete; then
            echo >&2 "bundle cleanup failed in $build_destination_dir"
            return 1
        fi
        return 0
    fi

    if [ "$TRANSFER_TRANSPORT" = "devicectl" ]; then
        build_destination_dir="$HARNESS_APP_ID/$REMOTE_DOCUMENTS_DIR (devicectl)"
        upload_tree_with_devicectl "$source_dir"
        return $?
    fi

    if [ "$TRANSFER_TRANSPORT" = "ios-deploy" ]; then
        echo >&2 "ios-deploy is the active transport, but bulk tree copy is not available without the ifuse mount. Enable USE_IFUSE=1 or switch to devicectl for a visible device."
        return 1
    fi

    build_destination_dir="$HARNESS_APP_ID/$REMOTE_DOCUMENTS_DIR (devicectl)"
    upload_tree_with_devicectl "$source_dir"
}

install_harness() {
    local app_path="$1"
    local status

    case "$TRANSFER_TRANSPORT" in
        ios-deploy)
            capture_command_output ios-deploy -r -i "$IOS_DEVICE_UUID" --bundle "$app_path"
            return $?
            ;;
        *)
            xcrun devicectl device uninstall app \
                --device "$IOS_DEVICE_UUID" "$HARNESS_APP_ID" >/dev/null 2>&1 || true
            if ! capture_command_output xcrun devicectl device install app \
                --device "$IOS_DEVICE_UUID" "$app_path"; then
                status=$?
                if [ "$status" -ne 0 ] && [ "$IOS_DEPLOY_AVAILABLE" -eq 1 ]; then
                    echo "devicectl install failed; retrying with ios-deploy" >&2
                    capture_command_output ios-deploy -r -i "$IOS_DEVICE_UUID" --bundle "$app_path"
                    return $?
                fi
                return "$status"
            fi
            return 0
            ;;
    esac
}

test_perl_device() {
    pushd "perl-$PERL_VERSION/ios/test"
    check_exit_code

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
        PERL_VERSION="$PERL_VERSION" ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO -allowProvisioningUpdates -scheme harness
    check_exit_code

    # install the app so it can receive files in Documents
    simulator_build=`echo "$ARCHS" | grep -c "x86_64"` # x86_64 simulator
    test_app="Build/Products/$HARNESS_BUILD_CONFIGURATION-$HARNESS_TARGET/harness.app"
    HARNESS_APP_PATH="$test_app"

    if [ "$simulator_build" -eq "0" ]; then
        install_harness "$test_app"
        check_exit_code
    else
        xcrun simctl uninstall "$IOS_DEVICE_UUID" "$HARNESS_APP_ID"
        xcrun simctl install "$IOS_DEVICE_UUID" "$test_app"
        check_exit_code
    fi

    pushd "$WORKDIR/perl-$PERL_VERSION/"

    echo 'substitute @INC = (...) with use lib (...). Patching files...'

    perl -0777 -p -i -e 's/(\@INC\s*=\s*)((?:(?!.*map.*)))/use lib \2/g' TestInit.pm

    find . -name "*.t" -o -name "TEST" -o -name "harness" -type f | \
        xargs grep -EL 'local\s*@INC\s*=' | \
        xargs grep -EL '\\@INC\s*=' | \
        xargs grep -El '^\s*[^#]*\s*\s*@INC\s*=' | \
        xargs perl -0777 -p -i -e 's|(\s*(?:(?!#))\s*)(?:(?!local))\s*\@INC\s*=(?:(?!>))\s*(?!.*if.*)|\1use lib |g'

    find . -type f | grep -E "\.(pl|pm|t)$" | \
        xargs grep -EL 'local\s*@INC\s*=' | \
        xargs grep -EL '\\@INC\s*=' | \
        xargs grep -El "^\s*[^#]*\s*@INC\s*=.*if.*" | \
        xargs perl -0777 -p -i -e \
        's|(\s*(?:(?!#))\s*)(?:(?!local)\s*)\@INC\s*=(?:(?!>))\s*(.*)\s*if\s*([^;]*);|${1}if (${3}) { use lib ${2} }|g'

    # exceptions
    git checkout ext/File-Find/t/find.t
    git checkout ext/File-Find/t/taint.t
    git checkout t/op/inccode-tie.t

    echo 'Patched files:'
    git --no-pager diff --name-only

    popd

    echo "Copy perl build directory to iOS device..."

    if [ "$simulator_build" -eq "0" ]; then
        copy_tree_to_device "$WORKDIR/perl-$PERL_VERSION"
        check_exit_code
    else # ARM device
        build_destination_dir=`xcrun simctl get_app_container "$IOS_DEVICE_UUID" "$HARNESS_APP_ID" data`
        build_destination_dir="$build_destination_dir/Documents/"
        cp -RL "$WORKDIR/perl-$PERL_VERSION/." "$build_destination_dir"
        rm -Rf "$build_destination_dir/ios/test/Build"
        find "$build_destination_dir" -name "*.bundle" -type f -delete
        check_exit_code
    fi

    echo "App Documents dir is '$build_destination_dir'"

    if [ "$simulator_build" -eq "0" ]; then
        if [ "$IFUSE_IN_USE" -eq 1 ]; then
            umount -f "$IOS_MOUNTPOINT"
        fi
        launch_harness
        check_exit_code
    else
        xcrun simctl launch "$IOS_DEVICE_UUID" "$HARNESS_APP_ID"
        check_exit_code
        TRANSFER_TRANSPORT="simulator"
        TEST_LOG_SOURCE="$build_destination_dir/perl-tests.txt"
    fi

    popd

    if [ "$simulator_build" -eq "0" ]; then
        if [ "$IFUSE_IN_USE" -eq 1 ]; then
            echo "Remounting harness Documents to follow the test log"
            if ! run_with_timeout "$IFUSE_MOUNT_TIMEOUT" mount_harness_documents; then
                echo >&2 "ifuse remount failed or timed out after ${IFUSE_MOUNT_TIMEOUT}s while preparing the test log"
                check_exit_code 1
            fi
            TEST_LOG_SOURCE="$IOS_MOUNTPOINT/perl-tests.txt"
            sleep 2
            # needed for scrolling to keep in sync w/ device's ifuse fs
            perl -e "while (1) {sleep 1; system qw (ls $IOS_MOUNTPOINT);} " > /dev/null 2>&1 &
            MOUNT_REFRESH_PID=$!
        fi
    fi

    rm -f "$PERL_TEST_LOG"
    echo "Waiting up to ${TEST_LOG_WAIT_TIMEOUT}s for device test log: $REMOTE_TEST_LOG"
    test_log_waited=0
    while ! download_test_log; do
        if [ "$test_log_waited" -ge "$TEST_LOG_WAIT_TIMEOUT" ]; then
            echo >&2 "Timed out waiting for the device test log after ${TEST_LOG_WAIT_TIMEOUT}s"
            echo >&2 "Expected source: ${TEST_LOG_SOURCE:-$REMOTE_TEST_LOG}"
            check_exit_code 1 "test log discovery"
        fi
        sleep 2
        test_log_waited=$((test_log_waited + 2))
        if [ $((test_log_waited % 10)) -eq 0 ]; then
            echo "Still waiting for the device test log (${test_log_waited}s elapsed)"
        fi
    done
    echo "Device test log found; streaming output"
    refresh_test_log &
    REFRESH_PID=$!

    sleep 3

    tail -n 3000 -f "$PERL_TEST_LOG"

    if [ -n "$REFRESH_PID" ]; then
        echo "kill $REFRESH_PID"
        kill "$REFRESH_PID" >/dev/null 2>&1 || true
        REFRESH_PID=""
    fi
    if [ -n "$MOUNT_REFRESH_PID" ]; then
        kill "$MOUNT_REFRESH_PID" >/dev/null 2>&1 || true
        MOUNT_REFRESH_PID=""
    fi
    if [ "$simulator_build" -eq "0" ]; then
        if [ "$IFUSE_IN_USE" -eq 1 ]; then
            umount -f "$IOS_MOUNTPOINT"
            check_exit_code
        fi
    fi
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

build_artifacts() {
  if [ $SIMULATOR_BUILD -ne 0 ]; then
    PLATFORM_TAG="$PLATFORM_TAG-simul"
  fi
  cd "$WORKDIR"
  TIMESTAMP=$(date "+%Y%m%d-%H%M%S")
  export COPY_EXTENDED_ATTRIBUTES_DISABLE=true
  export COPYFILE_DISABLE=true
  tar -c --exclude='._*' --exclude='.DS_Store' --exclude='*.bak' --exclude='*~' -vjf "perl-$PERL_VERSION-$PLATFORM_TAG-$PERL_ARCH-$TIMESTAMP.share.tar.bz2" "./$INSTALL_DIR/share"
  tar -c --exclude='._*' --exclude='.DS_Store' --exclude='*.bak' --exclude='*~' -vjf "perl-$PERL_VERSION-$PLATFORM_TAG-$PERL_ARCH-$TIMESTAMP.bin.tar.bz2" "./$INSTALL_DIR/bin"
  tar -c --exclude='._*' --exclude='.DS_Store' --exclude='*.bak' --exclude='*~' -vjf "perl-$PERL_VERSION-$PLATFORM_TAG-$PERL_ARCH-$TIMESTAMP.lib.tar.bz2" "./$INSTALL_DIR/lib/perl5"
  tar -c --exclude='._*' --exclude='.DS_Store' --exclude='*.bak' --exclude='*~' -vjf "perl-$PERL_VERSION-$PLATFORM_TAG-$PERL_ARCH-$TIMESTAMP.build.tar.bz2" "./perl-$PERL_VERSION"
}

####################################################################

cd "$WORKDIR" || exit 1

echo "Build started: $(date)"

trap _term SIGINT

check_dependencies

use_perlbrew

mkdir -p ext
rm -f "ext/CamelBones-$CAMELBONES_VERSION".tar.gz

prepare_perl
check_exit_code

prepare_camelbones
check_exit_code

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

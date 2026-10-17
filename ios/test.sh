#!/usr/bin/env bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
PERL5_SOURCE_ROOT="${PERL5_SOURCE_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd -P)}"
WORKDIR="${PERL_IOS_WORKDIR:-$(pwd -P)}"
PERL5_REVISION="${PERL5_REVISION:-HEAD}"

if [ -f "$HOME/perl5/perlbrew/etc/bashrc" ]; then
    source "$HOME/perl5/perlbrew/etc/bashrc"
fi

if [ -n "${IOS_SETUP_FILE:-}" ]; then
    if [ ! -f "$IOS_SETUP_FILE" ]; then
        echo >&2 "IOS_SETUP_FILE does not name a file: $IOS_SETUP_FILE"
        exit 1
    fi
    source "$IOS_SETUP_FILE"
elif [ -e "$WORKDIR/setup_test.sh" ];
    then source "$WORKDIR/setup_test.sh";
elif [ -e "$SCRIPT_DIR/setup_test.sh" ];
    then source "$SCRIPT_DIR/setup_test.sh";
fi

: "${MACOS_PERL_PATH:=$(command -v perl)}"
if [ -z "$MACOS_PERL_PATH" ] || [ ! -x "$MACOS_PERL_PATH" ]; then
    echo >&2 "MACOS_PERL_PATH must name an executable host Perl 5"
    exit 1
fi
export MACOS_PERL_PATH

if [ -z "${IOS_DEVICE_UUID:-${SIMULATOR_DEVICE_UUID:-${IOS_SIMULATOR_UUID:-}}}" ];
    then echo "IOS_DEVICE_UUID or a simulator UUID is unset. Please set it and try again" && exit 1;
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

: "${IOS_DEPLOYMENT_TARGET:=12.0}"

: "${PERL_5_BRANCH:=ios_blead_test}"
INSTALL_DIR_DEFAULTED=0
if [ -z "${INSTALL_DIR:-}" ]; then
    INSTALL_DIR=local
    INSTALL_DIR_DEFAULTED=1
fi
: "${HARNESS_TARGET:=iphoneos}"

case "$HARNESS_TARGET" in
    iphoneos|appletvos|watchos)
        SIMULATOR_BUILD=0
        ;;
    iphonesimulator|appletvsimulator|watchsimulator)
        SIMULATOR_BUILD=1
        ;;
    *)
        echo >&2 "Unsupported HARNESS_TARGET SDK: $HARNESS_TARGET"
        echo >&2 "Use iphoneos, iphonesimulator, appletvos, appletvsimulator, watchos, or watchsimulator"
        exit 1
        ;;
esac
if [ "$SIMULATOR_BUILD" -eq 1 ]; then
    HOST_ARCH=$(uname -m)
    case "$HOST_ARCH" in
        arm64|x86_64) ;;
        *)
            echo >&2 "Unsupported macOS host architecture for simulator build: $HOST_ARCH"
            exit 1
            ;;
    esac
    if [ -n "${ARCHS:-}" ] && [ "$ARCHS" != "$HOST_ARCH" ]; then
        echo >&2 "Simulator builds require host architecture $HOST_ARCH; ARCHS=$ARCHS was requested"
        exit 1
    fi
    ARCHS="$HOST_ARCH"
    echo "Using host architecture $ARCHS for simulator build"

    : "${SIMULATOR_DEVICE_UUID:=${IOS_DEVICE_UUID:-${IOS_SIMULATOR_UUID:-}}}"
    if [ -z "$SIMULATOR_DEVICE_UUID" ]; then
        echo >&2 "SIMULATOR_DEVICE_UUID is unset. Set it to an available simulator UUID and try again"
        exit 1
    fi
    IOS_DEVICE_UUID="$SIMULATOR_DEVICE_UUID"
    DEVICE_TRANSPORT=simulator
else
    : "${ARCHS:=arm64}"
fi

BUILD_SCOPE="$HARNESS_TARGET-$IOS_DEPLOYMENT_TARGET"
if [ "$INSTALL_DIR_DEFAULTED" -eq 1 ]; then
    INSTALL_DIR="local-$BUILD_SCOPE"
fi
export INSTALL_DIR

: "${CAMELBONES_GIT:=https://github.com/jpalao/camelbones.git}"
: "${CAMELBONES_BRANCH:=original}"
: "${CAMELBONES_PREFIX:=$WORKDIR}"
: "${BUILD_CAMELBONES:=1}"

: "${PERL_IOS_PREFIX:=$WORKDIR}"

: "${HARNESS_BUILD_CONFIGURATION:=Debug}"
case "$HARNESS_TARGET" in
    appletvos|appletvsimulator)
        : "${IOS_TEST_APP:=appletv-runner}"
        ;;
    watchsimulator)
        : "${IOS_TEST_APP:=watch-runner}"
        ;;
    *)
        : "${IOS_TEST_APP:=foundation-runner}"
        ;;
esac
case "$IOS_TEST_APP" in
    harness)
        : "${HARNESS_SCHEME:=harness}"
        : "${HARNESS_PRODUCT_NAME:=harness}"
        : "${HARNESS_PROJECT:=harness.xcodeproj}"
        ;;
    foundation-runner|runner)
        : "${HARNESS_SCHEME:=foundation-runner}"
        : "${HARNESS_PRODUCT_NAME:=foundation-runner}"
        : "${HARNESS_PROJECT:=harness.xcodeproj}"
        ;;
    appletv-runner)
        case "$HARNESS_TARGET" in
            appletvos|appletvsimulator) ;;
            *)
                echo >&2 "appletv-runner requires HARNESS_TARGET=appletvos or appletvsimulator"
                exit 1
                ;;
        esac
        : "${HARNESS_SCHEME:=appletv-runner}"
        : "${HARNESS_PRODUCT_NAME:=appletv-runner}"
        : "${HARNESS_PROJECT:=appletv-runner.xcodeproj}"
        ;;
    watch-runner)
        : "${HARNESS_SCHEME:=watch-runner}"
        : "${HARNESS_PRODUCT_NAME:=watch-runner}"
        : "${HARNESS_PROJECT:=watch-runner.xcodeproj}"
        ;;
    *)
        echo >&2 "IOS_TEST_APP must be harness, runner, foundation-runner, watch-runner, or appletv-runner"
        exit 1
        ;;
esac
# Device transport is the real install/copy/launch mechanism.
# Supported values are devicectl and ios-deploy (ios-deploy is the pipeline default).
: "${DEVICE_TRANSPORT:=ios-deploy}"
: "${AUTO_LAUNCH:=1}"
: "${TEST_LOG_WAIT_TIMEOUT:=120}"

PERL_INSTALL_PREFIX="$WORKDIR/$INSTALL_DIR"
PERL_BUILD_DIR="$WORKDIR/perl-$PERL_VERSION-$HARNESS_TARGET-$IOS_DEPLOYMENT_TARGET"
export PERL_BUILD_DIR
REMOTE_TEST_DATA_DIR="Documents"
if [ "$IOS_TEST_APP" = "appletv-runner" ]; then
    REMOTE_TEST_DATA_DIR="Library/Caches"
fi
TEST_STATUS_SOURCE=""
TRANSFER_TRANSPORT=""
DEVICECTL_AVAILABLE=0
DEVICECTL_CONNECTED=0
IOS_DEPLOY_AVAILABLE=0
RUN_LOCK_DIR="$WORKDIR/.perl-ios-test-$BUILD_SCOPE.lock"
TRANSFER_ROOT="$WORKDIR/.ios-test-$BUILD_SCOPE"
CAMELBONES_ROOT="$CAMELBONES_PREFIX/camelbones"
RUN_LOCK_OWNED=0

# CAMELBONES #
export CAMELBONES_PREFIX="$CAMELBONES_PREFIX"
export CAMELBONES_TARGET=$HARNESS_TARGET
export CAMELBONES_BUILD_CONFIGURATION=$HARNESS_BUILD_CONFIGURATION
export CAMELBONES_CI=1
export CAMELBONES_VERSION='1.3.0'
export CAMELBONES_CPAN_DIR="$PERL_BUILD_DIR/ext/CamelBones-$CAMELBONES_VERSION"
export CAMELBONES_FRAMEWORK_DIR="$CAMELBONES_ROOT/CamelBones"
export BUILD_CAMELBONES="$BUILD_CAMELBONES"
export INSTALL_CAMELBONES_FRAMEWORK=0
export OVERWRITE_CAMELBONES_FRAMEWORK=0

# IOS #
export PERL_IOS_PREFIX="$PERL_IOS_PREFIX"
export IOS_TARGET=$HARNESS_TARGET
export IOS_BUILD_CONFIGURATION=$HARNESS_BUILD_CONFIGURATION
export IOS_VERSION='0.0.1'
export IOS_FRAMEWORK_DIR="$PERL_BUILD_DIR/ios/ios"
export IOS_MODULE_PATH="$PERL_BUILD_DIR/ios/ios"
export IOS_CPAN_DIR="$IOS_MODULE_PATH/CPAN"
export IOS_CPAN_EXT_DIR="$PERL_BUILD_DIR/ext/ios"
export INSTALL_IOS_FRAMEWORK=0
export OVERWRITE_IOS_FRAMEWORK=0

export ARCHS="$ARCHS"
export PERL_DIST_PATH="$PERL_INSTALL_PREFIX/lib/perl5"
export LIBPERL_PATH="$PERL_BUILD_DIR"

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

    deps=( "xcodebuild" "xcrun" "git" "rsync" )
    for i in "${deps[@]}"
    do
        command -v $i >/dev/null 2>&1 || {
            echo >&2 "$i is required. Please install it and try again"
            exit 1
        }
    done

    if ! "$MACOS_PERL_PATH" -MFile::Find::Rule -MFile::Copy::Recursive -e 1 >/dev/null 2>&1; then
        echo >&2 "Host Perl $MACOS_PERL_PATH must provide File::Find::Rule and File::Copy::Recursive"
        echo >&2 "Select a host Perl with these modules using MACOS_PERL_PATH; the target Perl version need not match"
        exit 1
    fi

    if [ "$SIMULATOR_BUILD" -eq 1 ]; then
        TRANSFER_TRANSPORT=simulator
        echo "Using simulator $SIMULATOR_DEVICE_UUID"
        return 0
    fi

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
    [ "$BUILD_CAMELBONES" -eq 1 ] || return 0
    if [ -d "$CAMELBONES_ROOT/.git" ]; then
        echo "Using existing CamelBones checkout at $CAMELBONES_ROOT"
        return 0
    fi
    git clone --single-branch --branch "$CAMELBONES_BRANCH" "$CAMELBONES_GIT" "$CAMELBONES_ROOT"
}

prepare_perl() {
    local perl_build_dir
    local perl_revision
    local local_patch
    local ios_harness_source
    local appletv_runner_source
    local appletv_runner_project
    local watch_runner_source
    local watch_runner_project
    local prepare_runtime_source

    perl_build_dir="$PERL_BUILD_DIR"
    rm -Rf "$perl_build_dir"
    git clone --no-checkout "$PERL5_SOURCE_ROOT" "$perl_build_dir"
    git -C "$perl_build_dir" checkout --detach "$PERL5_REVISION"
    local_patch=$(mktemp "${TMPDIR:-/tmp}/perl-ios-source-diff.XXXXXX")
    if ! git -C "$PERL5_SOURCE_ROOT" diff --binary HEAD -- > "$local_patch"; then
        rm -f "$local_patch"
        echo >&2 "failed to collect local Perl source changes"
        return 1
    fi
    if [ -s "$local_patch" ] && ! git -C "$perl_build_dir" apply --whitespace=nowarn "$local_patch"; then
        rm -f "$local_patch"
        echo >&2 "failed to apply local Perl source changes to generated tree"
        return 1
    fi
    rm -f "$local_patch"
    ios_harness_source="$PERL5_SOURCE_ROOT/ios/test/ios_harness"
    if [ ! -f "$ios_harness_source" ]; then
        echo >&2 "missing iOS harness source: $ios_harness_source"
        return 1
    fi
    install -m 755 "$ios_harness_source" "$perl_build_dir/t/ios_harness" || return 1
    if [ "$IOS_TEST_APP" = "appletv-runner" ]; then
        appletv_runner_source="$PERL5_SOURCE_ROOT/ios/test/appletv-runner"
        appletv_runner_project="$PERL5_SOURCE_ROOT/ios/test/appletv-runner.xcodeproj"
        prepare_runtime_source="$PERL5_SOURCE_ROOT/ios/test/prepare-runtime.sh"
        if [ ! -f "$appletv_runner_source/Info.plist" ] ||
            [ ! -f "$appletv_runner_project/project.pbxproj" ] ||
            [ ! -f "$prepare_runtime_source" ]; then
            echo >&2 "missing Apple TV runner or shared runtime packaging sources"
            return 1
        fi
        cp -R "$appletv_runner_source" "$perl_build_dir/ios/test/" || return 1
        cp -R "$appletv_runner_project" "$perl_build_dir/ios/test/" || return 1
        install -m 755 "$prepare_runtime_source" "$perl_build_dir/ios/test/prepare-runtime.sh" || return 1
    elif [ "$IOS_TEST_APP" = "watch-runner" ]; then
        watch_runner_source="$PERL5_SOURCE_ROOT/ios/test/watch-runner"
        watch_runner_project="$PERL5_SOURCE_ROOT/ios/test/watch-runner.xcodeproj"
        prepare_runtime_source="$PERL5_SOURCE_ROOT/ios/test/prepare-runtime.sh"
        if [ ! -f "$watch_runner_source/WatchRunnerApp.swift" ] ||
            [ ! -f "$watch_runner_project/project.pbxproj" ] ||
            [ ! -f "$prepare_runtime_source" ]; then
            echo >&2 "missing Watch runner or shared runtime packaging sources"
            return 1
        fi
        cp -R "$watch_runner_source" "$perl_build_dir/ios/test/" || return 1
        cp -R "$watch_runner_project" "$perl_build_dir/ios/test/" || return 1
        install -m 755 "$prepare_runtime_source" "$perl_build_dir/ios/test/prepare-runtime.sh" || return 1
    fi
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
    rm -Rf "$TRANSFER_ROOT"
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
    "$MACOS_PERL_PATH" -e '
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
        --exclude 'Build/' \
        --exclude 'build/' \
        --exclude '/ios/test/Build/' \
        --exclude '*.bundle' \
        --include '/config.sh' \
        "$source_dir/" "$upload_dir/"; then
        echo >&2 "rsync staging failed for $source_dir"
        return 1
    fi
    refresh_generated_config_timestamps "$upload_dir" || return 1
    echo "Perl tree staging complete."
    return 0
}

simulator_app_group_container() {
    local simulator_data metadata identifier

    simulator_data=$(xcrun simctl getenv "$1" HOME) || return 1
    for metadata in "$simulator_data"/Containers/Shared/AppGroup/*/.com.apple.mobile_container_manager.metadata.plist; do
        [ -f "$metadata" ] || continue
        identifier=$(/usr/libexec/PlistBuddy -c 'Print :MCMMetadataIdentifier' "$metadata" 2>/dev/null) || continue
        if [ "$identifier" = "$2" ]; then
            dirname "$metadata"
            return 0
        fi
    done

    echo >&2 "Could not find simulator App Group container '$2'"
    return 1
}

capture_command_output() {
    local output_file="$TRANSFER_ROOT/command-output.log"
    local status

    mkdir -p "$TRANSFER_ROOT"
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
    local upload_dir="$TRANSFER_ROOT/device-transfer-upload"
    local status

    stage_tree_for_upload "$source_dir" "$upload_dir"
    status=$?
    if [ "$status" -ne 0 ]; then
        rm -Rf "$upload_dir"
        return "$status"
    fi
    echo "Uploading staged Perl tree to $HARNESS_APP_ID/$REMOTE_TEST_DATA_DIR with devicectl..."
    capture_command_output xcrun devicectl device copy to \
        --device "$IOS_DEVICE_UUID" \
        --user mobile \
        --domain-type appDataContainer \
        --domain-identifier "$HARNESS_APP_ID" \
        --source "$upload_dir" \
        --destination "$REMOTE_TEST_DATA_DIR"
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
    local upload_dir="$TRANSFER_ROOT/device-transfer-upload"
    local status

    if [ "$TRANSFER_TRANSPORT" = "ios-deploy" ]; then
        stage_tree_for_upload "$source_dir" "$upload_dir"
        status=$?
        if [ "$status" -ne 0 ]; then
            rm -Rf "$upload_dir"
            return "$status"
        fi
        echo "Uploading staged Perl tree to $HARNESS_APP_ID/$REMOTE_TEST_DATA_DIR with ios-deploy..."
        capture_command_output ios-deploy \
            -i "$IOS_DEVICE_UUID" \
            --bundle_id "$HARNESS_APP_ID" \
            --upload "$upload_dir" \
            --to "/$REMOTE_TEST_DATA_DIR"
        status=$?
        rm -Rf "$upload_dir"
        [ "$status" -eq 0 ] || return "$status"
        build_destination_dir="$HARNESS_APP_ID/$REMOTE_TEST_DATA_DIR (ios-deploy)"
        return 0
    fi

    if [ "$TRANSFER_TRANSPORT" = "devicectl" ]; then
        build_destination_dir="$HARNESS_APP_ID/$REMOTE_TEST_DATA_DIR (devicectl)"
        upload_tree_with_devicectl "$source_dir"
        return $?
    fi

    build_destination_dir="$HARNESS_APP_ID/$REMOTE_TEST_DATA_DIR (devicectl)"
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
    pushd "$PERL_BUILD_DIR/ios/test"
    check_exit_code

    local install_root="$PWD/Build/Install"

    BUILD_CAMELBONES_BOOLEAN="NO"
    if [ $BUILD_CAMELBONES -eq 1 ]; then
        BUILD_CAMELBONES_BOOLEAN="YES"
    fi

    xcodebuild -project "$HARNESS_PROJECT" -sdk "$HARNESS_TARGET" ARCHS="$ARCHS" \
        EMBED_CAMELBONES_FRAMEWORK="$BUILD_CAMELBONES_BOOLEAN" \
        CAMELBONES_FRAMEWORK_PATH="$CAMELBONES_ROOT/CamelBones/build/Products/$CAMELBONES_BUILD_CONFIGURATION-$CAMELBONES_TARGET" \
        IOS_FRAMEWORK_PATH="$PERL_BUILD_DIR/ios/ios/Build/Products/$IOS_BUILD_CONFIGURATION-$IOS_TARGET" \
        PERL_DIST_PATH="$PERL_INSTALL_PREFIX/lib/perl5" \
        PERL_INSTALL_PREFIX="$PERL_INSTALL_PREFIX" \
        LIBPERL_PATH="$PERL_INSTALL_PREFIX/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/CORE" \
        PERL_VERSION="$PERL_VERSION" ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO \
        MACOS_PERL_PATH="$MACOS_PERL_PATH" \
        DSTROOT="$install_root" -configuration "$HARNESS_BUILD_CONFIGURATION" \
        -allowProvisioningUpdates -scheme "$HARNESS_SCHEME" clean install
    check_exit_code

    # Install the app before copying test data into its sandbox.
    simulator_build="$SIMULATOR_BUILD"
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
        copy_tree_to_device "$PERL_BUILD_DIR"
        check_exit_code
    else
        if [ "$HARNESS_TARGET" = "watchsimulator" ]; then
            build_destination_dir=$(simulator_app_group_container "$IOS_DEVICE_UUID" group.net.pytm.perl.watchrunner)
            check_exit_code $? "simulator App Group lookup"
        else
            build_destination_dir=$(xcrun simctl get_app_container "$IOS_DEVICE_UUID" "$HARNESS_APP_ID" data)
            check_exit_code $? "simulator app data lookup"
        fi
        build_destination_dir="$build_destination_dir/$REMOTE_TEST_DATA_DIR/"
        simulator_stage_dir="$TRANSFER_ROOT/simulator-stage"
        stage_tree_for_upload "$PERL_BUILD_DIR" "$simulator_stage_dir"
        check_exit_code $? "simulator tree staging"
        cp -RL "$simulator_stage_dir/." "$build_destination_dir"
        rm -Rf "$simulator_stage_dir"
        check_exit_code
        rm -f "$build_destination_dir/perl-tests.status"
        check_exit_code $? "clear stale simulator test status"
    fi

    echo "App test data dir is '$build_destination_dir'"

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

####################################################################

cd "$WORKDIR" || exit 1

echo "Build started: $(date)"

trap cleanup EXIT
trap 'exit 130' SIGINT SIGTERM SIGHUP

acquire_run_lock

check_dependencies

mkdir -p ext
rm -f "ext/CamelBones-$CAMELBONES_VERSION".tar.gz

prepare_perl
check_exit_code

prepare_camelbones
check_exit_code

rm -Rf "$INSTALL_DIR"

PERL_ARCH="$ARCHS" DEBUG=1 sh -x "$PERL_BUILD_DIR/ios/build.sh"
check_exit_code

# enable APItest.bundle and Typemap.bundle loading
mkdir -p "$INSTALL_DIR/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/auto/XS/APItest"
mkdir -p "$INSTALL_DIR/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/auto/XS/Typemap"
cp "$PERL_BUILD_DIR/lib/auto/XS/APItest/APItest.bs" "$INSTALL_DIR/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/auto/XS/APItest"
cp "$PERL_BUILD_DIR/lib/auto/XS/APItest/APItest.bundle" "$INSTALL_DIR/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/auto/XS/APItest"
cp "$PERL_BUILD_DIR/lib/auto/XS/Typemap/Typemap.bundle" "$INSTALL_DIR/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/auto/XS/Typemap"

mkdir -p "$INSTALL_DIR/lib/perl5/$PERL_VERSION/XS/"
chmod u+w "$INSTALL_DIR/lib/perl5/$PERL_VERSION/XS/APItest.pm" 2>/dev/null || true
cp "$PERL_BUILD_DIR/lib/XS/APItest.pm" "$INSTALL_DIR/lib/perl5/$PERL_VERSION/XS/"
check_exit_code $? "APItest.pm installation"

mkdir -p "$INSTALL_DIR/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/TAP/Parser/Iterator"
mkdir -p "$INSTALL_DIR/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/TAP/Parser/SourceHandler"
chmod u+w "$INSTALL_DIR/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/TAP/Parser/Iterator/iOS.pm" 2>/dev/null || true
chmod u+w "$INSTALL_DIR/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/TAP/Parser/SourceHandler/iOSExecutable.pm" 2>/dev/null || true
chmod u+w "$INSTALL_DIR/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/TAP/Parser/SourceHandler/iOSPerl.pm" 2>/dev/null || true
cp "$PERL_BUILD_DIR/lib/TAP/Parser/Iterator/iOS.pm" \
    "$INSTALL_DIR/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/TAP/Parser/Iterator/"
cp "$PERL_BUILD_DIR/lib/TAP/Parser/SourceHandler/iOSExecutable.pm" \
    "$INSTALL_DIR/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/TAP/Parser/SourceHandler/"
cp "$PERL_BUILD_DIR/lib/TAP/Parser/SourceHandler/iOSPerl.pm" \
    "$INSTALL_DIR/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/TAP/Parser/SourceHandler/"
check_exit_code $? "iOS TAP module installation"

test_perl_device

echo "Build finished: $(date)"

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
: "${USE_IFUSE:=auto}"

PERL_INSTALL_PREFIX="$WORKDIR/$INSTALL_DIR"
REMOTE_DOCUMENTS_DIR="Documents"
REMOTE_TEST_LOG="$REMOTE_DOCUMENTS_DIR/perl-tests.txt"
PERL_TEST_LOG="$WORKDIR/perl-tests.txt"
TRANSFER_TRANSPORT=""
REFRESH_PID=""

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

check_dependencies() {
    deps=( "xcodebuild" "git" "perl" "perlbrew" "ios-deploy" "rsync" )
    for i in "${deps[@]}"
    do
        command -v $i >/dev/null 2>&1 || {
            echo >&2 "$i is required. Please install it and try again"
            exit 1
        }
    done

    case "$USE_IFUSE" in
        0)
            TRANSFER_TRANSPORT="ios-deploy"
            ;;
        1)
            command -v ifuse >/dev/null 2>&1 || {
                echo >&2 "USE_IFUSE=1 requires ifuse"
                exit 1
            }
            TRANSFER_TRANSPORT="ifuse"
            ;;
        auto)
            if command -v ifuse >/dev/null 2>&1; then
                TRANSFER_TRANSPORT="ifuse"
            else
                TRANSFER_TRANSPORT="ios-deploy"
            fi
            ;;
        *)
            echo >&2 "USE_IFUSE must be 0, 1, or auto"
            exit 1
            ;;
    esac

    echo "Device file transport: $TRANSFER_TRANSPORT"
}

check_exit_code() {
    local status=${1:-$?}
    if [ "$status" -ne 0 ]; then
    echo "Failed to build perl for $HARNESS_TARGET"
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
    perl_build_dir="$WORKDIR/perl-$PERL_VERSION"
    rm -Rf "$perl_build_dir"
    git clone --no-checkout "$PERL5_SOURCE_ROOT" "$perl_build_dir"
    git -C "$perl_build_dir" checkout --detach "$PERL5_REVISION"
    echo "Building perl5 revision $(git -C "$perl_build_dir" rev-parse HEAD)"
}

_term() {
    if [ -n "$REFRESH_PID" ]; then
        echo "Killing refresh process..."
        kill -TERM "$REFRESH_PID" >/dev/null 2>&1 || true
    fi
    if [ "$TRANSFER_TRANSPORT" = "ifuse" ]; then
        umount -f "$IOS_MOUNTPOINT" >/dev/null 2>&1 || true
    fi
    rm -Rf "$WORKDIR/.ios-deploy-download"
    exit 0
}

mount_harness_documents() {
    umount -f "$IOS_MOUNTPOINT" >/dev/null 2>&1 || true
    mkdir -p "$IOS_MOUNTPOINT"
    ifuse "$IOS_MOUNTPOINT" -u "$IOS_DEVICE_UUID" -o volname=harness --documents "$HARNESS_APP_ID"
}

upload_tree_with_ios_deploy() {
    local source_dir="$1"
    local upload_dir="$WORKDIR/.ios-deploy-upload"
    local status

    rm -Rf "$upload_dir"
    mkdir -p "$upload_dir"
    rsync -aL \
        --exclude '/ios/test/Build/' \
        --exclude '*.bundle' \
        "$source_dir/" "$upload_dir/"
    check_exit_code

    ios-deploy -i "$IOS_DEVICE_UUID" -1 "$HARNESS_APP_ID" \
        --upload "$upload_dir" --to "$REMOTE_DOCUMENTS_DIR"
    status=$?
    rm -Rf "$upload_dir"
    return "$status"
}

download_test_log_with_ios_deploy() {
    local download_dir="$WORKDIR/.ios-deploy-download"
    local downloaded_log="$download_dir/$REMOTE_TEST_LOG"

    rm -Rf "$download_dir"
    ios-deploy -i "$IOS_DEVICE_UUID" -1 "$HARNESS_APP_ID" \
        --download="$REMOTE_TEST_LOG" --to "$download_dir" >/dev/null 2>&1 || return 1
    [ -f "$downloaded_log" ] || return 1
    cat "$downloaded_log" > "$PERL_TEST_LOG"
}

refresh_test_log_with_ios_deploy() {
    while true; do
        download_test_log_with_ios_deploy || true
        sleep 2
    done
}

launch_harness() {
    if ios-deploy -i "$IOS_DEVICE_UUID" --noinstall --justlaunch --bundle "$test_app"; then
        return 0
    fi

    echo "Automatic launch requires DeviceSupport for the connected iOS version."
    if [ -t 0 ]; then
        read -r -p "Launch the harness on the iPhone, then press Return to continue: "
        return 0
    fi

    echo >&2 "Launch the harness manually and rerun in an interactive terminal"
    return 1
}

copy_tree_to_device() {
    local source_dir="$1"

    if [ "$TRANSFER_TRANSPORT" = "ifuse" ]; then
        if mount_harness_documents; then
            build_destination_dir="$IOS_MOUNTPOINT"
            cp -RL "$source_dir/." "$build_destination_dir" 2>/dev/null
            check_exit_code
            rm -Rf "$build_destination_dir/ios/test/Build"
            find "$build_destination_dir" -name "*.bundle" -type f -delete
            check_exit_code
            return 0
        fi

        if [ "$USE_IFUSE" = "1" ]; then
            echo >&2 "Failed to mount harness Documents with ifuse"
            return 1
        fi

        echo "ifuse mount failed; falling back to ios-deploy"
        TRANSFER_TRANSPORT="ios-deploy"
    fi

    build_destination_dir="$HARNESS_APP_ID/$REMOTE_DOCUMENTS_DIR (ios-deploy)"
    upload_tree_with_ios_deploy "$source_dir"
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

    if [ "$simulator_build" -eq "0" ]; then
        ios-deploy -r -i "$IOS_DEVICE_UUID" --bundle "$test_app"
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
        if [ "$TRANSFER_TRANSPORT" = "ifuse" ]; then
            umount -f "$IOS_MOUNTPOINT"
        fi
        launch_harness
        check_exit_code
    else
        xcrun simctl launch "$IOS_DEVICE_UUID" "$HARNESS_APP_ID"
        check_exit_code
        PERL_TEST_LOG="$build_destination_dir/perl-tests.txt"
    fi

    popd

    if [ "$simulator_build" -eq "0" ]; then
        if [ "$TRANSFER_TRANSPORT" = "ifuse" ]; then
            if ! mount_harness_documents; then
                if [ "$USE_IFUSE" = "1" ]; then
                    check_exit_code 1
                fi
                echo "ifuse remount failed; using ios-deploy for the test log"
                TRANSFER_TRANSPORT="ios-deploy"
            fi
        fi

        if [ "$TRANSFER_TRANSPORT" = "ifuse" ]; then
            PERL_TEST_LOG="$IOS_MOUNTPOINT/perl-tests.txt"
            sleep 2
            # needed for scrolling to keep in sync w/ device's ifuse fs
            perl -e "while (1) {sleep 1; system qw (ls $IOS_MOUNTPOINT);} " > /dev/null 2>&1 &
            REFRESH_PID=$!
        else
            PERL_TEST_LOG="$WORKDIR/perl-tests.txt"
            rm -f "$PERL_TEST_LOG"
            while ! download_test_log_with_ios_deploy; do
                sleep 2
            done
            refresh_test_log_with_ios_deploy &
            REFRESH_PID=$!
        fi
    fi

    sleep 3

    tail -n 3000 -f "$PERL_TEST_LOG"

    if [ "$simulator_build" -eq "0" ]; then
        echo "kill $REFRESH_PID"
        kill "$REFRESH_PID" >/dev/null 2>&1 || true
        REFRESH_PID=""
        if [ "$TRANSFER_TRANSPORT" = "ifuse" ]; then
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
cp "perl-$PERL_VERSION/lib/XS/APItest.pm" "$INSTALL_DIR/lib/perl5/$PERL_VERSION/XS/"

test_perl_device

echo "Build finished: $(date)"

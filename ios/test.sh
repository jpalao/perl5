#!/usr/bin/env sh

source $HOME/perl5/perlbrew/etc/bashrc
if [ -e setup_test.sh ];
    then source setup_test.sh;
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

: "${PERL_MAJOR_VERSION:=35}"
: "${PERL_MINOR_VERSION:=4}"

export PERL_VERSION="5.$PERL_MAJOR_VERSION.$PERL_MINOR_VERSION"

: "${PERL5_GIT:=https://github.com/jpalao/perl5.git}"
: "${PERL_5_BRANCH:=ios_blead_test}"
: "${INSTALL_DIR:=local}"
: "${ARCHS:=arm64}"

WORKDIR=`pwd`

: "${IOS_GIT:=https://github.com/jpalao/ios.git}"
: "${IOS_BRANCH:=master}"
: "${PERL_IOS_PREFIX:=$WORKDIR}"
: "${IOS_MOUNTPOINT:=$WORKDIR/_ios_mount}"

: "${HARNESS_TARGET:=iphoneos}"
: "${HARNESS_BUILD_CONFIGURATION:=Debug}"

PERL_INSTALL_PREFIX="$WORKDIR/$INSTALL_DIR"
PERL_TEST_LOG="$IOS_MOUNTPOINT/perl-tests.txt"

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
    deps=( "xcodebuild" "git" "perl" "perlbrew" "ifuse" "ios-deploy" )
    for i in "${deps[@]}"
    do
        command -v $i >/dev/null 2>&1 || {
            echo >&2 "$i is required. Please install it and try again"
            exit 1
        }
    done
}

check_exit_code() {
  if [ $? -ne 0 ]; then
    echo "Failed to build perl for $HARNESS_TARGET"
    exit $?
  fi
}

prepare_ios() {
  rm -Rf $1
  git clone --single-branch --branch "$IOS_BRANCH" "$IOS_GIT" $1
}

prepare_perl() {
  rm -Rf "perl-$PERL_VERSION"
  git clone --single-branch --branch "$PERL_5_BRANCH" "$PERL5_GIT" "perl-$PERL_VERSION"
}

build_libffi() {
    pushd ./libffi-3.2.1
    xcodebuild -scheme libffi-"$IOS_TARGET"
    check_exit_code
    popd
}

_term() {
  echo "Killing refresh process..."
  kill -TERM "$REFRESH_PID" 2>&1 > /dev/null
  exit 0;
}

test_perl_device() {
    echo "Mount iOS device under $IOS_MOUNTPOINT"

    umount -f $IOS_MOUNTPOINT

    mkdir -p $IOS_MOUNTPOINT
    check_exit_code

    pushd "perl-$PERL_VERSION/ios/test"
    check_exit_code

    xcodebuild ARCHS="$ARCHS" \
        IOS_FRAMEWORK_PATH="$PERL_IOS_PREFIX/perl-$PERL_VERSION/ios/ios/build/Products/$IOS_BUILD_CONFIGURATION-$IOS_TARGET" \
        PERL_DIST_PATH="$PERL_INSTALL_PREFIX/lib/perl5" \
        LIBPERL_PATH="$PERL_INSTALL_PREFIX/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/CORE" \
        PERL_VERSION="$PERL_VERSION" ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO -scheme harness
    check_exit_code

    # install the app so it can receive files in Documents
    simulator_build=`echo "$ARCHS" | grep -c "x86_64"` # x86_64 simulator
    test_app="Build/Products/$HARNESS_BUILD_CONFIGURATION-$HARNESS_TARGET/harness.app"

    if [ "$simulator_build" -eq "0" ]; then
        ios-deploy -r -i "$IOS_DEVICE_UUID" --bundle "$test_app"
        check_exit_code

        rm -Rf "$IOS_MOUNTPOINT/*"
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
        build_destination_dir="$IOS_MOUNTPOINT"
        ifuse $IOS_MOUNTPOINT -u "$IOS_DEVICE_UUID" -o volname=harness --documents "$HARNESS_APP_ID"
    else # ARM device
        build_destination_dir=`xcrun simctl get_app_container "$IOS_DEVICE_UUID" "$HARNESS_APP_ID" data`
        build_destination_dir="$build_destination_dir/Documents/"
    fi

    echo "App Documents dir is '$build_destination_dir'"

    if [ "$simulator_build" -eq "0" ]; then
        cp -RL "$WORKDIR/perl-$PERL_VERSION/." "$build_destination_dir" 2>/dev/null
    else # ARM device
        cp -RL "$WORKDIR/perl-$PERL_VERSION/." "$build_destination_dir"
    fi

    #check_exit_code

    echo "Delete Build dir..."
    rm -Rf "$build_destination_dir/ios/test/Build"

    echo "Delete unsigned bundle files from harness mountpoint..."
    find $build_destination_dir -name "*.bundle" -type f -delete
    check_exit_code

    if [ "$simulator_build" -eq "0" ]; then
        umount -f $IOS_MOUNTPOINT
        #check_exit_code
        ios-deploy --noinstall --justlaunch --debug --bundle "$test_app"
        check_exit_code
    else
        xcrun simctl launch "$IOS_DEVICE_UUID" "$HARNESS_APP_ID"
        check_exit_code
    fi

    popd

    if [ "$simulator_build" -eq "0" ]; then
        ifuse $IOS_MOUNTPOINT -u "$IOS_DEVICE_UUID" -o volname=harness --documents "$HARNESS_APP_ID"
        check_exit_code
        sleep 2
        # needed for scrolling to keep in sync w/ device's ifuse fs
        perl -e "while (1) {sleep 1; system qw (ls $IOS_MOUNTPOINT);} " > /dev/null 2>&1 &
        REFRESH_PID=$!
    fi

    sleep 3

    tail -n 3000 -f $build_destination_dir/perl-tests.txt

    if [ "$simulator_build" -eq "0" ]; then
        echo "kill $REFRESH_PID"
        kill $REFRESH_PID
        check_exit_code
        umount -f $IOS_MOUNTPOINT
        #rm -Rf $IOS_MOUNTPOINT
        check_exit_code
    fi
}

build_ios_framework() {

    pushd $IOS_FRAMEWORK_DIR
    check_exit_code

    xcodebuild ARCHS="$ARCHS" PERL_DIST_PATH="$PERL_INSTALL_PREFIX/lib/perl5" \
    LIBPERL_PATH="$PERL_INSTALL_PREFIX/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/CORE" \
    PERL_VERSION="$PERL_VERSION" ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO \
    -scheme "$IOS_TARGET"
    popd
}

build_macos_perl() {
    # uninstall perl-blead
    echo "Uninstalling perl-blead"
    perlbrew uninstall -q perl-blead

    echo "Installing perl-blead"
    # macOS generate_uudmap and miniperl are used in cross builds
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

echo "Build started: $(date)"

trap _term SIGINT

check_dependencies

use_perlbrew

prepare_perl
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

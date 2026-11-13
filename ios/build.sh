#!/usr/bin/env sh

############## CONFIG BEGIN ##############

# perl binaries
: "${BITCODE:=0}"
: "${DEBUG:=0}"
: "${IOS_BUILD_CONFIGURATION:=Release}"
export IOS_BUILD_CONFIGURATION
: "${INSTALL_DIR:=local}"
if [ -n "${IOS_DEPLOYMENT_TARGET:-}" ] && [ -n "${MIN_VERSION:-}" ] &&
   [ "$IOS_DEPLOYMENT_TARGET" != "$MIN_VERSION" ]; then
  echo >&2 "IOS_DEPLOYMENT_TARGET and MIN_VERSION must match"
  exit 1
fi
: "${MIN_VERSION:=${IOS_DEPLOYMENT_TARGET:-12.0}}"
export MIN_VERSION
export IOS_DEPLOYMENT_TARGET="$MIN_VERSION"
unset MACOSX_DEPLOYMENT_TARGET IPHONEOS_DEPLOYMENT_TARGET
unset TVOS_DEPLOYMENT_TARGET WATCHOS_DEPLOYMENT_TARGET
unset APPLETV_DEPLOYMENT_TARGET

# Xcode
: "${XCODE_PATH:=/Applications/Xcode.app}"
: "${XCODE_DEVELOPER_PATH:=$XCODE_PATH/Contents/Developer}"
: "${IOS_DEVICE_SDK_PATH:=$XCODE_PATH/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk}"
: "${IOS_SIMULATOR_SDK_PATH:=$XCODE_PATH/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk}"
: "${APPLETV_DEVICE_SDK_PATH:=$XCODE_PATH/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk}"
: "${APPLETV_SIMULATOR_SDK_PATH:=$XCODE_PATH/Contents/Developer/Platforms/AppleTVSimulator.platform/Developer/SDKs/AppleTVSimulator.sdk}"
: "${WATCHOS_DEVICE_SDK_PATH:=$XCODE_PATH/Contents/Developer/Platforms/WatchOS.platform/Developer/SDKs/WatchOS.sdk}"
: "${WATCHOS_SIMULATOR_SDK_PATH:=$XCODE_PATH/Contents/Developer/Platforms/WatchSimulator.platform/Developer/SDKs/WatchSimulator.sdk}"

# CamelBones
: "${BUILD_CAMELBONES:=0}"

############## CONFIG END ##############

SCRIPTPATH="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"

PERL_REVISION=5

PERL_MAJOR_VERSION=`awk '/define[ 	]+PERL_VERSION/ {print $3}' "$SCRIPTPATH/../patchlevel.h"`
PERL_MINOR_VERSION=`awk '/define[ 	]+PERL_SUBVERSION/ {print $3}' "$SCRIPTPATH/../patchlevel.h"`

if [ -z "${IOS_TARGET:-}" ]; then
  echo >&2 "IOS_TARGET must name the target SDK; PERL_ARCH cannot distinguish a device from a simulator"
  exit 1
fi

case "$IOS_TARGET" in
  iphoneos|appletvos|watchos)
    SIMULATOR_BUILD=0
    ;;
  iphonesimulator|appletvsimulator|watchsimulator)
    SIMULATOR_BUILD=1
    ;;
  *)
    echo >&2 "Unsupported target SDK: $IOS_TARGET"
    echo >&2 "Use iphoneos, iphonesimulator, appletvos, appletvsimulator, watchos, or watchsimulator"
    exit 1
    ;;
esac

case "$IOS_TARGET" in
  iphoneos|iphonesimulator) target_appletv=0; target_applewatch=0 ;;
  appletvos|appletvsimulator) target_appletv=1; target_applewatch=0 ;;
  watchos|watchsimulator) target_appletv=0; target_applewatch=1 ;;
esac
if { [ -n "${PERL_APPLETV:-}" ] && [ "$PERL_APPLETV" != "$target_appletv" ]; } ||
   { [ -n "${PERL_APPLEWATCH:-}" ] && [ "$PERL_APPLEWATCH" != "$target_applewatch" ]; }; then
  echo >&2 "Ignoring PERL_APPLETV/PERL_APPLEWATCH values that conflict with IOS_TARGET=$IOS_TARGET"
fi
PERL_APPLETV=$target_appletv
PERL_APPLEWATCH=$target_applewatch
export PERL_APPLETV PERL_APPLEWATCH

if [ $PERL_APPLETV -ne 0 ]; then
  PLATFORM_TAG="appletv"
  DEVICE_SDK_PATH="$APPLETV_DEVICE_SDK_PATH"
  SIMULATOR_SDK_PATH="$APPLETV_SIMULATOR_SDK_PATH"
  PERL_PLATFORM_TAG="PERL_APPLETV"
  export PERL_IOS=1
elif [ $PERL_APPLEWATCH -ne 0 ]; then
  PLATFORM_TAG="watch"
  DEVICE_SDK_PATH="$WATCHOS_DEVICE_SDK_PATH"
  SIMULATOR_SDK_PATH="$WATCHOS_SIMULATOR_SDK_PATH"
  PERL_PLATFORM_TAG="PERL_APPLEWATCH"
  export PERL_IOS=1
else
  PLATFORM_TAG="iphone"
  DEVICE_SDK_PATH="$IOS_DEVICE_SDK_PATH"
  SIMULATOR_SDK_PATH="$IOS_SIMULATOR_SDK_PATH"
  PERL_PLATFORM_TAG="PERL_IOS"
  export PERL_IOS=1
fi

WORKDIR=`pwd`
PREFIX="$WORKDIR/$INSTALL_DIR"
PERL_VERSION="$PERL_REVISION.$PERL_MAJOR_VERSION.$PERL_MINOR_VERSION"
: "${PERL_BUILD_DIR:=$WORKDIR/perl-$PERL_VERSION}"

if [ "$SIMULATOR_BUILD" -eq 1 ]; then
  HOST_ARCH=$(uname -m)
  case "$HOST_ARCH" in
    arm64|x86_64) ;;
    *)
      echo >&2 "Unsupported macOS host architecture for simulator build: $HOST_ARCH"
      exit 1
      ;;
  esac
  if [ -n "${PERL_ARCH:-}" ] && [ "$PERL_ARCH" != "$HOST_ARCH" ]; then
    echo >&2 "Simulator builds require host architecture $HOST_ARCH; PERL_ARCH=$PERL_ARCH was requested"
    exit 1
  fi
  if [ -n "${ARCHS:-}" ] && [ "$ARCHS" != "$HOST_ARCH" ]; then
    echo >&2 "Simulator builds require host architecture $HOST_ARCH; ARCHS=$ARCHS was requested"
    exit 1
  fi
  PERL_ARCH="$HOST_ARCH"
  ARCHS="$HOST_ARCH"
  export ARCHS
  echo "Using host architecture $PERL_ARCH for simulator build"
else
  : "${PERL_ARCH:=arm64}"
fi

# Platform version flags select the correct Mach-O platform for all link steps.
case "$IOS_TARGET" in
  iphonesimulator)
    MIN_VERSION_TAG="-mios-simulator-version-min=$MIN_VERSION"
    ;;
  appletvsimulator)
    MIN_VERSION_TAG="-mtvos-simulator-version-min=$MIN_VERSION"
    ;;
  watchsimulator)
    MIN_VERSION_TAG="-mwatchos-simulator-version-min=$MIN_VERSION"
    ;;
  *)
    MIN_VERSION_TAG="-m${PLATFORM_TAG}os-version-min=$MIN_VERSION"
    ;;
esac

case "$PERL_ARCH" in
  arm64|armv7|armv7s|armv7k|x86_64|i386) ;;
  *)
    echo >&2 "Unsupported architecture: $PERL_ARCH"
    exit 1
    ;;
esac

mkdir "$PREFIX"
mkdir "$PREFIX/lib"
mkdir "$PREFIX/include"

# passed to Configure as optimize; release matches the darwin hints default
if [ $DEBUG -eq 1 ]; then
  OPTIMIZER="-O0 -g"
else
  OPTIMIZER="-O3"
fi

# simulator builds cannot produce bitcode
if [ $SIMULATOR_BUILD -eq 1 ]; then
  BITCODE=0
elif [ $PERL_APPLEWATCH -ne 0 ]; then
  PERL_ARCH="armv7k"
fi

BITCODE_BUILD_FLAGS=""
if [ $BITCODE -ne 0 ]; then
  BITCODE_BUILD_FLAGS="-fembed-bitcode"
fi

ARCH_FLAGS="-arch $PERL_ARCH"

SIMULATOR_BUILD_FLAGS="-DPERL_IOS -I$PREFIX/include -I$SIMULATOR_SDK_PATH/usr/include $ARCH_FLAGS $MIN_VERSION_TAG -isysroot $SIMULATOR_SDK_PATH"
# Apple silicon only runs signed simulator executables, and ld does not sign every target.
SIMULATOR_LINK_FLAGS="-DPERL_IOS $ARCH_FLAGS $MIN_VERSION_TAG -isysroot $SIMULATOR_SDK_PATH -L$PREFIX/lib -L$SIMULATOR_SDK_PATH/usr/lib -Wl,-adhoc_codesign"

DEVICE_BUILD_FLAGS="-DPERL_IOS -I$PREFIX/include -I$DEVICE_SDK_PATH/usr/include $ARCH_FLAGS $MIN_VERSION_TAG -isysroot $DEVICE_SDK_PATH $BITCODE_BUILD_FLAGS"
DEVICE_LINK_FLAGS="-DPERL_IOS $ARCH_FLAGS $MIN_VERSION_TAG -isysroot $DEVICE_SDK_PATH -L$PREFIX/include -L$DEVICE_SDK_PATH/usr/lib"

if [ $SIMULATOR_BUILD -ne 0 ]; then
  BUILD_FLAGS="$SIMULATOR_BUILD_FLAGS"
  BUILD_FLAGS="$BUILD_FLAGS -DNO_LOCALE"
  LINK_FLAGS="$SIMULATOR_LINK_FLAGS"
  SDK_PATH="$SIMULATOR_SDK_PATH"
else
  BUILD_FLAGS="$DEVICE_BUILD_FLAGS"
  LINK_FLAGS="$DEVICE_LINK_FLAGS"
  SDK_PATH="$DEVICE_SDK_PATH"
fi

if [ -n "${IOS_PLATFORM:-}" ] && [ "$IOS_PLATFORM" != "$IOS_TARGET" ]; then
  echo >&2 "Ignoring IOS_PLATFORM=$IOS_PLATFORM; IOS_TARGET=$IOS_TARGET selects the SDK"
fi
IOS_PLATFORM="$IOS_TARGET"
export IOS_PLATFORM
export IOS_ARCH="$PERL_ARCH"
export IOS_SDKROOT="$SDK_PATH"

BUILD_FLAGS="$BUILD_FLAGS -D$PERL_PLATFORM_TAG"
LINK_FLAGS="$LINK_FLAGS -D$PERL_PLATFORM_TAG"

######################################################
# Build perl
######################################################

boot_simulator_for_probes() {
  local simulator_uuid="${IOS_DEVICE_UUID:-}"

  case "$IOS_PLATFORM" in
    *simulator) ;;
    *) return 0 ;;
  esac
  if [ -z "$simulator_uuid" ]; then
    echo >&2 "IOS_DEVICE_UUID is unset. Set it to the selected simulator UUID and try again"
    return 1
  fi

  echo "Ensuring simulator $simulator_uuid is booted for Configure probes"
  xcrun simctl boot "$simulator_uuid" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$simulator_uuid" -b
}

build_perl() {
  cd "$WORKDIR"

  if [ -d "$WORKDIR/ext" ]; then
    # Only unpack extension archives when they are actually present.
    if ls "$WORKDIR"/ext/*.tar.gz >/dev/null 2>&1; then
      for f in "$WORKDIR"/ext/*.tar.gz
      do
        echo "$f is"
        echo "Installing perl extension $f..."
        tar xvfz "$f" -C "$PERL_BUILD_DIR/ext"
      done
    else
      echo "No extension archives found in $WORKDIR/ext"
    fi
  fi

  cd "$PERL_BUILD_DIR"

  export SDKROOT="$SDK_PATH"
  export CC=/usr/bin/clang

  # export min version
  if [ $PERL_APPLETV -ne 0 ]; then
    export APPLETV_DEPLOYMENT_TARGET="$MIN_VERSION"
  elif [ $PERL_APPLEWATCH -ne 0 ]; then
    export WATCHOS_DEPLOYMENT_TARGET="$MIN_VERSION"
  else
    export IPHONEOS_DEPLOYMENT_TARGET="$MIN_VERSION"
  fi

  boot_simulator_for_probes || exit 1

  env -u SDKROOT \
    -u IPHONEOS_DEPLOYMENT_TARGET \
    -u APPLETV_DEPLOYMENT_TARGET \
    -u WATCHOS_DEPLOYMENT_TARGET \
    ./Configure -des -Dusedevel \
    -Dusecrosscompile \
    -U i_gdbmndbm \
    -U i_gdbm_ndbm \
    -Duseshrplib \
    -Dusethreads \
    -Dd_pseudofork=define \
    -Dtargethost=physical-device \
    -Dtargetrun=darwin-ios \
    -Dtargetarch="${PERL_ARCH}-darwin" \
    -Dios_sdk="$IOS_PLATFORM" \
    -Dcc=/usr/bin/clang \
    -Dccflags="$BUILD_FLAGS" \
    -Doptimize="$OPTIMIZER" \
    -Dldflags="$LINK_FLAGS" \
    -Dlibs='-lm -lc' \
    -Dprefix="$PREFIX"

  make depend
  check_exit_code

  make
  check_exit_code

  prepare_ios_module_source
  build_ios_framework

  mkdir -p $IOS_CPAN_EXT_DIR
  chmod -R +w $IOS_CPAN_EXT_DIR
  echo cp -Rv "$IOS_CPAN_DIR/." $IOS_CPAN_EXT_DIR/
  cp -Rv "$IOS_CPAN_DIR/." $IOS_CPAN_EXT_DIR/

  if [ $BUILD_CAMELBONES -eq 1 ]; then
      build_camelbones_framework
  fi

  if [ $BUILD_CAMELBONES -eq 1 ]; then
    mkdir -p "$CAMELBONES_CPAN_DIR"
    chmod -R +w "$CAMELBONES_CPAN_DIR"
    echo cp -R "$CAMELBONES_FRAMEWORK_DIR/CPAN/." "$CAMELBONES_CPAN_DIR/"
    cp -R "$CAMELBONES_FRAMEWORK_DIR/CPAN/." "$CAMELBONES_CPAN_DIR/"
  fi

  DYLD_LIBRARY_PATH=`pwd` ./miniperl -Ilib make_ext.pl ext/ios/pm_to_blib  MAKE="$XCODE_DEVELOPER_PATH/usr/bin/make" LIBPERL_A=libperl.dylib
  check_exit_code

  if [ $BUILD_CAMELBONES -eq 1 ]; then
    DYLD_LIBRARY_PATH=`pwd` ./miniperl -Ilib make_ext.pl "ext/CamelBones-$CAMELBONES_VERSION/pm_to_blib"  MAKE="$XCODE_DEVELOPER_PATH/usr/bin/make" LIBPERL_A=libperl.dylib
    check_exit_code
  fi

  make test_prep
  #make test would fail

  make install
  check_exit_code

  # Generate symbols for both optimized and debug builds.
  echo "Generate libperl.dylib.dSYM..."
  pushd "$PREFIX/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/CORE"
  dsymutil libperl.dylib
  check_exit_code
  echo "$PREFIX/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/CORE/libperl.dylib.dSYM"
  popd

  #change install name of library for embedding
  chmod +w "$PREFIX/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/CORE/libperl.dylib"
  install_name_tool -id @rpath/libperl.dylib "$PREFIX/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/CORE/libperl.dylib"
  cd ..
}

delete_installed_perl() {
  rm -Rf "$PREFIX/bin/*"
  rm -Rf "$PREFIX/lib/*"
  rm -Rf "$PREFIX/doc/*"
  rm -Rf "$PREFIX/share/*"
  rm -Rf "$PREFIX/include/*"
}

check_exit_code() {
  status=${1:-$?}
  if [ "$status" -ne 0 ]; then
    echo "Failed to build perl for Apple platform $PLATFORM_TAG"
    exit "$status"
  fi
}

build_ios_framework() {
    pushd $IOS_FRAMEWORK_DIR
    check_exit_code

    local framework_other_cflags=""
    local framework_scheme="$IOS_TARGET"
    local framework_debug_settings="DEBUG_INFORMATION_FORMAT=dwarf-with-dsym GCC_GENERATE_DEBUGGING_SYMBOLS=YES"
    if [ "$DEBUG" -eq 1 ]; then
      framework_debug_settings="$framework_debug_settings GCC_OPTIMIZATION_LEVEL=0"
    fi
    if [ "$SIMULATOR_BUILD" -ne 0 ]; then
      framework_other_cflags="-DNO_LOCALE"
    fi

    if [ $PERL_APPLETV -ne 0 ]; then
      case "$IOS_PLATFORM" in
        appletvsimulator) framework_scheme="iphonesimulator" ;;
        appletvos) framework_scheme="iphoneos" ;;
      esac
      xcodebuild -sdk "$IOS_PLATFORM" ARCHS="$ARCHS" VALID_ARCHS="$ARCHS" \
      OTHER_CFLAGS="$framework_other_cflags" PERL_DIST_PATH="$PERL_BUILD_DIR" \
      LIBPERL_PATH="$PERL_BUILD_DIR" PERL_VERSION="$PERL_VERSION" \
      HEADER_SEARCH_PATHS="$PERL_BUILD_DIR" \
      OTHER_LDFLAGS="-L$PERL_BUILD_DIR -lperl" \
      $framework_debug_settings \
      ONLY_ACTIVE_ARCH=NO SUPPORTED_PLATFORMS="$IOS_PLATFORM" \
      TVOS_DEPLOYMENT_TARGET="$MIN_VERSION" TARGETED_DEVICE_FAMILY=3 \
      -configuration "${IOS_BUILD_CONFIGURATION:-Release}" -scheme "$framework_scheme"
    elif [ $PERL_APPLEWATCH -ne 0 ]; then
      case "$IOS_PLATFORM" in
        watchsimulator) framework_scheme="iphonesimulator" ;;
        watchos) framework_scheme="iphoneos" ;;
      esac
      xcodebuild -sdk "$IOS_PLATFORM" ARCHS="$ARCHS" VALID_ARCHS="$ARCHS" \
      OTHER_CFLAGS="$framework_other_cflags" PERL_DIST_PATH="$PERL_BUILD_DIR" \
      LIBPERL_PATH="$PERL_BUILD_DIR" PERL_VERSION="$PERL_VERSION" \
      HEADER_SEARCH_PATHS="$PERL_BUILD_DIR" \
      OTHER_LDFLAGS="-L$PERL_BUILD_DIR -lperl" \
      $framework_debug_settings \
      ONLY_ACTIVE_ARCH=NO SUPPORTED_PLATFORMS="$IOS_PLATFORM" \
      WATCHOS_DEPLOYMENT_TARGET="$MIN_VERSION" TARGETED_DEVICE_FAMILY=4 \
      -configuration "${IOS_BUILD_CONFIGURATION:-Release}" -scheme "$framework_scheme"
    else
      xcodebuild -sdk "$IOS_PLATFORM" ARCHS="$ARCHS" \
      OTHER_CFLAGS="$framework_other_cflags" PERL_DIST_PATH="$PERL_BUILD_DIR" \
      LIBPERL_PATH="$PERL_BUILD_DIR" PERL_VERSION="$PERL_VERSION" \
      IPHONEOS_DEPLOYMENT_TARGET="$MIN_VERSION" \
      $framework_debug_settings \
      ONLY_ACTIVE_ARCH=NO \
      -configuration "${IOS_BUILD_CONFIGURATION:-Release}" -scheme "$framework_scheme"
    fi
    check_exit_code
    popd
}

prepare_ios_module_source() {
    mkdir -p "$PERL_BUILD_DIR/ext/ios"
    # The host miniperl built by Configure; no external host Perl is needed.
    (cd "$PERL_BUILD_DIR" && ./miniperl -Ilib -MExtUtils::ParseXS -e \
      'ExtUtils::ParseXS::process_file(filename => $ARGV[0], output => $ARGV[1])' \
      "$IOS_FRAMEWORK_DIR/CPAN/ios.xs" "$PERL_BUILD_DIR/ext/ios/ios.m")
    check_exit_code
}

build_libffi() {
    pushd ./libffi-3.2.1
    LIBFFI_SCHEME="libffi-$IOS_TARGET"

    if ! xcodebuild -list -project libffi.xcodeproj | grep -q "^[[:space:]]*$LIBFFI_SCHEME$"; then
      echo "libffi scheme '$LIBFFI_SCHEME' not found in libffi.xcodeproj"
      echo "Available libffi schemes:"
      xcodebuild -list -project libffi.xcodeproj | sed -n '/Schemes:/,$p'
      exit 1
    fi

    xcodebuild -project libffi.xcodeproj -scheme "$LIBFFI_SCHEME" -sdk "$IOS_PLATFORM" \
      ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO
    check_exit_code
    popd
}

build_camelbones_framework() {
    pushd $CAMELBONES_FRAMEWORK_DIR
    build_libffi
    check_exit_code

    xcodebuild -sdk "$IOS_PLATFORM" ARCHS="$ARCHS" PERL_DIST_PATH="$PERL_BUILD_DIR" \
    LIBPERL_PATH="$PERL_BUILD_DIR" \
    PERL_VERSION="$PERL_VERSION" ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO \
    -scheme "$CAMELBONES_TARGET"
    check_exit_code
    popd
}

delete_installed_perl
build_perl

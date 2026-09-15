#!/usr/bin/env sh

############## CONFIG BEGIN ##############

# perl binaries
: "${PERL_ARCH:=arm64}"
: "${BITCODE:=0}"
: "${DEBUG:=0}"
: "${INSTALL_DIR:=local}"
: "${MIN_VERSION:=12.0}"
: "${PERL_APPLETV:=0}"
: "${PERL_APPLEWATCH:=0}"

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

if [ $PERL_APPLETV -ne 0 ]; then
  PLATFORM_TAG="appletv"
  DEVICE_SDK_PATH="$APPLETV_DEVICE_SDK_PATH"
  SIMULATOR_SDK_PATH="$APPLETV_SIMULATOR_SDK_PATH"
  PERL_PLATFORM_TAG="PERL_APPLETV"
elif [ $PERL_APPLEWATCH -ne 0 ]; then
  PLATFORM_TAG="watch"
  DEVICE_SDK_PATH="$WATCHOS_DEVICE_SDK_PATH"
  SIMULATOR_SDK_PATH="$WATCHOS_SIMULATOR_SDK_PATH"
  PERL_PLATFORM_TAG="PERL_APPLEWATCH"
else
  PLATFORM_TAG="iphone"
  DEVICE_SDK_PATH="$IOS_DEVICE_SDK_PATH"
  SIMULATOR_SDK_PATH="$IOS_SIMULATOR_SDK_PATH"
  PERL_PLATFORM_TAG="PERL_IOS"
  export PERL_IOS=1
fi

MIN_VERSION_TAG="-m""$PLATFORM_TAG""os-version-min=$MIN_VERSION"
WORKDIR=`pwd`
PREFIX="$WORKDIR/$INSTALL_DIR"
PERL_VERSION="$PERL_REVISION.$PERL_MAJOR_VERSION.$PERL_MINOR_VERSION"

: "${PERLBREW_SOURCE:=$PERLBREW_ROOT/build/perl-$PERL_VERSION}"
export PERLBREW_SOURCE

mkdir "$PREFIX"
mkdir "$PREFIX/lib"
mkdir "$PREFIX/include"

case "$PERL_ARCH" in
  x86_64)
    SIMULATOR_BUILD=1
    ;;
  i386)
    SIMULATOR_BUILD=1
    ;;
  arm64)
    SIMULATOR_BUILD=0
    ;;
  armv7)
    SIMULATOR_BUILD=0
    ;;
  armv7s)
    SIMULATOR_BUILD=0
    ;;
  armv7k)
    SIMULATOR_BUILD=0
    ;;
  *)
    echo "Unsupported architecture: $PERL_ARCH"
    exit 1
    ;;
esac

# depends on GnuMakefile and DEBUGGING
if [ $DEBUG -eq 1 ]; then
  OPTIMIZER="-O0 -g"
else
  OPTIMIZER="-Os -O3"
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
SIMULATOR_LINK_FLAGS="-DPERL_IOS $ARCH_FLAGS -L$PREFIX/lib -L$SIMULATOR_SDK_PATH/usr/lib"

DEVICE_BUILD_FLAGS="-DPERL_IOS -I$PREFIX/include -I$DEVICE_SDK_PATH/usr/include $ARCH_FLAGS $MIN_VERSION_TAG -isysroot $DEVICE_SDK_PATH $BITCODE_BUILD_FLAGS"
DEVICE_LINK_FLAGS="-DPERL_IOS $ARCH_FLAGS -L$PREFIX/include -L$DEVICE_SDK_PATH/usr/lib"

if [ $SIMULATOR_BUILD -ne 0 ]; then
  BUILD_FLAGS="$SIMULATOR_BUILD_FLAGS"
  LINK_FLAGS="$SIMULATOR_LINK_FLAGS"
  SDK_PATH="$SIMULATOR_SDK_PATH"
else
  BUILD_FLAGS="$DEVICE_BUILD_FLAGS"
  LINK_FLAGS="$DEVICE_LINK_FLAGS"
  SDK_PATH="$DEVICE_SDK_PATH"
fi

BUILD_FLAGS="$BUILD_FLAGS -D$PERL_PLATFORM_TAG"
LINK_FLAGS="$LINK_FLAGS -D$PERL_PLATFORM_TAG"

######################################################
# Build perl
######################################################

build_perl() {
  cd "$WORKDIR"

  if [ -d "$WORKDIR/ext" ]; then
    # Only unpack extension archives when they are actually present.
    if ls "$WORKDIR"/ext/*.tar.gz >/dev/null 2>&1; then
      for f in "$WORKDIR"/ext/*.tar.gz
      do
        echo "$f is"
        echo "Installing perl extension $f..."
        tar xvfz "$f" -C "perl-$PERL_VERSION/ext"
      done
    else
      echo "No extension archives found in $WORKDIR/ext"
    fi
  fi

  cd "perl-$PERL_VERSION"

  export SDKROOT="$SDK_PATH"
  export CC=/usr/bin/clang

  # do not strip if -g in ccflags
  if [ $DEBUG -eq 1 ]; then
    perl -0777 -i.bak.0 -pe "s|(\\$\\^O eq \'darwin\');|\(\1 && \\\$Config\{\"ccflags\"\} \!\~ /-g\\\s/);|" installperl
  fi

  # export min version
  if [ $PERL_APPLETV -ne 0 ]; then
    export APPLETV_DEPLOYMENT_TARGET="$MIN_VERSION"
  elif [ $PERL_APPLEWATCH -ne 0 ]; then
    export WATCHOS_DEPLOYMENT_TARGET="$MIN_VERSION"
  else
    export IPHONEOS_DEPLOYMENT_TARGET="$MIN_VERSION"
  fi

  ./Configure -des -Dusedevel \
    -Dtargethost=physical-device \
    -Dtargetrun=darwin-ios \
    -Dhostperl="$PERLBREW_SOURCE/miniperl" \
    -Dhostgenerate="$PERLBREW_SOURCE/generate_uudmap" \
    -Dcc=/usr/bin/clang \
    -Dccflags="$BUILD_FLAGS" \
    -Dldflags="$LINK_FLAGS" \
    -Dlibs='-lm -lc' \
    -Dprefix="$PREFIX"

  make depend
  check_exit_code

  make
  check_exit_code

  build_ios_framework

  mkdir -p $IOS_CPAN_EXT_DIR
  chmod -R +w $IOS_CPAN_EXT_DIR
  echo cp -Rv "$IOS_CPAN_DIR/." $IOS_CPAN_EXT_DIR/
  cp -Rv "$IOS_CPAN_DIR/." $IOS_CPAN_EXT_DIR/

  if [ $BUILD_CAMELBONES -eq 1 ]; then
      build_camelbones_framework
  fi

  mkdir -p $CAMELBONES_CPAN_DIR
  chmod -R +w $CAMELBONES_CPAN_DIR
  echo cp -R "$CAMELBONES_FRAMEWORK_DIR/CPAN/." $CAMELBONES_CPAN_DIR/
  cp -R "$CAMELBONES_FRAMEWORK_DIR/CPAN/." $CAMELBONES_CPAN_DIR/

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

  # generate dSYM file
  if [ $DEBUG -eq 1 ]; then
    echo "Generate libperl.dylib.dSYM..."
    pushd "$PREFIX/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/CORE"
    dsymutil libperl.dylib
    check_exit_code
    echo "$PREFIX/lib/perl5/$PERL_VERSION/darwin-thread-multi-2level/CORE/libperl.dylib.dSYM"
    popd
  fi

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
    echo "Failed to build perl for iOS"
    exit "$status"
  fi
}

build_ios_framework() {
    pushd $IOS_FRAMEWORK_DIR
    check_exit_code

    xcodebuild ARCHS="$ARCHS" PERL_DIST_PATH="$WORKDIR/perl-$PERL_VERSION" \
    LIBPERL_PATH="$WORKDIR/perl-$PERL_VERSION" \
    PERL_VERSION="$PERL_VERSION" ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO \
    -scheme "$IOS_TARGET"
    check_exit_code
    popd
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

    xcodebuild -project libffi.xcodeproj -scheme "$LIBFFI_SCHEME" \
      ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO
    check_exit_code
    popd
}

build_camelbones_framework() {
    pushd $CAMELBONES_FRAMEWORK_DIR
    build_libffi
    check_exit_code

    xcodebuild ARCHS="$ARCHS" PERL_DIST_PATH="$WORKDIR/perl-$PERL_VERSION" \
    LIBPERL_PATH="$WORKDIR/perl-$PERL_VERSION" \
    PERL_VERSION="$PERL_VERSION" ARCHS="$ARCHS" ONLY_ACTIVE_ARCH=NO \
    -scheme "$CAMELBONES_TARGET"
    check_exit_code
    popd
}

delete_installed_perl
build_perl

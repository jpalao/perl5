#!/bin/sh
#
# This file was produced by running the Configure script. It holds all the
# definitions figured out by Configure. Should you modify one of these values,
# do not forget to propagate your changes by running "Configure -der". You may
# instead choose to run each of the .SH files by yourself, or "Configure -S".
#

# Package name      : perl%PERL_REVISION%
# Source directory  : .
# Configuration time: Thu May 21 09:08:29 CEST 2020
# Configured by     : jose
# Target system     : darwin joses-mac.local %DARWIN_VERSION% darwin kernel version %DARWIN_VERSION%: thu jun 21 20:07:40 pdt 2018; root:xnu-3248.73.11~1release_x86_64 x86_64 

: Configure command line arguments.
config_arg0='./Configure'
config_args='-Duse64bitall -des -Dinstallstyle=lib/perl%PERL_REVISION% -Dlibpth=/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk/usr/lib /opt/local/lib -Dincpth=/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk/usr/include /opt/local/include -Dlocincpth=/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk/usr/include /opt/local/include -Dloclibpth=/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk/usr/lib /opt/local/lib -Dprefix=/opt/local -Dcc=/usr/bin/clang -Dman1dir=/opt/local/share/man/man1p -Dman1ext=1pm -Dman3dir=/opt/local/share/man/man3p -Dman3ext=3pm -Dscriptdir=/opt/local/bin -Dsitebin=/opt/local/libexec/perl%PERL_REVISION%.%PERL_MAJOR_VERSION%/sitebin -Dsiteman1dir=/opt/local/share/perl%PERL_REVISION%.%PERL_MAJOR_VERSION%/siteman/man1 -Dsiteman3dir=/opt/local/share/perl%PERL_REVISION%.%PERL_MAJOR_VERSION%/siteman/man3 -Dusemultiplicity=y -Duseshrplib -Dusethreads -Dvendorbin=/opt/local/libexec/perl%PERL_REVISION%.%PERL_MAJOR_VERSION% -Dvendorman1dir=/opt/local/share/perl%PERL_REVISION%.%PERL_MAJOR_VERSION%/man/man1 -Dvendorman3dir=/opt/local/share/perl%PERL_REVISION%.%PERL_MAJOR_VERSION%/man/man3 -Dvendorprefix=/opt/local -Accflags=-arch arm64 -DTARGET_OS_APPLETV -I/opt/local/include -I/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk/usr/include -arch arm64 -mappletvos-version-min=8.0 -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk  -DPERL_USE_SAFE_PUTENV -fno-common -fPIC -DPERL_DARWIN -DPERL_IOS -pipe -O0 -g -fno-strict-aliasing -fstack-protector-strong -Acppflags=-arch arm64 -DTARGET_OS_APPLETV -I/opt/local/include -I/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk/usr/include -arch arm64 -mappletvos-version-min=8.0 -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk  -DPERL_USE_SAFE_PUTENV -fno-common -fPIC -DPERL_DARWIN -DPERL_IOS -pipe -O0 -g -fno-strict-aliasing -fstack-protector-strong -Aldflags=-arch arm64 -DTARGET_OS_APPLETV -arch arm64 -L/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk/usr/lib  -Wl,-headerpad_max_install_names -Alddlflags=-arch arm64 -DTARGET_OS_APPLETV -arch arm64 -L/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk/usr/lib  -Wl,-headerpad_max_install_names -bundle -L/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk/usr/lib -L/opt/local/lib -Acccdlflags=-arch arm64 -mappletvos-version-min=8.0 -isysroot/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk'
config_argc=29
config_arg1='-Duse64bitall'
config_arg2='-des'
config_arg3='-Dinstallstyle=lib/perl%PERL_REVISION%'
config_arg4='-Dlibpth=/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk/usr/lib /opt/local/lib '
config_arg5='-Dincpth=/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk/usr/include /opt/local/include'
config_arg6='-Dlocincpth=/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk/usr/include /opt/local/include'
config_arg7='-Dloclibpth=/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk/usr/lib /opt/local/lib'
config_arg8='-Dprefix=/opt/local'
config_arg9='-Dcc=/usr/bin/clang'
config_arg10='-Dman1dir=/opt/local/share/man/man1p'
config_arg11='-Dman1ext=1pm'
config_arg12='-Dman3dir=/opt/local/share/man/man3p'
config_arg13='-Dman3ext=3pm'
config_arg14='-Dscriptdir=/opt/local/bin'
config_arg15='-Dsitebin=/opt/local/libexec/perl%PERL_REVISION%.%PERL_MAJOR_VERSION%/sitebin'
config_arg16='-Dsiteman1dir=/opt/local/share/perl%PERL_REVISION%.%PERL_MAJOR_VERSION%/siteman/man1'
config_arg17='-Dsiteman3dir=/opt/local/share/perl%PERL_REVISION%.%PERL_MAJOR_VERSION%/siteman/man3'
config_arg18='-Dusemultiplicity=y'
config_arg19='-Duseshrplib'
config_arg20='-Dusethreads'
config_arg21='-Dvendorbin=/opt/local/libexec/perl%PERL_REVISION%.%PERL_MAJOR_VERSION%'
config_arg22='-Dvendorman1dir=/opt/local/share/perl%PERL_REVISION%.%PERL_MAJOR_VERSION%/man/man1'
config_arg23='-Dvendorman3dir=/opt/local/share/perl%PERL_REVISION%.%PERL_MAJOR_VERSION%/man/man3'
config_arg24='-Dvendorprefix=/opt/local'
config_arg25='-Dccflags=-arch arm64 -DTARGET_OS_APPLETV -I/opt/local/include -I/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk/usr/include -arch arm64 -mappletvos-version-min=8.0 -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk  -DPERL_USE_SAFE_PUTENV -fno-common -fPIC -DPERL_DARWIN -DPERL_IOS -pipe -O0 -g -fno-strict-aliasing -fstack-protector-strong'
config_arg26='-Dcppflags=-arch arm64 -DTARGET_OS_APPLETV -I/opt/local/include -I/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk/usr/include -arch arm64 -mappletvos-version-min=8.0 -isysroot /Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk  -DPERL_USE_SAFE_PUTENV -fno-common -fPIC -DPERL_DARWIN -DPERL_IOS -pipe -O0 -g -fno-strict-aliasing -fstack-protector-strong'
config_arg27='-Aldflags=-arch arm64 -DTARGET_OS_APPLETV -arch arm64 -L/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk/usr/lib  -Wl,-headerpad_max_install_names'
config_arg28='-Alddlflags=-arch arm64 -DTARGET_OS_APPLETV -arch arm64 -L/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk/usr/lib  -Wl,-headerpad_max_install_names -bundle -L/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk/usr/lib -L/opt/local/lib'
config_arg29='-Acccdlflags=-arch arm64 -mappletvos-version-min=8.0 -isysroot/Applications/Xcode.app/Contents/Developer/Platforms/AppleTVOS.platform/Developer/SDKs/AppleTVOS.sdk'


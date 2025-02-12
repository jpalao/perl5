#!/usr/bin/perl

package CBCommon;

use Config;
use ExtUtils::Embed qw/ldopts/;

die "This code only works on macOS, iOS, apple tv and apple watch systems"
    if ( $^O !~ m/darwin/ );

=pod

=head1 cb_common.pl

This script builds ios.framework and associated perl XS extension.

The following ENV variables can be set to control its behavior.

=cut

=pod

=head2 PERL_INCLUDE_DIR

Absolute path to the directory containing EXTERN.h and libperl.dylib

=cut

our $PERL_INCLUDE_DIR = $ENV{'LIBPERL_PATH'};

=pod

=head2 PERL_LINK_FLAGS

The linker flags to be used in the build. Defaults to:

perl -MExtUtils::Embed -e'print ldopts()'

=cut

our $PERL_LINK_FLAGS = $ENV{'PERL_LINK_FLAGS'};

=pod

=head2 ARCHFLAGS

The compiler flags to be used in the build. Defaults to:

perl -MConfig -e'print $Config{'ccflags'}'

=cut

our $ARCHFLAGS = $ENV{'ARCHFLAGS'};

=pod

=head2 PERL_VERSION

The perl version that ios should link with. For example 5.35.9 

=cut

our $PERL_VERSION = $ENV{'PERL_VERSION'};

=pod

=head2 IOS_TARGET

The target of this build. One of:

=cut

=over

=item

iphoneos

=item

iphonesimulator

=item

appletvos

=item

appletvsimulator

=item

watchos

=item

watchsimulator

=back

Default is iphoneos

=cut

our $IOS_TARGET = $ENV{'IOS_TARGET'};

=pod

=head2 PERL_IOS_PREFIX

Absolute path to the parent dir of the perl-5.XX.XX source folder

=cut

our $PERL_IOS_PREFIX = $ENV{'PERL_IOS_PREFIX'};

=pod

=head2 IOS_MODULE_PATH

Path to the ios.framework project files 

=cut

our $IOS_MODULE_PATH = $ENV{'IOS_MODULE_PATH'};

=pod

=head2 IOS_VERSION

The verion of ios module to build

=cut

our $IOS_VERSION = $ENV{'IOS_VERSION'};

=pod

=head2 IOS_CPAN_DIR

Absolute path to ios XS module

=cut

our $IOS_CPAN_DIR = $ENV{'IOS_CPAN_DIR'};

=pod

=head2 ARCHS

Architectures for this build, defaults to arm64

=cut

our $ARCHS = $ENV{'ARCHS'};
if (!length $ARCHS) {
    $ARCHS = 'arm64';
}

=pod

=head2 IOS_BUILD_CONFIGURATION

Either 'Debug' or 'Release'

=cut

our $XCODE_BUILD_CONFIG = $ENV{'IOS_BUILD_CONFIGURATION'};

print "\$IOS_BUILD_CONFIGURATION: $IOS_BUILD_CONFIGURATION\n";
print "\$IOS_TARGET: $IOS_TARGET\n";

$XCODE_BUILD_CONFIG .= "-$IOS_TARGET";

print "\$XCODE_BUILD_CONFIG: $XCODE_BUILD_CONFIG\n";
print "\$IOS_CPAN_DIR: $IOS_CPAN_DIR\n";
###################################################################################

our $IOS_FRAMEWORK = 'ios.framework';

my $perl_link_flags = ldopts();
print "\$perl_link_flags: $perl_link_flags\n";
chomp $perl_link_flags;

if (!defined $ARCHFLAGS || !length $ARCHFLAGS) {
    $ARCHFLAGS = $Config{'ccflags'};
    chomp $ARCHFLAGS;
}

$ARCHFLAGS .= " $perl_link_flags -framework ios ";

$PERL_INCLUDE_DIR = $Config{archlib}. "/CORE"
    if (!defined $PERL_INCLUDE_DIR || !length $PERL_INCLUDE_DIR);

$ARCHFLAGS .= " -L$PERL_INCLUDE_DIR -I$PERL_INCLUDE_DIR -ObjC -lobjc ";

$XCODE_BUILD_CONFIG = "Release-iphoneos"
    if (!defined $XCODE_BUILD_CONFIG || !length $XCODE_BUILD_CONFIG);

my $iosPath = "$PERL_IOS_PREFIX/ios/Build/Products/$XCODE_BUILD_CONFIG";

our %opts = (
    VERSION           => $IOS_VERSION,
    CCFLAGS           => "$ARCHFLAGS -Wall",
    PREREQ_PM         => {},

    AUTHOR            => 'Sherm Pendley <sherm.pendley@gmail.com>',
    XSOPT             => "-typemap $PERL_IOS_PREFIX/perl-$PERL_VERSION/ext/ios/typemap",

    LIBS              => [ '-lobjc'],
    INC               => "-F$IOS_MODULE_PATH/Build/Products/$XCODE_BUILD_CONFIG",
    dynamic_lib       => {
                        'OTHERLDFLAGS' =>
                            "$ARCHFLAGS -framework Foundation " .
                            "-framework ios -F$IOS_MODULE_PATH/Build/Products/$XCODE_BUILD_CONFIG " .
                            "-Wl,-rpath,$iosPath"
                        },
);

1;

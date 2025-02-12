#import <ios/PerlImports.h>
#import <ios/PerlCtrl.h>
#import <ios/NativeMethods.h>

#ifdef GNUSTEP
#include <objc/objc.h>
#else
#if PERL_IOS
#import <objc/runtime.h>
#elif TARGET_OS_MAC
#import <objc/objc-runtime.h>
#endif
#endif

#import <XSUB.h>

MODULE = ios	PACKAGE = ios

PROTOTYPES: ENABLE

void
CBInit()
    CODE:
    NSAutoreleasePool *p = [[NSAutoreleasePool alloc] init];
    [[PerlCtrl alloc] initXS];

AV*
CBRunPerlCaptureStdout(json)
    const char* json;

SV*
CBRunPerl(json)
    const char* json;

SV*
CBYield(ti)
    double ti;


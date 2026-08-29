#import <ios/PerlImports.h>
#import <ios/PerlCtrl.h>
#import <ios/NativeMethods.h>
#import <ios/ios_make.h>

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

static int
iosRunMakeRecipe(const char *command, void *context)
{
    PERL_SET_CONTEXT(context);
    dTHX;
    dSP;
    int count;
    int status = 2;

    ENTER;
    SAVETMPS;
    PUSHMARK(SP);
    XPUSHs(sv_2mortal(newSVpv(command, 0)));
    PUTBACK;
    count = call_pv("ios::_run_make_recipe", G_SCALAR | G_EVAL);
    SPAGAIN;
    if (SvTRUE(ERRSV)) {
        warn_sv(ERRSV);
    } else if (count == 1) {
        status = POPi;
    }
    PUTBACK;
    FREETMPS;
    LEAVE;
    return status;
}

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

int
CBRunMake(...)
    PREINIT:
        int index;
        int make_argc;
        char **make_argv;
    CODE:
        make_argc = items + 2;
        Newxz(make_argv, make_argc + 1, char *);
        make_argv[0] = "bmake";
        make_argv[1] = "-r";
        for (index = 0; index < items; index++)
            make_argv[index + 2] = SvPV_nolen(ST(index));
        RETVAL = ios_make_run(make_argc, make_argv, iosRunMakeRecipe,
            (void *)aTHX);
        Safefree(make_argv);
    OUTPUT:
        RETVAL

SV*
CBYield(ti)
    double ti;


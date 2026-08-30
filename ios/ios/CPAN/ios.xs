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

AV*
CBRunMakeCapture(...)
    PREINIT:
        int index;
        int make_argc;
        char **make_argv;
        int status;
        int saved_stdout;
        int saved_stderr;
        FILE *capture;
        long output_length;
        char *output;
        AV *results;
    CODE:
        capture = tmpfile();
        if (capture == NULL)
            croak("Could not create make output capture: %s", strerror(errno));

        make_argc = items + 2;
        Newxz(make_argv, make_argc + 1, char *);
        make_argv[0] = "bmake";
        make_argv[1] = "-r";
        for (index = 0; index < items; index++)
            make_argv[index + 2] = SvPV_nolen(ST(index));

        PerlIO_flush(PerlIO_stdout());
        PerlIO_flush(PerlIO_stderr());
        fflush(stdout);
        fflush(stderr);
        saved_stdout = dup(STDOUT_FILENO);
        saved_stderr = dup(STDERR_FILENO);
        if (saved_stdout < 0 || saved_stderr < 0 ||
            dup2(fileno(capture), STDOUT_FILENO) < 0 ||
            dup2(fileno(capture), STDERR_FILENO) < 0) {
            if (saved_stdout >= 0)
                close(saved_stdout);
            if (saved_stderr >= 0)
                close(saved_stderr);
            Safefree(make_argv);
            fclose(capture);
            croak("Could not redirect make output: %s", strerror(errno));
        }

        status = ios_make_run(make_argc, make_argv, iosRunMakeRecipe,
            (void *)aTHX);
        Safefree(make_argv);
        PerlIO_flush(PerlIO_stdout());
        PerlIO_flush(PerlIO_stderr());
        fflush(stdout);
        fflush(stderr);
        dup2(saved_stdout, STDOUT_FILENO);
        dup2(saved_stderr, STDERR_FILENO);
        close(saved_stdout);
        close(saved_stderr);

        if (fseek(capture, 0, SEEK_END) != 0 ||
            (output_length = ftell(capture)) < 0 ||
            fseek(capture, 0, SEEK_SET) != 0) {
            fclose(capture);
            croak("Could not read make output capture: %s", strerror(errno));
        }
        Newx(output, output_length + 1, char);
        if (output_length > 0 &&
            fread(output, 1, output_length, capture) != (size_t)output_length) {
            Safefree(output);
            fclose(capture);
            croak("Could not read make output capture: %s", strerror(errno));
        }
        output[output_length] = '\0';
        fclose(capture);

        results = newAV();
        av_push(results, newSViv((status & 0xff) << 8));
        av_push(results, newSVpvn_utf8(output, output_length, 1));
        Safefree(output);
        RETVAL = results;
    OUTPUT:
        RETVAL

SV*
CBYield(ti)
    double ti;


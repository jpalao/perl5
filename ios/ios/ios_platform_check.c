#include "ios_platform_check.h"

#include <TargetConditionals.h>
#include <stdio.h>
#include <unistd.h>

int
ios_platform_check(void)
{
    int result = 0;

    printf("ios_platform_check: pointer_size=%zu pid=%ld\n",
        sizeof(void *), (long)getpid());
#if !TARGET_OS_IPHONE
    result = 1;
#elif !TARGET_OS_SIMULATOR && !defined(__aarch64__)
    result = 1;
#endif
    fflush(stdout);
    return result;
}

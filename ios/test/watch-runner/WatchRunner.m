#import "WatchRunner.h"
#import <ios/ios.h>
#include <stdlib.h>

int RunWatchPerlTests(void) {
    @autoreleasepool {
        static NSMutableDictionary *perlInstanceDictionary;
        NSError *error = nil;
        NSURL *groupContainer = [[NSFileManager defaultManager]
            containerURLForSecurityApplicationGroupIdentifier:@"group.net.pytm.perl.watchrunner"];
        if (groupContainer == nil) {
            NSLog(@"Watch runner cannot access its shared App Group container");
            return 255;
        }
        NSURL *documentsURL = [groupContainer URLByAppendingPathComponent:@"Documents"
                                                              isDirectory:YES];
        if (![[NSFileManager defaultManager] createDirectoryAtURL:documentsURL
                                      withIntermediateDirectories:YES
                                                       attributes:nil
                                                            error:&error]) {
            NSLog(@"Watch runner cannot create its Documents directory: %@",
                  error.localizedDescription);
            return 255;
        }
        NSString *documents = documentsURL.path;
        NSString *scriptPath = [documents stringByAppendingPathComponent:@"t/ios_harness"];
        NSString *workingDirectory = [scriptPath stringByDeletingLastPathComponent];
        NSString *statusPath = [documents stringByAppendingPathComponent:@"perl-tests.status"];
        __block int perlResult = 255;

        NSLog(@"Watch runner starting Perl script: %@", scriptPath);
        if (![[NSFileManager defaultManager] fileExistsAtPath:scriptPath]) {
            NSLog(@"Watch runner cannot find Perl test harness at %@", scriptPath);
        } else {
            setenv("PERL_APPLEWATCH", "1", 1);
            setenv("PERL_FOUNDATION_RUNNER", "1", 1);
            if (perlInstanceDictionary == nil) {
                perlInstanceDictionary = [[NSMutableDictionary alloc] initWithCapacity:128];
            }
            [PerlCtrl initPerlInstanceDictionary:perlInstanceDictionary];
            PerlCtrl *controller = [[PerlCtrl alloc] init];
            [controller initWithFileName:scriptPath
                         withAbsolutePwd:workingDirectory
                            withDebugger:0
                             withOptions:@[]
                           withArguments:nil
                                   error:&error
                              completion:^(int result) {
                perlResult = result;
            }];
        }

        if (error != nil && perlResult == 0) {
            perlResult = (int)error.code;
            if (perlResult == 0) {
                perlResult = 255;
            }
            NSLog(@"Watch runner Perl error: %@", error.localizedDescription);
        }

        NSError *statusError = nil;
        NSString *status = [NSString stringWithFormat:@"%d\n", perlResult];
        if (![status writeToFile:statusPath
                      atomically:YES
                        encoding:NSUTF8StringEncoding
                           error:&statusError]) {
            NSLog(@"Watch runner could not write test status: %@", statusError.localizedDescription);
            return 255;
        }

        NSLog(@"Watch runner Perl invocation returned: %d", perlResult);
        return perlResult;
    }
}

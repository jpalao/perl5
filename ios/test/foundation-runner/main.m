#import <Foundation/Foundation.h>
#import <ios/ios.h>

static NSString *RunnerArgument(NSArray *arguments, NSString *name, NSString *fallback) {
    NSUInteger index = [arguments indexOfObject:name];
    if (index != NSNotFound && index + 1 < arguments.count) {
        return [arguments objectAtIndex:index + 1];
    }
    return fallback;
}

static int RunPerlScript(NSString *scriptPath, NSString *outputPath, NSString *statusPath) {
    __block int normalizedResult = 255;
    @autoreleasepool {
        NSError *error = nil;
        NSURL *scriptURL = [NSURL fileURLWithPath:scriptPath];
        NSString *workingDirectory = [[scriptURL URLByDeletingLastPathComponent] path];
        __block int perlResult = 255;

        freopen([outputPath fileSystemRepresentation], "w", stdout);
        freopen([outputPath fileSystemRepresentation], "a", stderr);
        [PerlCtrl initPerlInstanceDictionary:[NSMutableDictionary dictionaryWithCapacity:128]];
        PerlCtrl *controller = [[PerlCtrl alloc] init];
        [controller initWithFileName:scriptPath
                     withAbsolutePwd:workingDirectory
                        withDebugger:0
                         withOptions:nil
                       withArguments:nil
                               error:&error
                          completion:^(int result) {
            perlResult = result;
        }];

        if (error != nil) {
            if (perlResult == 0) {
                perlResult = (int)error.code;
                if (perlResult == 0) {
                    perlResult = 255;
                }
            }
            fprintf(stderr, "%s\n", [[error localizedDescription] UTF8String]);
        }

        NSString *status = [NSString stringWithFormat:@"%d\n", perlResult];
        NSError *statusError = nil;
        [status writeToFile:statusPath
                 atomically:YES
                   encoding:NSUTF8StringEncoding
                      error:&statusError];
        if (statusError != nil) {
            fprintf(stderr, "%s\n", [[statusError localizedDescription] UTF8String]);
            perlResult = 255;
        }

        fflush(stdout);
        fflush(stderr);
        normalizedResult = perlResult == 0 ? 0 : 1;
    }
    return normalizedResult;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSArray *arguments = [[NSProcessInfo processInfo] arguments];
        NSString *documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                     NSUserDomainMask,
                                                                     YES) firstObject];
        NSString *fullTestScript = [documents stringByAppendingPathComponent:@"t/ios_harness"];
        NSString *scriptPath = RunnerArgument(arguments, @"--script", fullTestScript);
        NSString *defaultOutput = [documents stringByAppendingPathComponent:@"perl-tests.txt"];
        NSString *outputPath = RunnerArgument(arguments, @"--output", defaultOutput);
        NSString *defaultStatus = [documents stringByAppendingPathComponent:@"perl-tests.status"];
        NSString *statusPath = RunnerArgument(arguments, @"--status", defaultStatus);
        return RunPerlScript(scriptPath, outputPath, statusPath);
    }
}

#import <Foundation/Foundation.h>
#import <ios/ios.h>
#import <unistd.h>

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
        setenv("PERL_FOUNDATION_RUNNER", "1", 1);
        __block NSError *error = nil;
        NSURL *scriptURL = [NSURL fileURLWithPath:scriptPath];
        NSString *workingDirectory = [[scriptURL URLByDeletingLastPathComponent] path];
        __block int perlResult = 255;
        NSPipe *stdoutPipe = [NSPipe pipe];
        NSPipe *stderrPipe = [NSPipe pipe];
        NSMutableDictionary *perlDictionary = [[NSMutableDictionary alloc] initWithCapacity:128];
        [PerlCtrl initPerlInstanceDictionary:perlDictionary];
        int savedStdout = dup(STDOUT_FILENO);
        int savedStderr = dup(STDERR_FILENO);
        dispatch_group_t pipeReaders = dispatch_group_create();
        NSMutableString *capturedOutput = [[NSMutableString alloc] init];

        if (savedStdout < 0 || savedStderr < 0 ||
            dup2(stdoutPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO) < 0 ||
            dup2(stderrPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO) < 0) {
            NSLog(@"Could not redirect stdout/stderr: %s", strerror(errno));
            return 1;
        }
        close(stdoutPipe.fileHandleForWriting.fileDescriptor);
        close(stderrPipe.fileHandleForWriting.fileDescriptor);

        void (^drainPipe)(NSPipe *, int) = ^(NSPipe *pipe, int outputDescriptor) {
            dispatch_group_enter(pipeReaders);
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
                @autoreleasepool {
                    while (YES) {
                        NSData *data = [pipe.fileHandleForReading readDataOfLength:4096];
                        if (data.length == 0) {
                            break;
                        }
                        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
                        @synchronized (capturedOutput) {
                            [capturedOutput appendString:text];
                        }
                        write(outputDescriptor, data.bytes, data.length);
                    }
                }
                dispatch_group_leave(pipeReaders);
            });
        };

        drainPipe(stdoutPipe, savedStdout);
        drainPipe(stderrPipe, savedStderr);

        dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
            @autoreleasepool {
                PerlCtrl *controller = [[PerlCtrl alloc] init];
                [controller initWithFileName:scriptPath
                             withAbsolutePwd:workingDirectory
                                withDebugger:0
                                 withOptions:@[]
                               withArguments:nil
                                       error:&error
                                  completion:^(int result) {
                    fflush(stdout);
                    fflush(stderr);
                    perlResult = result;
                }];
            }
        });

        dup2(savedStdout, STDOUT_FILENO);
        dup2(savedStderr, STDERR_FILENO);

        dispatch_group_wait(pipeReaders, DISPATCH_TIME_FOREVER);
        close(savedStdout);
        close(savedStderr);

        NSError *outputError = nil;
        [capturedOutput writeToFile:outputPath atomically:YES encoding:NSUTF8StringEncoding error:&outputError];
        if (capturedOutput.length > 0) {
            NSLog(@"Perl output captured");
        }
        if (outputError != nil) {
            NSLog(@"Could not write Perl output: %@", outputError.localizedDescription);
        }

        if (error != nil) {
            if (perlResult == 0) {
                perlResult = (int)error.code;
                if (perlResult == 0) {
                    perlResult = 255;
                }
            }
            NSString *reason = error.userInfo[@"reason"];
            NSString *message = reason ?: error.localizedDescription;
            NSLog(@"Perl error: %@", message);
        }

        NSString *status = [NSString stringWithFormat:@"%d\n", perlResult];
        NSError *statusError = nil;
        [status writeToFile:statusPath
                 atomically:YES
                   encoding:NSUTF8StringEncoding
                      error:&statusError];
        if (statusError != nil) {
            NSLog(@"Could not write status: %@", statusError.localizedDescription);
            perlResult = 255;
        }
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

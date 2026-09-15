#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <ios/ios.h>

static NSString *RunnerArgument(NSArray *arguments, NSString *name, NSString *fallback) {
    NSUInteger index = [arguments indexOfObject:name];
    if (index != NSNotFound && index + 1 < arguments.count) {
        return [arguments objectAtIndex:index + 1];
    }
    return fallback;
}

static int RunPerlScript(NSString *scriptPath, NSString *statusPath) {
    __block int normalizedResult = 255;
    @autoreleasepool {
        setenv("PERL_FOUNDATION_RUNNER", "1", 1);
        __block NSError *error = nil;
        NSURL *scriptURL = [NSURL fileURLWithPath:scriptPath];
        NSString *workingDirectory = [[scriptURL URLByDeletingLastPathComponent] path];
        __block int perlResult = 255;
        NSMutableDictionary *perlDictionary = [[NSMutableDictionary alloc] initWithCapacity:128];
        [PerlCtrl initPerlInstanceDictionary:perlDictionary];

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
                    perlResult = result;
                }];
            }
        });

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

@interface FoundationRunnerDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, assign) BOOL testRunStarted;
@end

@implementation FoundationRunnerDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    return YES;
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    if (self.testRunStarted) {
        return;
    }
    self.testRunStarted = YES;
    NSArray *arguments = [[NSProcessInfo processInfo] arguments];
    NSString *documents = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                                 NSUserDomainMask,
                                                                 YES) firstObject];
    NSString *fullTestScript = [documents stringByAppendingPathComponent:@"t/ios_harness"];
    NSString *scriptPath = RunnerArgument(arguments, @"--script", fullTestScript);
    NSString *defaultStatus = [documents stringByAppendingPathComponent:@"perl-tests.status"];
    NSString *statusPath = RunnerArgument(arguments, @"--status", defaultStatus);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)),
                    dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        int result = RunPerlScript(scriptPath, statusPath);
        exit(result);
    });
}

@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        return UIApplicationMain(argc, (char **)argv, nil,
                                  NSStringFromClass([FoundationRunnerDelegate class]));
    }
}

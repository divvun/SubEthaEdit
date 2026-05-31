//  SEELSPServerLocator.m
//  SubEthaEditLSPHost

#import "SEELSPServerLocator.h"
#import <pwd.h>

@implementation SEELSPServerLocator

// The login shell sets up the real PATH (path_helper, brew shellenv, rustup, …);
// launchd starts this XPC service with a bare PATH, so ask the shell once.
+ (NSString *)TCM_loginShellPath {
    static NSString *cached = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        struct passwd *pw = getpwuid(getuid());
        NSString *shell = (pw && pw->pw_shell) ? @(pw->pw_shell) : @"/bin/zsh";
        NSTask *task = [[NSTask alloc] init];
        task.executableURL = [NSURL fileURLWithPath:shell];
        task.arguments = @[@"-lc", @"printf %s \"$PATH\""];
        NSPipe *out = [NSPipe pipe];
        task.standardOutput = out;
        task.standardError = [NSPipe pipe];
        NSError *error = nil;
        if ([task launchAndReturnError:&error]) {
            NSData *data = [[out fileHandleForReading] readDataToEndOfFile];
            [task waitUntilExit];
            if (task.terminationStatus == 0) {
                cached = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]
                          stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            }
        }
    });
    return cached;
}

+ (NSArray<NSString *> *)searchPaths {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    void (^add)(NSString *) = ^(NSString *p) {
        if (p.length > 0 && [p isAbsolutePath] && ![seen containsObject:p]) {
            [seen addObject:p];
            [paths addObject:p];
        }
    };
    for (NSString *p in [[self TCM_loginShellPath] componentsSeparatedByString:@":"]) {
        add(p);
    }
    NSString *home = NSHomeDirectory();
    NSArray<NSString *> *common = @[@"/opt/homebrew/bin", @"/usr/local/bin", @"/usr/bin", @"/bin",
                                    @"/opt/local/bin",
                                    [home stringByAppendingPathComponent:@".cargo/bin"],
                                    [home stringByAppendingPathComponent:@"go/bin"],
                                    [home stringByAppendingPathComponent:@".local/bin"]];
    for (NSString *p in common) {
        add(p);
    }
    return paths;
}

+ (NSString *)resolvedPathForCommand:(NSString *)command {
    if (command.length == 0) {
        return nil;
    }
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([command isAbsolutePath]) {
        return [fm isExecutableFileAtPath:command] ? command : nil;
    }
    for (NSString *dir in [self searchPaths]) {
        NSString *candidate = [dir stringByAppendingPathComponent:command];
        BOOL isDirectory = NO;
        if ([fm fileExistsAtPath:candidate isDirectory:&isDirectory] && !isDirectory
                && [fm isExecutableFileAtPath:candidate]) {
            return candidate;
        }
    }
    return nil;
}

@end

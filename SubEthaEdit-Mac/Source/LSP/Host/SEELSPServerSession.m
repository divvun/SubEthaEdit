//  SEELSPServerSession.m
//  SubEthaEditLSPHost

#import "SEELSPServerSession.h"
#import "SEELSPChildProcess.h"

#import <math.h>

@implementation SEELSPServerSession {
    NSURL *I_executableURL;
    NSArray<NSString *> *I_arguments;
    NSDictionary<NSString *, NSString *> *I_environment;
    NSDictionary *I_initializeParams;

    dispatch_queue_t I_queue;
    SEELSPChildProcess *I_child;
    SEELSPServerState I_state;
    BOOL I_intentionalShutdown;
    NSUInteger I_consecutiveCrashes;
    NSMutableArray<NSNumber *> *I_recentCrashTimes;
}

- (instancetype)initWithExecutableURL:(NSURL *)executableURL
        arguments:(NSArray<NSString *> *)arguments
        environment:(NSDictionary<NSString *, NSString *> *)environment
        initializeParams:(NSDictionary *)initializeParams {
    self = [super init];
    if (self) {
        I_executableURL = executableURL;
        I_arguments = [arguments copy] ?: @[];
        I_environment = [environment copy];
        I_initializeParams = [initializeParams copy] ?: @{};
        I_queue = dispatch_queue_create("de.codingmonkeys.SubEthaEdit.lsp.session", DISPATCH_QUEUE_SERIAL);
        I_recentCrashTimes = [NSMutableArray array];
        I_state = SEELSPServerStateStopped;

        _initializeTimeout = 30.0;
        _restartBackoffBase = 1.0;
        _restartBackoffCap = 30.0;
        _maxRestartsPerWindow = 5;
        _restartWindow = 60.0;
    }
    return self;
}

- (SEELSPServerState)state {
    return I_state;
}

#pragma mark - Lifecycle

- (void)start {
    dispatch_async(I_queue, ^{ [self TCM_launch]; });
}

- (void)TCM_launch {
    [self TCM_setState:SEELSPServerStateLaunching];

    SEELSPChildProcess *child = [[SEELSPChildProcess alloc] initWithExecutableURL:I_executableURL
                                                                        arguments:I_arguments
                                                                      environment:I_environment];
    __weak typeof(self) weakSelf = self;
    dispatch_queue_t queue = I_queue;
    child.notificationHandler = ^(NSString *method, id params) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf.notificationHandler) { strongSelf.notificationHandler(method, params); }
    };
    child.serverRequestHandler = ^(id requestID, NSString *method, id params, void (^respond)(id, id)) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf.serverRequestHandler) {
            strongSelf.serverRequestHandler(requestID, method, params, respond);
        } else {
            respond(nil, @{@"code": @(-32601), @"message": @"Method not found"});
        }
    };
    child.stderrHandler = ^(NSString *text) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf.stderrHandler) { strongSelf.stderrHandler(text); }
    };
    child.terminationHandler = ^(int status) {
        dispatch_async(queue, ^{ [weakSelf TCM_childDidTerminate]; });
    };
    I_child = child;

    [self TCM_setState:SEELSPServerStateInitializing];
    // On handshake error the child terminates itself, so TCM_childDidTerminate drives the restart.
    [child launchAndInitializeWithParams:I_initializeParams timeout:self.initializeTimeout reply:^(NSDictionary *capabilities, NSError *error) {
        dispatch_async(queue, ^{
            if (!error) { [weakSelf TCM_didReachRunning]; }
        });
    }];
}

- (void)TCM_didReachRunning {
    if (I_state == SEELSPServerStateInitializing) {
        I_consecutiveCrashes = 0;
        [I_recentCrashTimes removeAllObjects];
        [self TCM_setState:SEELSPServerStateRunning];
    }
}

- (void)TCM_childDidTerminate {
    if (I_intentionalShutdown || I_state == SEELSPServerStateShuttingDown) {
        [self TCM_setState:SEELSPServerStateStopped];
    } else {
        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        [I_recentCrashTimes addObject:@(now)];
        NSTimeInterval cutoff = now - self.restartWindow;
        while (I_recentCrashTimes.count > 0 && [I_recentCrashTimes.firstObject doubleValue] < cutoff) {
            [I_recentCrashTimes removeObjectAtIndex:0];
        }
        I_consecutiveCrashes++;

        [self TCM_setState:SEELSPServerStateCrashed];
        if (I_recentCrashTimes.count > self.maxRestartsPerWindow) {
            // Circuit breaker tripped: stay Crashed, no further restarts.
        } else {
            NSTimeInterval backoff = MIN(self.restartBackoffCap, self.restartBackoffBase * pow(2.0, (double)(I_consecutiveCrashes - 1)));
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(backoff * NSEC_PER_SEC)), I_queue, ^{
                typeof(self) strongSelf = weakSelf;
                if (strongSelf && !strongSelf->I_intentionalShutdown) {
                    [strongSelf TCM_launch];
                }
            });
        }
    }
}

- (void)shutdown {
    dispatch_async(I_queue, ^{
        if (self->I_intentionalShutdown || self->I_state == SEELSPServerStateStopped) {
            return;
        }
        self->I_intentionalShutdown = YES;
        [self TCM_setState:SEELSPServerStateShuttingDown];

        SEELSPChildProcess *child = self->I_child;
        if (child.isRunning) {
            [child sendRequestMethod:@"shutdown" params:nil reply:^(id result, id errorObject) {
                [child sendNotificationMethod:@"exit" params:nil];
                [child terminate];
            }];
            __weak typeof(self) weakSelf = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), I_queue, ^{
                typeof(self) strongSelf = weakSelf;
                [strongSelf->I_child terminate];
            });
        } else {
            [self TCM_setState:SEELSPServerStateStopped];
        }
    });
}

#pragma mark - Routing

- (void)sendRequestMethod:(NSString *)method params:(id)params reply:(void (^)(id, id))reply {
    dispatch_async(I_queue, ^{
        if (self->I_child) {
            [self->I_child sendRequestMethod:method params:params reply:reply];
        } else {
            reply(nil, @{@"code": @(-32603), @"message": @"Server is not running"});
        }
    });
}

- (void)sendNotificationMethod:(NSString *)method params:(id)params {
    dispatch_async(I_queue, ^{
        [self->I_child sendNotificationMethod:method params:params];
    });
}

#pragma mark - State

- (void)TCM_setState:(SEELSPServerState)state {
    if (I_state != state) {
        I_state = state;
        if (self.stateChangeHandler) {
            self.stateChangeHandler(state);
        }
    }
}

@end

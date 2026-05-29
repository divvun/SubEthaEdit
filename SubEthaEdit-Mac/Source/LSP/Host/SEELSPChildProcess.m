//  SEELSPChildProcess.m
//  SubEthaEditLSPHost

#import "SEELSPChildProcess.h"
#import "SEELSPMessageReader.h"
#import "SEELSPMessageWriter.h"
#import "SEELSPRPCCoordinator.h"

#import <fcntl.h>
#import <unistd.h>

static NSInteger const SEELSPChildProcessTerminatedErrorCode = -32099;
static NSInteger const SEELSPJSONRPCMethodNotFound = -32601;

static NSString * const SEELSPChildProcessErrorDomain = @"SEELSPChildProcessErrorDomain";
typedef NS_ENUM(NSInteger, SEELSPChildProcessErrorCode) {
    SEELSPChildProcessInitializeFailed = 1,
    SEELSPChildProcessInitializeTimedOut = 2,
};

@implementation SEELSPChildProcess {
    NSArray<NSString *> *I_arguments;
    NSDictionary<NSString *, NSString *> *I_environment;

    NSTask *I_task;
    NSPipe *I_stdinPipe;
    NSPipe *I_stdoutPipe;
    NSPipe *I_stderrPipe;
    int I_stdinFD;
    dispatch_source_t I_stdoutSource;
    dispatch_source_t I_stderrSource;

    dispatch_queue_t I_queue;
    SEELSPMessageReader *I_reader;
    SEELSPRPCCoordinator *I_coordinator;
    BOOL I_running;
    BOOL I_didTerminate;
}

- (instancetype)initWithExecutableURL:(NSURL *)executableURL
        arguments:(NSArray<NSString *> *)arguments
        environment:(NSDictionary<NSString *, NSString *> *)environment {
    self = [super init];
    if (self) {
        _executableURL = executableURL;
        I_arguments = [arguments copy] ?: @[];
        I_environment = [environment copy];
        I_stdinFD = -1;
        I_queue = dispatch_queue_create("de.codingmonkeys.SubEthaEdit.lsp.child", DISPATCH_QUEUE_SERIAL);
        I_reader = [[SEELSPMessageReader alloc] init];
        I_coordinator = [[SEELSPRPCCoordinator alloc] init];
        [self TCM_wireEngine];
    }
    return self;
}

- (void)dealloc {
    if (I_stdoutSource) { dispatch_source_cancel(I_stdoutSource); }
    if (I_stderrSource) { dispatch_source_cancel(I_stderrSource); }
}

- (BOOL)isRunning {
    return I_running;
}

#pragma mark - Engine wiring

- (void)TCM_wireEngine {
    __weak typeof(self) weakSelf = self;

    I_reader.messageHandler = ^(NSData *jsonBody) {
        typeof(self) strongSelf = weakSelf;
        id object = [NSJSONSerialization JSONObjectWithData:jsonBody options:0 error:NULL];
        if (strongSelf && object) {
            [strongSelf->I_coordinator handleIncomingObject:object];
        }
    };
    I_reader.errorHandler = ^(NSError *error) {
        [weakSelf terminate];
    };

    I_coordinator.responseSender = ^(NSDictionary *responseObject) {
        [weakSelf TCM_sendObjectOnQueue:responseObject];
    };
    I_coordinator.notificationHandler = ^(NSString *method, id params) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf && strongSelf.notificationHandler) {
            strongSelf.notificationHandler(method, params);
        }
    };
    I_coordinator.serverRequestHandler = ^(id requestID, NSString *method, id params, void (^respond)(id, id)) {
        typeof(self) strongSelf = weakSelf;
        if (strongSelf && strongSelf.serverRequestHandler) {
            strongSelf.serverRequestHandler(requestID, method, params, respond);
        } else {
            respond(nil, @{@"code": @(SEELSPJSONRPCMethodNotFound), @"message": @"Method not found"});
        }
    };
}

#pragma mark - Launch

- (BOOL)launchAndReturnError:(NSError **)error {
    NSTask *task = [[NSTask alloc] init];
    task.executableURL = self.executableURL;
    task.arguments = I_arguments;
    if (I_environment) {
        task.environment = I_environment;
    }

    I_stdinPipe = [NSPipe pipe];
    I_stdoutPipe = [NSPipe pipe];
    I_stderrPipe = [NSPipe pipe];
    task.standardInput = I_stdinPipe;
    task.standardOutput = I_stdoutPipe;
    task.standardError = I_stderrPipe;

    __weak typeof(self) weakSelf = self;
    task.terminationHandler = ^(NSTask *terminatedTask) {
        [weakSelf TCM_handleTerminationWithStatus:terminatedTask.terminationStatus];
    };

    BOOL launched = [task launchAndReturnError:error];
    if (launched) {
        I_task = task;
        I_running = YES;

        // Writing to a dead child's stdin must return EPIPE rather than raise SIGPIPE.
        I_stdinFD = I_stdinPipe.fileHandleForWriting.fileDescriptor;
        int one = 1;
        fcntl(I_stdinFD, F_SETNOSIGPIPE, &one);

        I_stdoutSource = [self TCM_makeReadSourceForFD:I_stdoutPipe.fileHandleForReading.fileDescriptor
                                              consumer:^(NSData *chunk) {
            typeof(self) strongSelf = weakSelf;
            if (strongSelf) { [strongSelf->I_reader appendData:chunk]; }
        }];
        I_stderrSource = [self TCM_makeReadSourceForFD:I_stderrPipe.fileHandleForReading.fileDescriptor
                                              consumer:^(NSData *chunk) {
            typeof(self) strongSelf = weakSelf;
            if (strongSelf && strongSelf.stderrHandler) {
                NSString *text = [[NSString alloc] initWithData:chunk encoding:NSUTF8StringEncoding];
                if (text) { strongSelf.stderrHandler(text); }
            }
        }];
    }
    return launched;
}

// dup the read end so the dispatch source owns its descriptor and never double-closes the
// NSPipe's fd.
- (dispatch_source_t)TCM_makeReadSourceForFD:(int)fd consumer:(void (^)(NSData *chunk))consumer {
    int dupFD = dup(fd);
    dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_READ, dupFD, 0, I_queue);
    __weak typeof(self) weakSelf = self;
    dispatch_source_set_event_handler(source, ^{
        uint8_t buffer[8192];
        ssize_t count = read(dupFD, buffer, sizeof(buffer));
        if (count > 0) {
            consumer([NSData dataWithBytes:buffer length:count]);
        } else if (count == 0) {
            [weakSelf TCM_handleStreamEnd];
        } else if (errno != EAGAIN && errno != EINTR) {
            [weakSelf TCM_handleStreamEnd];
        }
    });
    dispatch_source_set_cancel_handler(source, ^{
        close(dupFD);
    });
    dispatch_resume(source);
    return source;
}

#pragma mark - Initialize handshake

- (void)launchAndInitializeWithParams:(NSDictionary *)initializeParams
        timeout:(NSTimeInterval)timeout
        reply:(void (^)(NSDictionary *, NSError *))reply {
    NSError *launchError = nil;
    BOOL launched = [self launchAndReturnError:&launchError];
    if (!launched) {
        reply(nil, launchError);
    } else {
        __weak typeof(self) weakSelf = self;
        __block BOOL replied = NO;

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(timeout * NSEC_PER_SEC)), I_queue, ^{
            if (!replied) {
                replied = YES;
                [weakSelf terminate];
                reply(nil, [SEELSPChildProcess TCM_errorWithCode:SEELSPChildProcessInitializeTimedOut
                                                         message:@"Language server did not answer initialize in time"]);
            }
        });

        [self sendRequestMethod:@"initialize" params:initializeParams reply:^(id result, id errorObject) {
            if (!replied) {
                replied = YES;
                typeof(self) strongSelf = weakSelf;
                if (errorObject) {
                    [strongSelf terminate];
                    reply(nil, [SEELSPChildProcess TCM_errorWithCode:SEELSPChildProcessInitializeFailed
                                                             message:[SEELSPChildProcess TCM_messageFromErrorObject:errorObject]]);
                } else {
                    [strongSelf sendNotificationMethod:@"initialized" params:@{}];
                    NSDictionary *capabilities = [result isKindOfClass:[NSDictionary class]] ? result[@"capabilities"] : nil;
                    reply(capabilities ?: @{}, nil);
                }
            }
        }];
    }
}

+ (NSError *)TCM_errorWithCode:(SEELSPChildProcessErrorCode)code message:(NSString *)message {
    return [NSError errorWithDomain:SEELSPChildProcessErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message ?: @"LSP error"}];
}

+ (NSString *)TCM_messageFromErrorObject:(id)errorObject {
    NSString *message = nil;
    if ([errorObject isKindOfClass:[NSDictionary class]]) {
        message = errorObject[@"message"];
    }
    return message ?: @"initialize failed";
}

#pragma mark - Sending

- (void)sendRequestMethod:(NSString *)method params:(id)params reply:(void (^)(id, id))reply {
    dispatch_async(I_queue, ^{
        NSDictionary *object = [self->I_coordinator requestObjectForMethod:method params:params reply:reply];
        [self TCM_sendObjectOnQueue:object];
    });
}

- (void)sendNotificationMethod:(NSString *)method params:(id)params {
    dispatch_async(I_queue, ^{
        NSDictionary *object = [self->I_coordinator notificationObjectForMethod:method params:params];
        [self TCM_sendObjectOnQueue:object];
    });
}

- (void)TCM_sendObjectOnQueue:(NSDictionary *)object {
    NSData *framed = [SEELSPMessageWriter framedDataForJSONObject:object error:NULL];
    if (framed && I_stdinFD >= 0) {
        const uint8_t *bytes = framed.bytes;
        size_t total = framed.length;
        size_t written = 0;
        while (written < total) {
            ssize_t n = write(I_stdinFD, bytes + written, total - written);
            if (n > 0) {
                written += (size_t)n;
            } else if (n == -1 && errno == EINTR) {
                continue;
            } else {
                break;
            }
        }
    }
}

#pragma mark - Termination

- (void)terminate {
    dispatch_async(I_queue, ^{
        if (self->I_running && [self->I_task isRunning]) {
            [self->I_task terminate];
        }
    });
}

- (void)TCM_handleStreamEnd {
}

- (void)TCM_handleTerminationWithStatus:(int)status {
    dispatch_async(I_queue, ^{
        if (!self->I_didTerminate) {
            self->I_didTerminate = YES;
            self->I_running = NO;

            if (self->I_stdoutSource) { dispatch_source_cancel(self->I_stdoutSource); self->I_stdoutSource = nil; }
            if (self->I_stderrSource) { dispatch_source_cancel(self->I_stderrSource); self->I_stderrSource = nil; }
            [self->I_stdinPipe.fileHandleForWriting closeFile];
            self->I_stdinFD = -1;

            NSDictionary *errorObject = @{@"code": @(SEELSPChildProcessTerminatedErrorCode),
                                          @"message": @"Language server terminated"};
            [self->I_coordinator failAllPendingWithErrorObject:errorObject];

            if (self.terminationHandler) {
                self.terminationHandler(status);
            }
        }
    });
}

@end

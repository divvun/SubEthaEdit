//  SEELSPChildProcess.h
//  SubEthaEditLSPHost
//
//  One launched language server: an NSTask with stdin/stdout/stderr pipes, a stdout reader
//  feeding the LSP framing/JSON-RPC engine, and outbound framing on stdin. Transport-agnostic
//  and XPC-independent so it can be exercised directly (e.g. against /bin/cat) without the
//  service. Crash/restart policy lives a layer up; this object models one process lifetime.
//
//  Thread model: all I/O and all handler callbacks run on one private serial queue (the same
//  queue that reads stdout), so the JSON-RPC coordinator state is never touched concurrently.
//  Public send methods may be called from any thread and hop onto that queue.

#import <Foundation/Foundation.h>

@interface SEELSPChildProcess : NSObject

- (instancetype)initWithExecutableURL:(NSURL *)executableURL
        arguments:(NSArray<NSString *> *)arguments
        environment:(NSDictionary<NSString *, NSString *> *)environment;

@property (nonatomic, readonly) NSURL *executableURL;
@property (nonatomic, readonly, getter=isRunning) BOOL running;

// Set before -launchAndReturnError:. Invoked on the private serial queue.
@property (nonatomic, copy) void (^notificationHandler)(NSString *method, id params);
@property (nonatomic, copy) void (^serverRequestHandler)(id requestID, NSString *method, id params, void (^respond)(id result, id errorObject));
@property (nonatomic, copy) void (^stderrHandler)(NSString *text);
@property (nonatomic, copy) void (^terminationHandler)(int terminationStatus);

- (BOOL)launchAndReturnError:(NSError **)error;

// Launch, then perform the LSP initialize/initialized handshake: send `initialize` with the
// given params, and on success send the `initialized` notification. reply is invoked once on
// the serial queue with the server's capabilities (the `initialize` result's "capabilities"
// object) on success, or an error if the process failed to launch, `initialize` returned an
// error, or no response arrived within timeout. On any failure the process is terminated.
- (void)launchAndInitializeWithParams:(NSDictionary *)initializeParams
        timeout:(NSTimeInterval)timeout
        reply:(void (^)(NSDictionary *capabilities, NSError *error))reply;

// reply is invoked once with exactly one of (result, errorObject) non-nil, or (nil, errorObject)
// if the process dies before a response arrives.
- (void)sendRequestMethod:(NSString *)method params:(id)params reply:(void (^)(id result, id errorObject))reply;
- (void)sendNotificationMethod:(NSString *)method params:(id)params;

- (void)terminate;

@end

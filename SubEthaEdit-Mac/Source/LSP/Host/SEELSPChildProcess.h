//  SEELSPChildProcess.h
//  SubEthaEditLSPHost

#import <Foundation/Foundation.h>

@interface SEELSPChildProcess : NSObject

- (instancetype)initWithExecutableURL:(NSURL *)executableURL
        arguments:(NSArray<NSString *> *)arguments
        environment:(NSDictionary<NSString *, NSString *> *)environment;

@property (nonatomic, readonly) NSURL *executableURL;
@property (nonatomic, readonly, getter=isRunning) BOOL running;

// Handlers are invoked on the private serial queue and must be set before launching.
@property (nonatomic, copy) void (^notificationHandler)(NSString *method, id params);
@property (nonatomic, copy) void (^serverRequestHandler)(id requestID, NSString *method, id params, void (^respond)(id result, id errorObject));
@property (nonatomic, copy) void (^stderrHandler)(NSString *text);
@property (nonatomic, copy) void (^terminationHandler)(int terminationStatus);

- (BOOL)launchAndReturnError:(NSError **)error;

- (void)launchAndInitializeWithParams:(NSDictionary *)initializeParams
        timeout:(NSTimeInterval)timeout
        reply:(void (^)(NSDictionary *capabilities, NSError *error))reply;

- (void)sendRequestMethod:(NSString *)method params:(id)params reply:(void (^)(id result, id errorObject))reply;
- (void)sendNotificationMethod:(NSString *)method params:(id)params;

- (void)terminate;

@end

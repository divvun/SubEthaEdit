//  SEELSPClientProtocol.h
//  SubEthaEdit

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SEELSPServerState) {
    SEELSPServerStateLaunching = 0,
    SEELSPServerStateInitializing,
    SEELSPServerStateRunning,
    SEELSPServerStateShuttingDown,
    SEELSPServerStateStopped,
    SEELSPServerStateCrashed,
};

@protocol SEELSPClientProtocol <NSObject>

- (void)server:(NSString *)serverInstanceID
        didReceiveNotificationMethod:(NSString *)method
        params:(NSDictionary *)params;

- (void)server:(NSString *)serverInstanceID
        didReceiveServerRequestMethod:(NSString *)method
        params:(NSDictionary *)params
        reply:(void (^)(id result, NSDictionary *errorObject))reply;

- (void)server:(NSString *)serverInstanceID didChangeState:(SEELSPServerState)state;
- (void)server:(NSString *)serverInstanceID didEmitStderr:(NSString *)logLine;
- (void)server:(NSString *)serverInstanceID didTerminateWithStatus:(int)status reason:(NSInteger)reason;

@end

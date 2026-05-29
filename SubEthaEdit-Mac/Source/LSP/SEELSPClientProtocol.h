//  SEELSPClientProtocol.h
//  SubEthaEdit
//
//  The app-side object the LSP host XPC service calls back into: server→client
//  pushes (diagnostics and other notifications, server-initiated requests, lifecycle
//  state). Implemented in the app, set as the connection's exportedObject; reached by
//  the service via the connection's remoteObjectProxy.

#import <Foundation/Foundation.h>

// Lifecycle state of a hosted language server, pushed to the app via -server:didChangeState:.
typedef NS_ENUM(NSInteger, SEELSPServerState) {
    SEELSPServerStateLaunching = 0,
    SEELSPServerStateInitializing,
    SEELSPServerStateRunning,
    SEELSPServerStateShuttingDown,
    SEELSPServerStateStopped,
    SEELSPServerStateCrashed,
};

@protocol SEELSPClientProtocol <NSObject>

// A server→client notification (e.g. textDocument/publishDiagnostics).
- (void)server:(NSString *)serverInstanceID
        didReceiveNotificationMethod:(NSString *)method
        params:(NSDictionary *)params;

// A server→client request. The app must call reply exactly once so the service can
// write the JSON-RPC response back to the child: (result, nil) or (nil, errorObject).
- (void)server:(NSString *)serverInstanceID
        didReceiveServerRequestMethod:(NSString *)method
        params:(NSDictionary *)params
        reply:(void (^)(NSDictionary *result, NSDictionary *errorObject))reply;

- (void)server:(NSString *)serverInstanceID didChangeState:(SEELSPServerState)state;
- (void)server:(NSString *)serverInstanceID didEmitStderr:(NSString *)logLine;
- (void)server:(NSString *)serverInstanceID didTerminateWithStatus:(int)status reason:(NSInteger)reason;

@end

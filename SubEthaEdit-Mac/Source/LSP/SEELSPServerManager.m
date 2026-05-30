//  SEELSPServerManager.m
//  SubEthaEdit

#import "SEELSPServerManager.h"
#import "SEELSPHostProtocol.h"
#import "SEELSPClientProtocol.h"
#import "SEELSPController.h"
#import "SEELSPXPCInterface.h"
#import "SEEScopedBookmarkManager.h"
#import "NSOperationQueue+TCMAdditions.h"

static NSInteger const SEELSPConnectionFailedErrorCode = -32603;

@interface SEELSPServerManager () <SEELSPClientProtocol>
@end

@implementation SEELSPServerManager {
    NSXPCConnection *I_connection;
    NSMapTable<NSString *, SEELSPController *> *I_observersByID;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        I_observersByID = [NSMapTable strongToWeakObjectsMapTable];
    }
    return self;
}

- (void)registerObserver:(SEELSPController *)observer forServerInstanceID:(NSString *)serverInstanceID {
    @synchronized (I_observersByID) {
        [I_observersByID setObject:observer forKey:serverInstanceID];
    }
}

- (void)unregisterServerInstanceID:(NSString *)serverInstanceID {
    @synchronized (I_observersByID) {
        [I_observersByID removeObjectForKey:serverInstanceID];
    }
}

- (SEELSPController *)TCM_observerForID:(NSString *)serverInstanceID {
    @synchronized (I_observersByID) {
        return [I_observersByID objectForKey:serverInstanceID];
    }
}

+ (instancetype)sharedManager {
    static SEELSPServerManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[self alloc] init];
    });
    return manager;
}

+ (NSData *)bookmarkForExecutableURL:(NSURL *)url error:(NSError **)error {
    return [SEEScopedBookmarkManager securityScopedBookmarkDataForURL:url error:error];
}

#pragma mark - Connection

// The embedded service's bundle id is the app's id plus ".LSPHost"; deriving it keeps the
// FULL / App Store / Dev build styles working without a hardcoded name.
- (NSString *)TCM_serviceName {
    return [[[NSBundle mainBundle] bundleIdentifier] stringByAppendingString:@".LSPHost"];
}

- (NSXPCConnection *)TCM_connection {
    if (!I_connection) {
        NSXPCConnection *connection = [[NSXPCConnection alloc] initWithServiceName:[self TCM_serviceName]];
        connection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SEELSPHostProtocol)];
        connection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SEELSPClientProtocol)];
        connection.exportedObject = self;
        SEELSPApplyJSONWhitelist(connection.remoteObjectInterface, connection.exportedInterface);

        __weak typeof(self) weakSelf = self;
        connection.invalidationHandler = ^{ [weakSelf TCM_dropConnection]; };
        connection.interruptionHandler = ^{ [weakSelf TCM_dropConnection]; };

        [connection resume];
        I_connection = connection;
    }
    return I_connection;
}

- (void)TCM_dropConnection {
    [NSOperationQueue TCM_performBlockOnMainQueue:^{
        self->I_connection = nil;
    } afterDelay:0];
}

- (id<SEELSPHostProtocol>)TCM_hostProxyWithReplyOnError:(void (^)(NSError *error))errorHandler {
    return [[self TCM_connection] remoteObjectProxyWithErrorHandler:^(NSError *error) {
        [NSOperationQueue TCM_performBlockOnMainQueue:^{ errorHandler(error); } afterDelay:0];
    }];
}

- (NSDictionary *)TCM_errorObjectFromError:(NSError *)error {
    return @{@"code": @(SEELSPConnectionFailedErrorCode), @"message": error.localizedDescription ?: @"XPC connection failed"};
}

#pragma mark - Public API

- (void)pingWithReply:(void (^)(NSString *, NSError *))reply {
    id<SEELSPHostProtocol> proxy = [self TCM_hostProxyWithReplyOnError:^(NSError *error) { reply(nil, error); }];
    [proxy pingWithReply:^(NSString *pong) {
        [NSOperationQueue TCM_performBlockOnMainQueue:^{ reply(pong, nil); } afterDelay:0];
    }];
}

- (void)startServerWithConfiguration:(NSDictionary *)configuration
        serverInstanceID:(NSString *)serverInstanceID
        bookmark:(NSData *)bookmark
        reply:(void (^)(BOOL, NSError *))reply {
    id<SEELSPHostProtocol> proxy = [self TCM_hostProxyWithReplyOnError:^(NSError *error) { reply(NO, error); }];
    [proxy startServerWithConfiguration:configuration serverInstanceID:serverInstanceID bookmark:bookmark reply:^(BOOL started, NSError *error) {
        [NSOperationQueue TCM_performBlockOnMainQueue:^{ reply(started, error); } afterDelay:0];
    }];
}

- (void)sendRequestForServer:(NSString *)serverInstanceID
        method:(NSString *)method
        params:(NSDictionary *)params
        reply:(void (^)(id, NSDictionary *))reply {
    __weak typeof(self) weakSelf = self;
    id<SEELSPHostProtocol> proxy = [self TCM_hostProxyWithReplyOnError:^(NSError *error) {
        reply(nil, [weakSelf TCM_errorObjectFromError:error]);
    }];
    [proxy sendRequestForServer:serverInstanceID method:method params:params reply:^(id result, NSDictionary *errorObject) {
        [NSOperationQueue TCM_performBlockOnMainQueue:^{ reply(result, errorObject); } afterDelay:0];
    }];
}

- (void)sendNotificationForServer:(NSString *)serverInstanceID
        method:(NSString *)method
        params:(NSDictionary *)params {
    id<SEELSPHostProtocol> proxy = [self TCM_hostProxyWithReplyOnError:^(NSError *error) {}];
    [proxy sendNotificationForServer:serverInstanceID method:method params:params];
}

- (void)stopServer:(NSString *)serverInstanceID reply:(void (^)(void))reply {
    id<SEELSPHostProtocol> proxy = [self TCM_hostProxyWithReplyOnError:^(NSError *error) { reply(); }];
    [proxy stopServer:serverInstanceID reply:^{
        [NSOperationQueue TCM_performBlockOnMainQueue:^{ reply(); } afterDelay:0];
    }];
}

#pragma mark - SEELSPClientProtocol

- (void)server:(NSString *)serverInstanceID didReceiveNotificationMethod:(NSString *)method params:(NSDictionary *)params {
    [NSOperationQueue TCM_performBlockOnMainQueue:^{
        [[self TCM_observerForID:serverInstanceID] handleNotificationMethod:method params:params];
    } afterDelay:0];
}

- (void)server:(NSString *)serverInstanceID didReceiveServerRequestMethod:(NSString *)method params:(NSDictionary *)params reply:(void (^)(id, NSDictionary *))reply {
    reply(nil, @{@"code": @(-32601), @"message": @"Method not found"});
}

- (void)server:(NSString *)serverInstanceID didChangeState:(SEELSPServerState)state {
}

- (void)server:(NSString *)serverInstanceID didEmitStderr:(NSString *)logLine {
}

- (void)server:(NSString *)serverInstanceID didTerminateWithStatus:(int)status reason:(NSInteger)reason {
}

@end

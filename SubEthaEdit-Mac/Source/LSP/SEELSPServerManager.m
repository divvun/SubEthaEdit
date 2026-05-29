//  SEELSPServerManager.m
//  SubEthaEdit

#import "SEELSPServerManager.h"
#import "SEELSPHostProtocol.h"
#import "SEELSPClientProtocol.h"
#import "SEELSPController.h"

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
    return [url bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope
        includingResourceValuesForKeys:nil
                         relativeToURL:nil
                                 error:error];
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
        [self TCM_whitelistJSONClassesForConnection:connection];

        __weak typeof(self) weakSelf = self;
        connection.invalidationHandler = ^{ [weakSelf TCM_dropConnection]; };
        connection.interruptionHandler = ^{ [weakSelf TCM_dropConnection]; };

        [connection resume];
        I_connection = connection;
    }
    return I_connection;
}

- (void)TCM_dropConnection {
    dispatch_async(dispatch_get_main_queue(), ^{
        self->I_connection = nil;
    });
}

// NSXPC drops JSON-collection arguments unless their member classes are whitelisted per
// selector and argument, in both directions and for reply-block arguments.
- (void)TCM_whitelistJSONClassesForConnection:(NSXPCConnection *)connection {
    NSSet *json = [NSSet setWithObjects:NSDictionary.class, NSArray.class, NSString.class, NSNumber.class, NSNull.class, nil];

    NSXPCInterface *host = connection.remoteObjectInterface;
    [host setClasses:json forSelector:@selector(startServerWithConfiguration:serverInstanceID:bookmark:reply:) argumentIndex:0 ofReply:NO];
    [host setClasses:json forSelector:@selector(sendRequestForServer:method:params:reply:) argumentIndex:2 ofReply:NO];
    [host setClasses:json forSelector:@selector(sendRequestForServer:method:params:reply:) argumentIndex:0 ofReply:YES];
    [host setClasses:json forSelector:@selector(sendRequestForServer:method:params:reply:) argumentIndex:1 ofReply:YES];
    [host setClasses:json forSelector:@selector(sendNotificationForServer:method:params:) argumentIndex:2 ofReply:NO];

    NSXPCInterface *client = connection.exportedInterface;
    [client setClasses:json forSelector:@selector(server:didReceiveNotificationMethod:params:) argumentIndex:2 ofReply:NO];
    [client setClasses:json forSelector:@selector(server:didReceiveServerRequestMethod:params:reply:) argumentIndex:2 ofReply:NO];
    [client setClasses:json forSelector:@selector(server:didReceiveServerRequestMethod:params:reply:) argumentIndex:0 ofReply:YES];
    [client setClasses:json forSelector:@selector(server:didReceiveServerRequestMethod:params:reply:) argumentIndex:1 ofReply:YES];
}

- (id<SEELSPHostProtocol>)TCM_hostProxyWithReplyOnError:(void (^)(NSError *error))errorHandler {
    return [[self TCM_connection] remoteObjectProxyWithErrorHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ errorHandler(error); });
    }];
}

- (NSDictionary *)TCM_errorObjectFromError:(NSError *)error {
    return @{@"code": @(SEELSPConnectionFailedErrorCode), @"message": error.localizedDescription ?: @"XPC connection failed"};
}

#pragma mark - Public API

- (void)pingWithReply:(void (^)(NSString *, NSError *))reply {
    id<SEELSPHostProtocol> proxy = [self TCM_hostProxyWithReplyOnError:^(NSError *error) { reply(nil, error); }];
    [proxy pingWithReply:^(NSString *pong) {
        dispatch_async(dispatch_get_main_queue(), ^{ reply(pong, nil); });
    }];
}

- (void)startServerWithConfiguration:(NSDictionary *)configuration
        serverInstanceID:(NSString *)serverInstanceID
        bookmark:(NSData *)bookmark
        reply:(void (^)(BOOL, NSError *))reply {
    id<SEELSPHostProtocol> proxy = [self TCM_hostProxyWithReplyOnError:^(NSError *error) { reply(NO, error); }];
    [proxy startServerWithConfiguration:configuration serverInstanceID:serverInstanceID bookmark:bookmark reply:^(BOOL started, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ reply(started, error); });
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
        dispatch_async(dispatch_get_main_queue(), ^{ reply(result, errorObject); });
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
        dispatch_async(dispatch_get_main_queue(), ^{ reply(); });
    }];
}

#pragma mark - SEELSPClientProtocol

- (void)server:(NSString *)serverInstanceID didReceiveNotificationMethod:(NSString *)method params:(NSDictionary *)params {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[self TCM_observerForID:serverInstanceID] handleNotificationMethod:method params:params];
    });
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

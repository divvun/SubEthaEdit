//  SEELSPServerManager.m
//  SubEthaEdit

#import "SEELSPServerManager.h"
#import "SEELSPHostProtocol.h"
#import "SEELSPClientProtocol.h"

@interface SEELSPServerManager () <SEELSPClientProtocol>
@end

@implementation SEELSPServerManager {
    NSXPCConnection *I_connection; // single shared connection; recreated lazily after death
}

+ (instancetype)sharedManager {
    static SEELSPServerManager *manager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[self alloc] init];
    });
    return manager;
}

#pragma mark - Connection

// The embedded service's bundle id is the app's id plus ".LSPHost" (see LSPHost-Info.plist
// + the target's PRODUCT_BUNDLE_IDENTIFIER), so deriving it keeps FULL / App Store / Dev
// build styles working without a hardcoded name.
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
    // Handlers fire on an arbitrary queue; touch I_connection only on the main thread so a
    // dying connection and a fresh request can't race. Next -TCM_connection reconnects.
    dispatch_async(dispatch_get_main_queue(), ^{
        self->I_connection = nil;
    });
}

// See SEELSPHostService for why every JSON-collection argument must be whitelisted in both
// directions (and for reply-block arguments). Mirror of the service-side configuration.
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

#pragma mark - Public API

- (void)pingWithReply:(void (^)(NSString *, NSError *))reply {
    id<SEELSPHostProtocol> proxy = [[self TCM_connection] remoteObjectProxyWithErrorHandler:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ reply(nil, error); });
    }];
    [proxy pingWithReply:^(NSString *pong) {
        dispatch_async(dispatch_get_main_queue(), ^{ reply(pong, nil); });
    }];
}

#pragma mark - SEELSPClientProtocol (server -> app)

// Routed to per-document controllers in a later phase; no-ops until then.
- (void)server:(NSString *)serverInstanceID didReceiveNotificationMethod:(NSString *)method params:(NSDictionary *)params {
}

- (void)server:(NSString *)serverInstanceID didReceiveServerRequestMethod:(NSString *)method params:(NSDictionary *)params reply:(void (^)(NSDictionary *, NSDictionary *))reply {
    reply(nil, @{@"code": @(-32601), @"message": @"Method not found"});
}

- (void)server:(NSString *)serverInstanceID didChangeState:(SEELSPServerState)state {
}

- (void)server:(NSString *)serverInstanceID didEmitStderr:(NSString *)logLine {
}

- (void)server:(NSString *)serverInstanceID didTerminateWithStatus:(int)status reason:(NSInteger)reason {
}

@end

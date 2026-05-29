//  SEELSPHostService.m
//  SubEthaEditLSPHost

#import "SEELSPHostService.h"
#import "SEELSPClientProtocol.h"

// JSON-RPC reserved error code, returned by the not-yet-implemented server calls.
static NSInteger const SEELSPJSONRPCInternalError = -32603;

@implementation SEELSPHostService

#pragma mark - NSXPCListenerDelegate

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SEELSPHostProtocol)];
    newConnection.exportedObject = self;
    newConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SEELSPClientProtocol)];
    [self TCM_whitelistJSONClassesForConnection:newConnection];
    [newConnection resume];
    return YES;
}

// params/result are arbitrary JSON object graphs (NSDictionary/NSArray/NSString/NSNumber/
// NSNull after NSJSONSerialization). NSXPC silently drops collection arguments unless their
// member classes are whitelisted per selector and argument — for both directions and for
// reply-block arguments. This is the single most common NSXPC failure mode.
- (void)TCM_whitelistJSONClassesForConnection:(NSXPCConnection *)connection {
    NSSet *json = [NSSet setWithObjects:NSDictionary.class, NSArray.class, NSString.class, NSNumber.class, NSNull.class, nil];

    NSXPCInterface *host = connection.exportedInterface;
    [host setClasses:json forSelector:@selector(startServerWithConfiguration:serverInstanceID:bookmark:reply:) argumentIndex:0 ofReply:NO];
    [host setClasses:json forSelector:@selector(sendRequestForServer:method:params:reply:) argumentIndex:2 ofReply:NO];
    [host setClasses:json forSelector:@selector(sendRequestForServer:method:params:reply:) argumentIndex:0 ofReply:YES];
    [host setClasses:json forSelector:@selector(sendRequestForServer:method:params:reply:) argumentIndex:1 ofReply:YES];
    [host setClasses:json forSelector:@selector(sendNotificationForServer:method:params:) argumentIndex:2 ofReply:NO];

    NSXPCInterface *client = connection.remoteObjectInterface;
    [client setClasses:json forSelector:@selector(server:didReceiveNotificationMethod:params:) argumentIndex:2 ofReply:NO];
    [client setClasses:json forSelector:@selector(server:didReceiveServerRequestMethod:params:reply:) argumentIndex:2 ofReply:NO];
    [client setClasses:json forSelector:@selector(server:didReceiveServerRequestMethod:params:reply:) argumentIndex:0 ofReply:YES];
    [client setClasses:json forSelector:@selector(server:didReceiveServerRequestMethod:params:reply:) argumentIndex:1 ofReply:YES];
}

#pragma mark - SEELSPHostProtocol

- (void)pingWithReply:(void (^)(NSString *))reply {
    reply(@"pong");
}

// The server-lifecycle methods are stubbed until the child-process plumbing lands
// (NSTask + pipes in a later phase). They fail cleanly rather than silently no-op.
- (void)startServerWithConfiguration:(NSDictionary *)configuration
        serverInstanceID:(NSString *)serverInstanceID
        bookmark:(NSData *)securityScopedBookmark
        reply:(void (^)(BOOL, NSError *))reply {
    NSError *error = [NSError errorWithDomain:@"SEELSPHostServiceErrorDomain"
                                         code:SEELSPJSONRPCInternalError
                                     userInfo:@{NSLocalizedDescriptionKey: @"Server hosting is not implemented yet"}];
    reply(NO, error);
}

- (void)sendRequestForServer:(NSString *)serverInstanceID
        method:(NSString *)method
        params:(NSDictionary *)params
        reply:(void (^)(NSDictionary *, NSDictionary *))reply {
    reply(nil, @{@"code": @(SEELSPJSONRPCInternalError), @"message": @"Server hosting is not implemented yet"});
}

- (void)sendNotificationForServer:(NSString *)serverInstanceID
        method:(NSString *)method
        params:(NSDictionary *)params {
}

- (void)cancelRequestForServer:(NSString *)serverInstanceID requestToken:(NSString *)requestToken {
}

- (void)stopServer:(NSString *)serverInstanceID reply:(void (^)(void))reply {
    reply();
}

@end

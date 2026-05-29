//  SEELSPHostService.m
//  SubEthaEditLSPHost

#import "SEELSPHostService.h"
#import "SEELSPClientProtocol.h"
#import "SEELSPChildProcess.h"

static NSInteger const SEELSPJSONRPCInternalError = -32603;
static NSString * const SEELSPHostServiceErrorDomain = @"SEELSPHostServiceErrorDomain";

@implementation SEELSPHostService {
    __weak NSXPCConnection *I_connection;
    NSMutableDictionary<NSString *, SEELSPChildProcess *> *I_childrenByID;
    NSMutableDictionary<NSString *, NSURL *> *I_scopedURLsByID;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        I_childrenByID = [NSMutableDictionary dictionary];
        I_scopedURLsByID = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - NSXPCListenerDelegate

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SEELSPHostProtocol)];
    newConnection.exportedObject = self;
    newConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SEELSPClientProtocol)];
    [self TCM_whitelistJSONClassesForConnection:newConnection];

    __weak typeof(self) weakSelf = self;
    newConnection.invalidationHandler = ^{ [weakSelf TCM_teardownAllServers]; };

    I_connection = newConnection;
    [newConnection resume];
    return YES;
}

// NSXPC drops JSON-collection arguments unless their member classes are whitelisted per
// selector and argument, in both directions and for reply-block arguments.
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

- (id<SEELSPClientProtocol>)TCM_client {
    return (id<SEELSPClientProtocol>)[I_connection remoteObjectProxy];
}

#pragma mark - SEELSPHostProtocol

- (void)pingWithReply:(void (^)(NSString *))reply {
    reply(@"pong");
}

- (void)startServerWithConfiguration:(NSDictionary *)configuration
        serverInstanceID:(NSString *)serverInstanceID
        bookmark:(NSData *)securityScopedBookmark
        reply:(void (^)(BOOL, NSError *))reply {
    NSError *error = nil;
    NSURL *executableURL = [self TCM_resolveExecutableForConfiguration:configuration
                                                              bookmark:securityScopedBookmark
                                                      serverInstanceID:serverInstanceID
                                                                 error:&error];
    if (!executableURL) {
        reply(NO, error);
    } else {
        NSArray *arguments = configuration[@"arguments"];
        NSDictionary *environment = configuration[@"environment"];
        SEELSPChildProcess *child = [[SEELSPChildProcess alloc] initWithExecutableURL:executableURL
                                                                            arguments:(arguments ?: @[])
                                                                          environment:environment];
        [self TCM_wireChild:child forServerInstanceID:serverInstanceID];
        @synchronized (self) {
            I_childrenByID[serverInstanceID] = child;
        }

        NSDictionary *initializeParams = configuration[@"initializeParams"] ?: @{};
        __weak typeof(self) weakSelf = self;
        [child launchAndInitializeWithParams:initializeParams timeout:30.0 reply:^(NSDictionary *capabilities, NSError *handshakeError) {
            typeof(self) strongSelf = weakSelf;
            if (handshakeError) {
                [strongSelf TCM_removeServer:serverInstanceID];
                reply(NO, handshakeError);
            } else {
                [[strongSelf TCM_client] server:serverInstanceID didChangeState:SEELSPServerStateRunning];
                reply(YES, nil);
            }
        }];
    }
}

- (void)sendRequestForServer:(NSString *)serverInstanceID
        method:(NSString *)method
        params:(NSDictionary *)params
        reply:(void (^)(id, NSDictionary *))reply {
    SEELSPChildProcess *child = [self TCM_childForID:serverInstanceID];
    if (child) {
        [child sendRequestMethod:method params:params reply:^(id result, id errorObject) {
            reply(result, errorObject);
        }];
    } else {
        reply(nil, @{@"code": @(SEELSPJSONRPCInternalError), @"message": @"No such server"});
    }
}

- (void)sendNotificationForServer:(NSString *)serverInstanceID
        method:(NSString *)method
        params:(NSDictionary *)params {
    [[self TCM_childForID:serverInstanceID] sendNotificationMethod:method params:params];
}

- (void)cancelRequestForServer:(NSString *)serverInstanceID requestToken:(NSString *)requestToken {
}

- (void)stopServer:(NSString *)serverInstanceID reply:(void (^)(void))reply {
    [[self TCM_childForID:serverInstanceID] terminate];
    [self TCM_removeServer:serverInstanceID];
    reply();
}

#pragma mark - Child wiring

- (void)TCM_wireChild:(SEELSPChildProcess *)child forServerInstanceID:(NSString *)serverInstanceID {
    __weak typeof(self) weakSelf = self;

    child.notificationHandler = ^(NSString *method, id params) {
        [[weakSelf TCM_client] server:serverInstanceID didReceiveNotificationMethod:method params:params];
    };
    child.serverRequestHandler = ^(id requestID, NSString *method, id params, void (^respond)(id, id)) {
        [[weakSelf TCM_client] server:serverInstanceID didReceiveServerRequestMethod:method params:params reply:^(id result, NSDictionary *errorObject) {
            respond(result, errorObject);
        }];
    };
    child.stderrHandler = ^(NSString *text) {
        [[weakSelf TCM_client] server:serverInstanceID didEmitStderr:text];
    };
    child.terminationHandler = ^(int status) {
        typeof(self) strongSelf = weakSelf;
        [[strongSelf TCM_client] server:serverInstanceID didTerminateWithStatus:status reason:0];
        [[strongSelf TCM_client] server:serverInstanceID didChangeState:SEELSPServerStateStopped];
        [strongSelf TCM_removeServer:serverInstanceID];
    };
}

#pragma mark - Server registry

- (SEELSPChildProcess *)TCM_childForID:(NSString *)serverInstanceID {
    @synchronized (self) {
        return I_childrenByID[serverInstanceID];
    }
}

- (void)TCM_removeServer:(NSString *)serverInstanceID {
    @synchronized (self) {
        [I_childrenByID removeObjectForKey:serverInstanceID];
        NSURL *scopedURL = I_scopedURLsByID[serverInstanceID];
        if (scopedURL) {
            [scopedURL stopAccessingSecurityScopedResource];
            [I_scopedURLsByID removeObjectForKey:serverInstanceID];
        }
    }
}

- (void)TCM_teardownAllServers {
    NSArray<SEELSPChildProcess *> *children = nil;
    NSArray<NSURL *> *scopedURLs = nil;
    @synchronized (self) {
        children = [I_childrenByID allValues];
        scopedURLs = [I_scopedURLsByID allValues];
        [I_childrenByID removeAllObjects];
        [I_scopedURLsByID removeAllObjects];
    }
    [children makeObjectsPerformSelector:@selector(terminate)];
    for (NSURL *scopedURL in scopedURLs) {
        [scopedURL stopAccessingSecurityScopedResource];
    }
}

#pragma mark - Executable resolution

- (NSURL *)TCM_resolveExecutableForConfiguration:(NSDictionary *)configuration
        bookmark:(NSData *)bookmark
        serverInstanceID:(NSString *)serverInstanceID
        error:(NSError **)error {
    NSURL *result = nil;
    if (bookmark) {
        BOOL stale = NO;
        NSURL *url = [NSURL URLByResolvingBookmarkData:bookmark
                                               options:NSURLBookmarkResolutionWithSecurityScope
                                         relativeToURL:nil
                                   bookmarkDataIsStale:&stale
                                                 error:error];
        if (url && !stale && [url startAccessingSecurityScopedResource]) {
            @synchronized (self) {
                I_scopedURLsByID[serverInstanceID] = url;
            }
            result = url;
        } else if (error && !*error) {
            *error = [NSError errorWithDomain:SEELSPHostServiceErrorDomain
                                         code:SEELSPJSONRPCInternalError
                                     userInfo:@{NSLocalizedDescriptionKey: stale ? @"Server bookmark is stale" : @"Could not access the server executable"}];
        }
    } else {
        NSString *path = configuration[@"executablePath"];
        if (path.length > 0) {
            result = [NSURL fileURLWithPath:path];
        } else if (error) {
            *error = [NSError errorWithDomain:SEELSPHostServiceErrorDomain
                                         code:SEELSPJSONRPCInternalError
                                     userInfo:@{NSLocalizedDescriptionKey: @"No executable bookmark or path provided"}];
        }
    }
    return result;
}

@end

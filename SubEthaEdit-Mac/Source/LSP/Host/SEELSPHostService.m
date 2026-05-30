//  SEELSPHostService.m
//  SubEthaEditLSPHost

#import "SEELSPHostService.h"
#import "SEELSPClientProtocol.h"
#import "SEELSPServerSession.h"
#import "SEELSPXPCInterface.h"
#import "SEELSPJSONRPC.h"

static NSString * const SEELSPHostServiceErrorDomain = @"SEELSPHostServiceErrorDomain";

@implementation SEELSPHostService {
    __weak NSXPCConnection *I_connection;
    NSMutableDictionary<NSString *, SEELSPServerSession *> *I_sessionsByID;
    NSMutableDictionary<NSString *, NSURL *> *I_scopedURLsByID;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        I_sessionsByID = [NSMutableDictionary dictionary];
        I_scopedURLsByID = [NSMutableDictionary dictionary];
    }
    return self;
}

#pragma mark - NSXPCListenerDelegate

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection {
    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SEELSPHostProtocol)];
    newConnection.exportedObject = self;
    newConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(SEELSPClientProtocol)];
    SEELSPApplyJSONWhitelist(newConnection.exportedInterface, newConnection.remoteObjectInterface);

    __weak typeof(self) weakSelf = self;
    newConnection.invalidationHandler = ^{ [weakSelf TCM_teardownAllServers]; };

    I_connection = newConnection;
    [newConnection resume];
    return YES;
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
        SEELSPServerSession *session = [[SEELSPServerSession alloc] initWithExecutableURL:executableURL
                                                                               arguments:(configuration[@"arguments"] ?: @[])
                                                                             environment:configuration[@"environment"]
                                                                        initializeParams:(configuration[@"initializeParams"] ?: @{})];
        [self TCM_wireSession:session forServerInstanceID:serverInstanceID];
        @synchronized (self) {
            I_sessionsByID[serverInstanceID] = session;
        }
        [session start];
        reply(YES, nil);
    }
}

- (void)sendRequestForServer:(NSString *)serverInstanceID
        method:(NSString *)method
        params:(NSDictionary *)params
        reply:(void (^)(id, NSDictionary *))reply {
    SEELSPServerSession *session = [self TCM_sessionForID:serverInstanceID];
    if (session) {
        [session sendRequestMethod:method params:params reply:^(id result, id errorObject) {
            reply(result, errorObject);
        }];
    } else {
        reply(nil, SEELSPJSONRPCErrorObject(SEELSPJSONRPCInternalError, @"No such server"));
    }
}

- (void)sendNotificationForServer:(NSString *)serverInstanceID
        method:(NSString *)method
        params:(NSDictionary *)params {
    [[self TCM_sessionForID:serverInstanceID] sendNotificationMethod:method params:params];
}

- (void)cancelRequestForServer:(NSString *)serverInstanceID requestToken:(NSString *)requestToken {
}

- (void)stopServer:(NSString *)serverInstanceID reply:(void (^)(void))reply {
    [[self TCM_sessionForID:serverInstanceID] shutdown];
    [self TCM_removeServer:serverInstanceID];
    reply();
}

#pragma mark - Session wiring

- (void)TCM_wireSession:(SEELSPServerSession *)session forServerInstanceID:(NSString *)serverInstanceID {
    __weak typeof(self) weakSelf = self;

    session.stateChangeHandler = ^(SEELSPServerState state) {
        [[weakSelf TCM_client] server:serverInstanceID didChangeState:state];
        if (state == SEELSPServerStateStopped) {
            [weakSelf TCM_releaseScopedURLForServer:serverInstanceID];
        }
    };
    session.notificationHandler = ^(NSString *method, id params) {
        [[weakSelf TCM_client] server:serverInstanceID didReceiveNotificationMethod:method params:params];
    };
    session.serverRequestHandler = ^(id requestID, NSString *method, id params, void (^respond)(id, id)) {
        [[weakSelf TCM_client] server:serverInstanceID didReceiveServerRequestMethod:method params:params reply:^(id result, NSDictionary *errorObject) {
            respond(result, errorObject);
        }];
    };
    session.stderrHandler = ^(NSString *text) {
        [[weakSelf TCM_client] server:serverInstanceID didEmitStderr:text];
    };
}

#pragma mark - Server registry

- (SEELSPServerSession *)TCM_sessionForID:(NSString *)serverInstanceID {
    @synchronized (self) {
        return I_sessionsByID[serverInstanceID];
    }
}

- (void)TCM_removeServer:(NSString *)serverInstanceID {
    @synchronized (self) {
        [I_sessionsByID removeObjectForKey:serverInstanceID];
    }
    [self TCM_releaseScopedURLForServer:serverInstanceID];
}

- (void)TCM_releaseScopedURLForServer:(NSString *)serverInstanceID {
    @synchronized (self) {
        NSURL *scopedURL = I_scopedURLsByID[serverInstanceID];
        if (scopedURL) {
            [scopedURL stopAccessingSecurityScopedResource];
            [I_scopedURLsByID removeObjectForKey:serverInstanceID];
        }
    }
}

- (void)TCM_teardownAllServers {
    NSArray<SEELSPServerSession *> *sessions = nil;
    NSArray<NSURL *> *scopedURLs = nil;
    @synchronized (self) {
        sessions = [I_sessionsByID allValues];
        scopedURLs = [I_scopedURLsByID allValues];
        [I_sessionsByID removeAllObjects];
        [I_scopedURLsByID removeAllObjects];
    }
    [sessions makeObjectsPerformSelector:@selector(shutdown)];
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

//  SEELSPHostProtocol.h
//  SubEthaEdit
//
//  The interface the LSP host XPC service exports and the app calls. The service owns
//  JSON-RPC framing and id correlation; the app sends semantic method+params and gets a
//  reply block on the correlated response, so raw JSON never crosses the XPC boundary.
//
//  serverInstanceID is an app-minted UUID string binding one hosted language server to
//  one document; every per-server call carries it.

#import <Foundation/Foundation.h>

@protocol SEELSPHostProtocol <NSObject>

// Connectivity / health check. No side effects; used to confirm the service is reachable.
- (void)pingWithReply:(void (^)(NSString *pong))reply;

// Launch a language server. configuration carries command/arguments/environment/rootURI/
// languageId/initializationOptions; bookmark is the security-scoped bookmark blob for the
// executable (resolved inside the service). reply fires once the launch attempt resolves.
- (void)startServerWithConfiguration:(NSDictionary *)configuration
        serverInstanceID:(NSString *)serverInstanceID
        bookmark:(NSData *)securityScopedBookmark
        reply:(void (^)(BOOL started, NSError *error))reply;

// Send a JSON-RPC request; reply fires with exactly one of (result, errorObject) non-nil.
- (void)sendRequestForServer:(NSString *)serverInstanceID
        method:(NSString *)method
        params:(NSDictionary *)params
        reply:(void (^)(NSDictionary *result, NSDictionary *errorObject))reply;

// Send a JSON-RPC notification (no reply).
- (void)sendNotificationForServer:(NSString *)serverInstanceID
        method:(NSString *)method
        params:(NSDictionary *)params;

// Map to LSP $/cancelRequest for the in-flight request identified by requestToken.
- (void)cancelRequestForServer:(NSString *)serverInstanceID
        requestToken:(NSString *)requestToken;

// Orderly shutdown (LSP shutdown/exit handshake) then terminate the child.
- (void)stopServer:(NSString *)serverInstanceID reply:(void (^)(void))reply;

@end

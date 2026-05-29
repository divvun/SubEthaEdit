//  SEELSPServerManager.h
//  SubEthaEdit
//
//  App-side singleton owning the single NSXPCConnection to the LSP host XPC service.
//  Later phases grow this into the per-document session registry and config/bookmark
//  resolution; for now it manages the connection lifecycle and exposes a connectivity
//  ping. The service is located by deriving its bundle id from the app's
//  (<app-bundle-id>.LSPHost), so it works across the FULL / App Store / Dev build styles.

#import <Foundation/Foundation.h>

@interface SEELSPServerManager : NSObject

+ (instancetype)sharedManager;

// Connectivity smoke test: round-trips to the service and back. reply is delivered on the
// main thread with either pong (success) or error (connection/transport failure).
- (void)pingWithReply:(void (^)(NSString *pong, NSError *error))reply;

@end

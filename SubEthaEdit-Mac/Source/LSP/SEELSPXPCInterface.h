//  SEELSPXPCInterface.h
//  SubEthaEdit

#import <Foundation/Foundation.h>

// Whitelist the JSON collection classes on every host/client method+argument that carries a JSON
// value (both directions, including reply blocks). NSXPC silently drops collection arguments
// otherwise. Shared by both ends of the connection (app and service targets).
void SEELSPApplyJSONWhitelist(NSXPCInterface *hostInterface, NSXPCInterface *clientInterface);

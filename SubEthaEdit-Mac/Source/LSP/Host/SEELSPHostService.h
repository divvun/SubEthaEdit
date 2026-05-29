//  SEELSPHostService.h
//  SubEthaEditLSPHost
//
//  The XPC service's listener delegate and exported object. Accepts the app's connection,
//  wires the bidirectional interfaces (with the JSON allowed-classes whitelist), and will
//  own the per-document SEELSPChildProcess instances (added in later phases). For now it
//  answers -pingWithReply: so connectivity can be smoke-tested.

#import <Foundation/Foundation.h>
#import "SEELSPHostProtocol.h"

@interface SEELSPHostService : NSObject <NSXPCListenerDelegate, SEELSPHostProtocol>
@end

//  SEELSPHostService.h
//  SubEthaEditLSPHost

#import <Foundation/Foundation.h>
#import "SEELSPHostProtocol.h"

@interface SEELSPHostService : NSObject <NSXPCListenerDelegate, SEELSPHostProtocol>
@end

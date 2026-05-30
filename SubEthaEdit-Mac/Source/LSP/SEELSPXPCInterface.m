//  SEELSPXPCInterface.m
//  SubEthaEdit

#import "SEELSPXPCInterface.h"
#import "SEELSPHostProtocol.h"
#import "SEELSPClientProtocol.h"

void SEELSPApplyJSONWhitelist(NSXPCInterface *hostInterface, NSXPCInterface *clientInterface) {
    NSSet *json = [NSSet setWithObjects:NSDictionary.class, NSArray.class, NSString.class, NSNumber.class, NSNull.class, nil];

    [hostInterface setClasses:json forSelector:@selector(startServerWithConfiguration:serverInstanceID:bookmark:reply:) argumentIndex:0 ofReply:NO];
    [hostInterface setClasses:json forSelector:@selector(sendRequestForServer:method:params:reply:) argumentIndex:2 ofReply:NO];
    [hostInterface setClasses:json forSelector:@selector(sendRequestForServer:method:params:reply:) argumentIndex:0 ofReply:YES];
    [hostInterface setClasses:json forSelector:@selector(sendRequestForServer:method:params:reply:) argumentIndex:1 ofReply:YES];
    [hostInterface setClasses:json forSelector:@selector(sendNotificationForServer:method:params:) argumentIndex:2 ofReply:NO];

    [clientInterface setClasses:json forSelector:@selector(server:didReceiveNotificationMethod:params:) argumentIndex:2 ofReply:NO];
    [clientInterface setClasses:json forSelector:@selector(server:didReceiveServerRequestMethod:params:reply:) argumentIndex:2 ofReply:NO];
    [clientInterface setClasses:json forSelector:@selector(server:didReceiveServerRequestMethod:params:reply:) argumentIndex:0 ofReply:YES];
    [clientInterface setClasses:json forSelector:@selector(server:didReceiveServerRequestMethod:params:reply:) argumentIndex:1 ofReply:YES];
}

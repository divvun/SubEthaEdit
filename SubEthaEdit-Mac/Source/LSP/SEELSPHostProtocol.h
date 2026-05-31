//  SEELSPHostProtocol.h
//  SubEthaEdit

#import <Foundation/Foundation.h>

@protocol SEELSPHostProtocol <NSObject>

- (void)pingWithReply:(void (^)(NSString *pong))reply;

- (void)startServerWithConfiguration:(NSDictionary *)configuration
        serverInstanceID:(NSString *)serverInstanceID
        bookmark:(NSData *)securityScopedBookmark
        reply:(void (^)(BOOL started, NSError *error))reply;

- (void)sendRequestForServer:(NSString *)serverInstanceID
        method:(NSString *)method
        params:(NSDictionary *)params
        reply:(void (^)(id result, NSDictionary *errorObject))reply;

- (void)sendNotificationForServer:(NSString *)serverInstanceID
        method:(NSString *)method
        params:(NSDictionary *)params;

- (void)cancelRequestForServer:(NSString *)serverInstanceID
        requestToken:(NSString *)requestToken;

- (void)stopServer:(NSString *)serverInstanceID reply:(void (^)(void))reply;

- (void)locateCommand:(NSString *)command reply:(void (^)(NSString *path))reply;

@end

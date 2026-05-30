//  SEELSPServerManager.h
//  SubEthaEdit

#import <Foundation/Foundation.h>

@class SEELSPController;

@interface SEELSPServerManager : NSObject

+ (instancetype)sharedManager;

- (void)registerObserver:(SEELSPController *)observer forServerInstanceID:(NSString *)serverInstanceID;
- (void)unregisterServerInstanceID:(NSString *)serverInstanceID;

+ (NSData *)bookmarkForExecutableURL:(NSURL *)url error:(NSError **)error;

- (void)pingWithReply:(void (^)(NSString *pong, NSError *error))reply;

- (void)startServerWithConfiguration:(NSDictionary *)configuration
        serverInstanceID:(NSString *)serverInstanceID
        bookmark:(NSData *)bookmark
        reply:(void (^)(BOOL started, NSError *error))reply;

- (void)sendRequestForServer:(NSString *)serverInstanceID
        method:(NSString *)method
        params:(NSDictionary *)params
        reply:(void (^)(id result, NSDictionary *errorObject))reply;

- (void)sendNotificationForServer:(NSString *)serverInstanceID
        method:(NSString *)method
        params:(NSDictionary *)params;

- (void)stopServer:(NSString *)serverInstanceID reply:(void (^)(void))reply;

@end

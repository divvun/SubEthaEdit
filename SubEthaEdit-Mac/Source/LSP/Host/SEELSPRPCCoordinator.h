//  SEELSPRPCCoordinator.h
//  SubEthaEdit

#import <Foundation/Foundation.h>

@interface SEELSPRPCCoordinator : NSObject

- (NSDictionary *)requestObjectForMethod:(NSString *)method
                                  params:(id)params
                                   reply:(void (^)(id result, id errorObject))reply;

- (NSDictionary *)notificationObjectForMethod:(NSString *)method params:(id)params;

- (void)handleIncomingObject:(id)object;

- (void)failAllPendingWithErrorObject:(id)errorObject;

@property (nonatomic, readonly) NSUInteger pendingRequestCount;

@property (nonatomic, copy) void (^notificationHandler)(NSString *method, id params);
@property (nonatomic, copy) void (^serverRequestHandler)(id requestID, NSString *method, id params, void (^respond)(id result, id errorObject));
@property (nonatomic, copy) void (^responseSender)(NSDictionary *responseObject);

@end

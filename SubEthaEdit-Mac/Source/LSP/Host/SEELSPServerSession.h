//  SEELSPServerSession.h
//  SubEthaEditLSPHost

#import <Foundation/Foundation.h>
#import "SEELSPClientProtocol.h"

@interface SEELSPServerSession : NSObject

- (instancetype)initWithExecutableURL:(NSURL *)executableURL
        arguments:(NSArray<NSString *> *)arguments
        environment:(NSDictionary<NSString *, NSString *> *)environment
        initializeParams:(NSDictionary *)initializeParams;

@property (nonatomic, readonly) SEELSPServerState state;

@property (nonatomic) NSTimeInterval initializeTimeout;
@property (nonatomic) NSTimeInterval restartBackoffBase;
@property (nonatomic) NSTimeInterval restartBackoffCap;
@property (nonatomic) NSUInteger maxRestartsPerWindow;
@property (nonatomic) NSTimeInterval restartWindow;

// Set before -start. stateChangeHandler fires on every transition.
@property (nonatomic, copy) void (^stateChangeHandler)(SEELSPServerState state);
@property (nonatomic, copy) void (^notificationHandler)(NSString *method, id params);
@property (nonatomic, copy) void (^serverRequestHandler)(id requestID, NSString *method, id params, void (^respond)(id result, id errorObject));
@property (nonatomic, copy) void (^stderrHandler)(NSString *text);

- (void)start;
- (void)sendRequestMethod:(NSString *)method params:(id)params reply:(void (^)(id result, id errorObject))reply;
- (void)sendNotificationMethod:(NSString *)method params:(id)params;
- (void)shutdown;

@end

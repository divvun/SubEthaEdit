//  SEELSPRPCCoordinator.m
//  SubEthaEdit

#import "SEELSPRPCCoordinator.h"

// JSON-RPC reserved error code, used when a server request arrives with no handler.
static NSInteger const SEELSPJSONRPCMethodNotFound = -32601;

@implementation SEELSPRPCCoordinator {
    long long I_nextRequestID;
    NSMutableDictionary *I_pendingReplies; // NSNumber(id) -> void (^)(id result, id errorObject)
}

- (instancetype)init {
    self = [super init];
    if (self) {
        I_nextRequestID = 1;
        I_pendingReplies = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSUInteger)pendingRequestCount {
    return [I_pendingReplies count];
}

- (NSDictionary *)requestObjectForMethod:(NSString *)method params:(id)params reply:(void (^)(id, id))reply {
    NSNumber *requestID = @(I_nextRequestID++);
    if (reply) {
        I_pendingReplies[requestID] = [reply copy];
    }
    NSMutableDictionary *object = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                   @"2.0", @"jsonrpc",
                                   requestID, @"id",
                                   method, @"method",
                                   nil];
    if (params) {
        object[@"params"] = params;
    }
    return object;
}

- (NSDictionary *)notificationObjectForMethod:(NSString *)method params:(id)params {
    NSMutableDictionary *object = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                   @"2.0", @"jsonrpc",
                                   method, @"method",
                                   nil];
    if (params) {
        object[@"params"] = params;
    }
    return object;
}

- (void)handleIncomingObject:(id)object {
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSDictionary *message = object;
        id idObject = message[@"id"];
        id methodObject = message[@"method"];
        BOOL hasID = (idObject != nil && idObject != [NSNull null]);
        BOOL hasMethod = [methodObject isKindOfClass:[NSString class]];

        if (hasMethod && hasID) {
            [self TCM_handleServerRequestWithID:idObject method:methodObject params:message[@"params"]];
        } else if (hasMethod) {
            if (self.notificationHandler) {
                self.notificationHandler(methodObject, message[@"params"]);
            }
        } else if (hasID) {
            [self TCM_handleResponse:message forID:idObject];
        }
        // Anything else is malformed and is ignored.
    }
}

- (void)failAllPendingWithErrorObject:(id)errorObject {
    NSArray *replies = [I_pendingReplies allValues];
    [I_pendingReplies removeAllObjects];
    for (void (^reply)(id, id) in replies) {
        reply(nil, errorObject);
    }
}

- (void)TCM_handleResponse:(NSDictionary *)message forID:(id)idObject {
    void (^reply)(id, id) = I_pendingReplies[idObject];
    if (reply) {
        [I_pendingReplies removeObjectForKey:idObject];
        id errorObject = message[@"error"];
        BOOL hasError = (errorObject != nil && errorObject != [NSNull null]);
        if (hasError) {
            reply(nil, errorObject);
        } else {
            reply(message[@"result"], nil);
        }
    }
    // An unknown id is ignored (late response to a cancelled/cleared request).
}

- (void)TCM_handleServerRequestWithID:(id)idObject method:(NSString *)method params:(id)params {
    if (self.serverRequestHandler) {
        __weak typeof(self) weakSelf = self;
        __block BOOL didRespond = NO;
        void (^respond)(id, id) = ^(id result, id errorObject) {
            typeof(self) strongSelf = weakSelf;
            if (strongSelf && !didRespond) {
                didRespond = YES;
                [strongSelf TCM_sendResponseForID:idObject result:result errorObject:errorObject];
            }
        };
        self.serverRequestHandler(idObject, method, params, respond);
    } else {
        id errorObject = @{@"code": @(SEELSPJSONRPCMethodNotFound), @"message": @"Method not found"};
        [self TCM_sendResponseForID:idObject result:nil errorObject:errorObject];
    }
}

- (void)TCM_sendResponseForID:(id)idObject result:(id)result errorObject:(id)errorObject {
    NSMutableDictionary *response = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                     @"2.0", @"jsonrpc",
                                     idObject, @"id",
                                     nil];
    if (errorObject) {
        response[@"error"] = errorObject;
    } else {
        response[@"result"] = (result ? result : [NSNull null]);
    }
    if (self.responseSender) {
        self.responseSender(response);
    }
}

@end

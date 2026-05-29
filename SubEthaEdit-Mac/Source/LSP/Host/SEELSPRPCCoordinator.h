//  SEELSPRPCCoordinator.h
//  SubEthaEdit
//
//  The JSON-RPC 2.0 message layer that sits between SEELSPMessageReader/Writer (framing
//  + (de)serialization) and a transport. It builds outgoing request/notification objects,
//  correlates responses back to the reply block that issued the request, and classifies
//  incoming objects as response / server-initiated request / notification.
//
//  This object is not thread-safe; its owner (one per child process) must drive it from a
//  single serial queue, the same one that reads the child's stdout.

#import <Foundation/Foundation.h>

@interface SEELSPRPCCoordinator : NSObject

// Build a request object, registering reply for the eventual response. reply is invoked with
// exactly one of (result, errorObject) non-nil: (result, nil) on success — result may be
// NSNull for a JSON null result — or (nil, errorObject) on a JSON-RPC error or when
// failAllPendingWithErrorObject: clears the request.
- (NSDictionary *)requestObjectForMethod:(NSString *)method
                                  params:(id)params
                                   reply:(void (^)(id result, id errorObject))reply;

// Build a notification object (no id, never replied to).
- (NSDictionary *)notificationObjectForMethod:(NSString *)method params:(id)params;

// Feed a decoded incoming JSON value (an NSDictionary for any well-formed message).
- (void)handleIncomingObject:(id)object;

// Fail and clear every outstanding request — e.g. when the child process dies.
- (void)failAllPendingWithErrorObject:(id)errorObject;

// Number of requests still awaiting a response (exposed for diagnostics/tests).
@property (nonatomic, readonly) NSUInteger pendingRequestCount;

// Server -> client notifications (e.g. textDocument/publishDiagnostics).
@property (nonatomic, copy) void (^notificationHandler)(NSString *method, id params);

// Server -> client requests. The handler must call respond exactly once: (result, nil) for
// success or (nil, errorObject) for failure. If no handler is set, the coordinator answers
// with a JSON-RPC "method not found" error so the server is never left waiting.
@property (nonatomic, copy) void (^serverRequestHandler)(id requestID, NSString *method, id params, void (^respond)(id result, id errorObject));

// Invoked when the coordinator produces an outgoing object that the owner must frame + send
// (currently only responses to server-initiated requests).
@property (nonatomic, copy) void (^responseSender)(NSDictionary *responseObject);

@end

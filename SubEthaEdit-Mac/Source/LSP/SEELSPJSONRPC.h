//  SEELSPJSONRPC.h
//  SubEthaEdit

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SEELSPJSONRPCErrorCode) {
    SEELSPJSONRPCParseError           = -32700,
    SEELSPJSONRPCInvalidRequest       = -32600,
    SEELSPJSONRPCMethodNotFound       = -32601,
    SEELSPJSONRPCInvalidParams        = -32602,
    SEELSPJSONRPCInternalError        = -32603,
    SEELSPJSONRPCServerNotInitialized = -32002,
    SEELSPJSONRPCRequestCancelled     = -32800,
    SEELSPJSONRPCContentModified      = -32801,
};

static inline NSDictionary *SEELSPJSONRPCErrorObject(SEELSPJSONRPCErrorCode code, NSString *message) {
    return @{@"code": @(code), @"message": (message ?: @"")};
}

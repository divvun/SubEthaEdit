//  SEELSPMessageWriter.h
//  SubEthaEdit
//
//  Serializes JSON-RPC objects into LSP base-protocol framing (the counterpart to
//  SEELSPMessageReader). Stateless; all methods are class methods.

#import <Foundation/Foundation.h>

@interface SEELSPMessageWriter : NSObject

// Serialize a JSON-RPC object and wrap it in framing. Returns nil (and fills error)
// if the object is not a valid JSON top-level value.
+ (NSData *)framedDataForJSONObject:(id)object error:(NSError **)error;

// Wrap an already-serialized JSON body in framing.
+ (NSData *)framedDataForJSONBody:(NSData *)body;

@end

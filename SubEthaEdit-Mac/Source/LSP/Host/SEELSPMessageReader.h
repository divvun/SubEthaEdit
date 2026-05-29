//  SEELSPMessageReader.h
//  SubEthaEdit
//
//  Incremental reader for the LSP base-protocol framing:
//
//      Content-Length: <N>\r\n
//      [<header>: <value>\r\n]*
//      \r\n
//      <N bytes of UTF-8 JSON>
//
//  Bytes arrive in arbitrary chunks (a pipe read can split a message anywhere).
//  Each complete message body is handed to messageHandler. Modelled on the frame
//  reader in TCMBEEPSession (TCM_readBytes), adapted from BEEP's LF/Content-Length
//  framing to LSP's CRLFCRLF/Content-Length framing.

#import <Foundation/Foundation.h>

extern NSString * const SEELSPMessageReaderErrorDomain;

typedef NS_ENUM(NSInteger, SEELSPMessageReaderErrorCode) {
    SEELSPMessageReaderErrorMissingContentLength  = 1,
    SEELSPMessageReaderErrorMalformedHeader       = 2,
    SEELSPMessageReaderErrorContentLengthTooLarge = 3,
};

@interface SEELSPMessageReader : NSObject

// Invoked once per complete message with the raw JSON body (framing headers stripped).
@property (nonatomic, copy) void (^messageHandler)(NSData *jsonBody);

// Invoked on a protocol violation. The reader resets its state afterwards; a transport
// should treat this as fatal and tear the connection down (there is no reliable resync).
@property (nonatomic, copy) void (^errorHandler)(NSError *error);

// Largest content length we will buffer for a single message. Defaults to 64 MiB.
// A larger declared length raises SEELSPMessageReaderErrorContentLengthTooLarge.
@property (nonatomic) NSUInteger maximumContentLength;

- (void)appendData:(NSData *)data;
- (void)reset;

@end

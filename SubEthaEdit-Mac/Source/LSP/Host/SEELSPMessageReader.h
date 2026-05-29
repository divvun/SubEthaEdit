//  SEELSPMessageReader.h
//  SubEthaEdit

#import <Foundation/Foundation.h>

extern NSString * const SEELSPMessageReaderErrorDomain;

typedef NS_ENUM(NSInteger, SEELSPMessageReaderErrorCode) {
    SEELSPMessageReaderErrorMissingContentLength  = 1,
    SEELSPMessageReaderErrorMalformedHeader       = 2,
    SEELSPMessageReaderErrorContentLengthTooLarge = 3,
};

@interface SEELSPMessageReader : NSObject

@property (nonatomic, copy) void (^messageHandler)(NSData *jsonBody);
@property (nonatomic, copy) void (^errorHandler)(NSError *error);
@property (nonatomic) NSUInteger maximumContentLength;

- (void)appendData:(NSData *)data;
- (void)reset;

@end

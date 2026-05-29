//  SEELSPMessageReader.m
//  SubEthaEdit

#import "SEELSPMessageReader.h"

NSString * const SEELSPMessageReaderErrorDomain = @"SEELSPMessageReaderErrorDomain";

static NSUInteger const SEELSPDefaultMaximumContentLength = 64 * 1024 * 1024;

@implementation SEELSPMessageReader {
    NSMutableData *I_buffer;
    NSInteger I_expectedContentLength; // -1 while reading headers
}

- (instancetype)init {
    self = [super init];
    if (self) {
        I_buffer = [NSMutableData data];
        I_expectedContentLength = -1;
        _maximumContentLength = SEELSPDefaultMaximumContentLength;
    }
    return self;
}

- (void)reset {
    [I_buffer setLength:0];
    I_expectedContentLength = -1;
}

- (void)appendData:(NSData *)data {
    if ([data length] > 0) {
        [I_buffer appendData:data];
        [self TCM_processBuffer];
    }
}

- (void)TCM_processBuffer {
    BOOL keepGoing = YES;
    while (keepGoing) {
        if (I_expectedContentLength < 0) {
            keepGoing = [self TCM_tryConsumeHeader];
        } else {
            keepGoing = [self TCM_tryConsumeContent];
        }
    }
}

- (BOOL)TCM_tryConsumeHeader {
    BOOL madeProgress = NO;
    static NSData *terminator = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        const char crlfcrlf[4] = {'\r', '\n', '\r', '\n'};
        terminator = [NSData dataWithBytes:crlfcrlf length:4];
    });

    NSRange searchRange = NSMakeRange(0, [I_buffer length]);
    NSRange terminatorRange = [I_buffer rangeOfData:terminator options:0 range:searchRange];
    if (terminatorRange.location != NSNotFound) {
        NSData *headerData = [I_buffer subdataWithRange:NSMakeRange(0, terminatorRange.location)];
        NSInteger contentLength = [self TCM_contentLengthFromHeaderData:headerData];
        [I_buffer replaceBytesInRange:NSMakeRange(0, NSMaxRange(terminatorRange)) withBytes:NULL length:0];

        if (contentLength < 0) {
            [self TCM_reportErrorCode:SEELSPMessageReaderErrorMissingContentLength
                          description:@"LSP message header without a valid Content-Length"];
            [self reset];
        } else if ((NSUInteger)contentLength > self.maximumContentLength) {
            [self TCM_reportErrorCode:SEELSPMessageReaderErrorContentLengthTooLarge
                          description:@"LSP message Content-Length exceeds the maximum"];
            [self reset];
        } else {
            I_expectedContentLength = contentLength;
            madeProgress = YES;
        }
    }
    return madeProgress;
}

- (BOOL)TCM_tryConsumeContent {
    BOOL madeProgress = NO;
    if ((NSInteger)[I_buffer length] >= I_expectedContentLength) {
        NSData *body = [I_buffer subdataWithRange:NSMakeRange(0, I_expectedContentLength)];
        [I_buffer replaceBytesInRange:NSMakeRange(0, I_expectedContentLength) withBytes:NULL length:0];
        I_expectedContentLength = -1;
        if (self.messageHandler) {
            self.messageHandler(body);
        }
        madeProgress = YES;
    }
    return madeProgress;
}

- (NSInteger)TCM_contentLengthFromHeaderData:(NSData *)headerData {
    NSInteger result = -1;
    NSString *headerString = [[NSString alloc] initWithData:headerData encoding:NSASCIIStringEncoding];
    if (headerString) {
        NSCharacterSet *whitespace = [NSCharacterSet whitespaceCharacterSet];
        for (NSString *line in [headerString componentsSeparatedByString:@"\r\n"]) {
            NSRange colonRange = [line rangeOfString:@":"];
            if (colonRange.location != NSNotFound) {
                NSString *key = [[line substringToIndex:colonRange.location] stringByTrimmingCharactersInSet:whitespace];
                if ([key caseInsensitiveCompare:@"Content-Length"] == NSOrderedSame) {
                    NSString *value = [[line substringFromIndex:NSMaxRange(colonRange)] stringByTrimmingCharactersInSet:whitespace];
                    result = [self TCM_parseNonNegativeInteger:value];
                }
            }
        }
    }
    return result;
}

- (NSInteger)TCM_parseNonNegativeInteger:(NSString *)string {
    NSInteger result = -1;
    if ([string length] > 0) {
        NSCharacterSet *nonDigits = [[NSCharacterSet decimalDigitCharacterSet] invertedSet];
        if ([string rangeOfCharacterFromSet:nonDigits].location == NSNotFound) {
            long long value = [string longLongValue];
            if (value >= 0 && value <= NSIntegerMax) {
                result = (NSInteger)value;
            }
        }
    }
    return result;
}

- (void)TCM_reportErrorCode:(SEELSPMessageReaderErrorCode)code description:(NSString *)description {
    if (self.errorHandler) {
        NSError *error = [NSError errorWithDomain:SEELSPMessageReaderErrorDomain
                                             code:code
                                         userInfo:@{NSLocalizedDescriptionKey: description}];
        self.errorHandler(error);
    }
}

@end

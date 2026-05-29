//  SEELSPMessageWriter.m
//  SubEthaEdit

#import "SEELSPMessageWriter.h"

@implementation SEELSPMessageWriter

+ (NSData *)framedDataForJSONObject:(id)object error:(NSError **)error {
    NSData *result = nil;
    if ([NSJSONSerialization isValidJSONObject:object]) {
        NSData *body = [NSJSONSerialization dataWithJSONObject:object options:0 error:error];
        if (body) {
            result = [self framedDataForJSONBody:body];
        }
    } else if (error) {
        *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                     code:NSFormattingError
                                 userInfo:@{NSLocalizedDescriptionKey: @"Object is not a valid top-level JSON value"}];
    }
    return result;
}

+ (NSData *)framedDataForJSONBody:(NSData *)body {
    NSString *header = [NSString stringWithFormat:@"Content-Length: %lu\r\n\r\n", (unsigned long)[body length]];
    NSMutableData *framed = [[header dataUsingEncoding:NSASCIIStringEncoding] mutableCopy];
    [framed appendData:body];
    return framed;
}

@end

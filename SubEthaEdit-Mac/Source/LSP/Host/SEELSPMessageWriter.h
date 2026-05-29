//  SEELSPMessageWriter.h
//  SubEthaEdit

#import <Foundation/Foundation.h>

@interface SEELSPMessageWriter : NSObject

+ (NSData *)framedDataForJSONObject:(id)object error:(NSError **)error;
+ (NSData *)framedDataForJSONBody:(NSData *)body;

@end

//  SEELSPController.h
//  SubEthaEdit

#import <Foundation/Foundation.h>

@class PlainTextDocument;

@interface SEELSPController : NSObject

- (instancetype)initWithDocument:(PlainTextDocument *)document;

@property (nonatomic, readonly, getter=isActive) BOOL active;

- (void)startIfNeeded;
- (void)shutdown;

@end

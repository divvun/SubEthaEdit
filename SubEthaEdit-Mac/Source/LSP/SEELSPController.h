//  SEELSPController.h
//  SubEthaEdit

#import <Foundation/Foundation.h>

@class PlainTextDocument, FullTextStorage;

@interface SEELSPController : NSObject

- (instancetype)initWithDocument:(PlainTextDocument *)document;

@property (nonatomic, readonly, getter=isActive) BOOL active;

- (void)startIfNeeded;
- (void)shutdown;

// Forwarded from PlainTextDocument's FullTextStorage will/did-replace callbacks. The change
// event is captured pre-edit (in will, where textStorage still holds the old text) and
// committed in did; accumulated events flush as one coalesced textDocument/didChange.
- (void)noteWillReplaceCharactersInRange:(NSRange)range withString:(NSString *)string textStorage:(FullTextStorage *)textStorage;
- (void)noteDidReplaceCharactersInRange:(NSRange)range withString:(NSString *)string;

@end

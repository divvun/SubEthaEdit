//  SEELSPController.h
//  SubEthaEdit

#import <Foundation/Foundation.h>

@class PlainTextDocument, FullTextStorage;

extern NSString * const SEELSPControllerDidChangeDiagnosticsNotification;

@interface SEELSPController : NSObject

- (instancetype)initWithDocument:(PlainTextDocument *)document;

@property (nonatomic, readonly, getter=isActive) BOOL active;

@property (nonatomic, readonly, copy) NSArray *diagnostics;

- (NSArray *)diagnosticsInFullRange:(NSRange)range;

- (NSArray *)documentSymbolEntries;
- (void)requestDocumentSymbolsIfNeeded;

+ (NSArray *)symbolTableEntriesFromDocumentSymbolResult:(NSArray *)result textStorage:(FullTextStorage *)textStorage;

- (void)handleNotificationMethod:(NSString *)method params:(id)params;

- (void)startIfNeeded;
- (void)shutdown;

- (void)noteWillReplaceCharactersInRange:(NSRange)range withString:(NSString *)string textStorage:(FullTextStorage *)textStorage;
- (void)noteDidReplaceCharactersInRange:(NSRange)range withString:(NSString *)string;

@end

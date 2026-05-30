//  SEELSPController.h
//  SubEthaEdit

#import <Cocoa/Cocoa.h>
#import "SEELSPDiagnostic.h"

@class PlainTextDocument, FullTextStorage;

extern NSString * const SEELSPControllerDidChangeDiagnosticsNotification;

@interface SEELSPController : NSObject

- (instancetype)initWithDocument:(PlainTextDocument *)document;

@property (nonatomic, readonly, getter=isActive) BOOL active;

@property (nonatomic, readonly, copy) NSArray *diagnostics;

- (NSArray *)diagnosticsInFullRange:(NSRange)range;

+ (NSColor *)colorForSeverity:(SEELSPDiagnosticSeverity)severity;
+ (SEELSPDiagnosticSeverity)highestSeverityInDiagnostics:(NSArray *)diagnostics;
+ (NSAttributedString *)attributedStringForDiagnostics:(NSArray *)diagnostics;

- (NSArray *)documentSymbolEntries;
- (void)requestDocumentSymbolsIfNeeded;

+ (NSArray *)symbolTableEntriesFromDocumentSymbolResult:(NSArray *)result textStorage:(FullTextStorage *)textStorage;

- (void)requestHoverAtFullOffset:(NSUInteger)offset reply:(void (^)(NSAttributedString *contents, NSRange fullRange, BOOL hasRange))reply;
+ (NSRange)hoverFullRangeFromResult:(NSDictionary *)result textStorage:(FullTextStorage *)textStorage;

- (void)requestDefinitionAtFullOffset:(NSUInteger)offset reply:(void (^)(NSArray *targets))reply;
+ (NSArray *)definitionTargetsFromResult:(id)result;
+ (NSRange)fullTextRangeForLSPRange:(NSDictionary *)rangeDict textStorage:(FullTextStorage *)textStorage;

- (void)requestCompletionAtFullOffset:(NSUInteger)offset reply:(void (^)(NSArray *completionStrings))reply;
+ (NSArray *)completionStringsFromResult:(id)result;

- (void)handleNotificationMethod:(NSString *)method params:(id)params;

- (void)startIfNeeded;
- (void)shutdown;

- (void)noteWillReplaceCharactersInRange:(NSRange)range withString:(NSString *)string textStorage:(FullTextStorage *)textStorage;
- (void)noteDidReplaceCharactersInRange:(NSRange)range withString:(NSString *)string;

@end

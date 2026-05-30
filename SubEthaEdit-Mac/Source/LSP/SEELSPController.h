//  SEELSPController.h
//  SubEthaEdit

#import <Foundation/Foundation.h>

@class PlainTextDocument, FullTextStorage;

// Posted (object = the PlainTextDocument) when the document's LSP diagnostics change.
extern NSString * const SEELSPControllerDidChangeDiagnosticsNotification;

@interface SEELSPController : NSObject

- (instancetype)initWithDocument:(PlainTextDocument *)document;

@property (nonatomic, readonly, getter=isActive) BOOL active;

// Latest published diagnostics for the document (array of SEELSPDiagnostic).
@property (nonatomic, readonly, copy) NSArray *diagnostics;

// Diagnostics whose full-text range intersects range (point diagnostics match by location).
- (NSArray *)diagnosticsInFullRange:(NSRange)range;

// Server -> client notification routed by SEELSPServerManager (e.g. publishDiagnostics).
- (void)handleNotificationMethod:(NSString *)method params:(id)params;

- (void)startIfNeeded;
- (void)shutdown;

// Forwarded from PlainTextDocument's FullTextStorage will/did-replace callbacks. The change
// event is captured pre-edit (in will, where textStorage still holds the old text) and
// committed in did; accumulated events flush as one coalesced textDocument/didChange.
- (void)noteWillReplaceCharactersInRange:(NSRange)range withString:(NSString *)string textStorage:(FullTextStorage *)textStorage;
- (void)noteDidReplaceCharactersInRange:(NSRange)range withString:(NSString *)string;

@end

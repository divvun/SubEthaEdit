//  FullTextStorage+LSPPosition.h
//  SubEthaEdit

#import "FullTextStorage.h"

// LSP positions are 0-based {line, character}, character in UTF-16 code units — which is
// NSString's own indexing, so no codepoint conversion is involved.
@interface FullTextStorage (LSPPosition)

- (void)lspLine:(NSUInteger *)outLine character:(NSUInteger *)outCharacter forOffset:(NSUInteger)offset;
- (NSUInteger)offsetForLSPLine:(NSUInteger)line character:(NSUInteger)character;

// An incremental LSP TextDocumentContentChangeEvent for replacing range with string. The
// range positions are computed against the receiver's current text, so call this before the
// edit is applied (the pre-edit buffer).
- (NSDictionary *)lspContentChangeForRange:(NSRange)range replacementString:(NSString *)string;

@end

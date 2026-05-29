//  FullTextStorage+LSPPosition.h
//  SubEthaEdit

#import "FullTextStorage.h"

// LSP positions are 0-based {line, character}, character in UTF-16 code units — which is
// NSString's own indexing, so no codepoint conversion is involved.
@interface FullTextStorage (LSPPosition)

- (void)lspLine:(NSUInteger *)outLine character:(NSUInteger *)outCharacter forOffset:(NSUInteger)offset;
- (NSUInteger)offsetForLSPLine:(NSUInteger)line character:(NSUInteger)character;

@end

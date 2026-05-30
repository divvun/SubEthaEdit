//  FullTextStorage+LSPPosition.h
//  SubEthaEdit

#import "FullTextStorage.h"

@interface FullTextStorage (LSPPosition)

- (void)lspLine:(NSUInteger *)outLine character:(NSUInteger *)outCharacter forOffset:(NSUInteger)offset;
- (NSUInteger)offsetForLSPLine:(NSUInteger)line character:(NSUInteger)character;

- (NSDictionary *)lspContentChangeForRange:(NSRange)range replacementString:(NSString *)string;

@end

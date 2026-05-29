//  FullTextStorage+LSPPosition.m
//  SubEthaEdit

#import "FullTextStorage+LSPPosition.h"

@implementation FullTextStorage (LSPPosition)

- (void)lspLine:(NSUInteger *)outLine character:(NSUInteger *)outCharacter forOffset:(NSUInteger)offset {
    NSUInteger length = [[self string] length];
    NSUInteger clampedOffset = MIN(offset, length);
    int lineNumber = [self lineNumberForLocation:clampedOffset];
    NSArray *starts = [self lineStarts];
    NSUInteger lineStart = 0;
    if (lineNumber >= 1 && (NSUInteger)lineNumber <= starts.count) {
        lineStart = [starts[lineNumber - 1] unsignedIntegerValue];
    }
    if (outLine) { *outLine = (NSUInteger)(lineNumber - 1); }
    if (outCharacter) { *outCharacter = clampedOffset - lineStart; }
}

- (NSUInteger)offsetForLSPLine:(NSUInteger)line character:(NSUInteger)character {
    NSString *string = [self string];
    NSUInteger length = [string length];
    NSUInteger result;
    if (line + 1 > [self numberOfLines]) {
        result = length;
    } else {
        NSRange lineRange = [self findLine:(int)(line + 1)];
        if (lineRange.location == NSNotFound) {
            result = length;
        } else {
            NSUInteger lineStart = 0, lineEnd = 0, contentsEnd = 0;
            [string getLineStart:&lineStart end:&lineEnd contentsEnd:&contentsEnd forRange:NSMakeRange(lineRange.location, 0)];
            NSUInteger maxCharacter = contentsEnd - lineRange.location;
            result = lineRange.location + MIN(character, maxCharacter);
        }
    }
    return result;
}

- (NSDictionary *)lspContentChangeForRange:(NSRange)range replacementString:(NSString *)string {
    NSUInteger startLine = 0, startCharacter = 0, endLine = 0, endCharacter = 0;
    [self lspLine:&startLine character:&startCharacter forOffset:range.location];
    [self lspLine:&endLine character:&endCharacter forOffset:NSMaxRange(range)];
    return @{
        @"range": @{
            @"start": @{@"line": @(startLine), @"character": @(startCharacter)},
            @"end": @{@"line": @(endLine), @"character": @(endCharacter)},
        },
        @"text": (string ?: @""),
    };
}

@end

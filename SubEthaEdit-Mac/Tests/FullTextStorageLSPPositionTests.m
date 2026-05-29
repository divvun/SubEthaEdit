//  FullTextStorageLSPPositionTests.m
//  SubEthaEdit

#import <XCTest/XCTest.h>
#import "NSStringSEEAdditions.h"
#import "FoldableTextStorage.h"
#import "FullTextStorage.h"
#import "FullTextStorage+LSPPosition.h"

@interface FullTextStorageLSPPositionTests : XCTestCase {
    NSMutableArray *_keepAlive;
}
@end

@implementation FullTextStorageLSPPositionTests

- (void)setUp {
    _keepAlive = [NSMutableArray array];
}

- (FullTextStorage *)storageWithString:(NSString *)string {
    FoldableTextStorage *foldable = [[FoldableTextStorage alloc] init];
    [foldable replaceCharactersInRange:NSMakeRange(0, 0) withString:string];
    [_keepAlive addObject:foldable]; // full's back-reference is weak; keep the owner alive
    return [foldable fullTextStorage];
}

- (void)assertOffset:(NSUInteger)offset mapsToLine:(NSUInteger)line character:(NSUInteger)character in:(FullTextStorage *)full {
    NSUInteger gotLine = NSNotFound, gotChar = NSNotFound;
    [full lspLine:&gotLine character:&gotChar forOffset:offset];
    XCTAssertEqual(gotLine, line, @"line for offset %lu", (unsigned long)offset);
    XCTAssertEqual(gotChar, character, @"character for offset %lu", (unsigned long)offset);
    XCTAssertEqual([full offsetForLSPLine:line character:character], offset, @"offset for {%lu,%lu}", (unsigned long)line, (unsigned long)character);
}

- (void)testBasicMultiLine {
    FullTextStorage *full = [self storageWithString:@"line0\nline1\nline22"];
    [self assertOffset:0 mapsToLine:0 character:0 in:full];   // 'l' of line0
    [self assertOffset:5 mapsToLine:0 character:5 in:full];   // end of line0 (before \n)
    [self assertOffset:6 mapsToLine:1 character:0 in:full];   // 'l' of line1
    [self assertOffset:12 mapsToLine:2 character:0 in:full];  // 'l' of line22
    [self assertOffset:18 mapsToLine:2 character:6 in:full];  // end of document
}

- (void)testExhaustiveRoundTripLF {
    FullTextStorage *full = [self storageWithString:@"\nabc\n\nde\nfghi\n"];
    NSUInteger length = full.string.length;
    for (NSUInteger offset = 0; offset <= length; offset++) {
        NSUInteger line = NSNotFound, character = NSNotFound;
        [full lspLine:&line character:&character forOffset:offset];
        XCTAssertEqual([full offsetForLSPLine:line character:character], offset,
                       @"round-trip offset %lu via {%lu,%lu}", (unsigned long)offset, (unsigned long)line, (unsigned long)character);
    }
}

- (void)testCRLF {
    FullTextStorage *full = [self storageWithString:@"a\r\nb"];
    [self assertOffset:0 mapsToLine:0 character:0 in:full];   // 'a'
    [self assertOffset:1 mapsToLine:0 character:1 in:full];   // end of line0 content (before \r\n)
    [self assertOffset:3 mapsToLine:1 character:0 in:full];   // 'b' (after \r\n)
    // a character past end-of-line content clamps to the content end (before the terminator).
    XCTAssertEqual([full offsetForLSPLine:0 character:99], 1u);
}

- (void)testMultibyteIsUTF16 {
    // U+1F600 is a surrogate pair: 2 UTF-16 code units.
    FullTextStorage *full = [self storageWithString:@"a\U0001F600b\nc"];
    [self assertOffset:0 mapsToLine:0 character:0 in:full];   // 'a'
    [self assertOffset:3 mapsToLine:0 character:3 in:full];   // 'b' (after the 2-unit emoji)
    [self assertOffset:5 mapsToLine:1 character:0 in:full];   // 'c'
}

- (void)testContentChangeEvent {
    FullTextStorage *full = [self storageWithString:@"abc\ndef"]; // a0 b1 c2 \n3 d4 e5 f6

    NSDictionary *change = [full lspContentChangeForRange:NSMakeRange(1, 2) replacementString:@"X"];
    XCTAssertEqualObjects(change[@"text"], @"X");
    XCTAssertEqualObjects(change[@"range"][@"start"], (@{@"line": @0, @"character": @1}));
    XCTAssertEqualObjects(change[@"range"][@"end"], (@{@"line": @0, @"character": @3}));

    // A deletion spanning the newline: "c\nd" = range {2,3}.
    NSDictionary *multi = [full lspContentChangeForRange:NSMakeRange(2, 3) replacementString:@""];
    XCTAssertEqualObjects(multi[@"range"][@"start"], (@{@"line": @0, @"character": @2}));
    XCTAssertEqualObjects(multi[@"range"][@"end"], (@{@"line": @1, @"character": @1}));
    XCTAssertEqualObjects(multi[@"text"], @"");
}

- (void)testEmptyAndTrailingNewline {
    FullTextStorage *empty = [self storageWithString:@""];
    [self assertOffset:0 mapsToLine:0 character:0 in:empty];

    FullTextStorage *trailing = [self storageWithString:@"x\n"];
    [self assertOffset:1 mapsToLine:0 character:1 in:trailing]; // before \n
    [self assertOffset:2 mapsToLine:1 character:0 in:trailing]; // synthetic empty last line
    XCTAssertEqual([trailing offsetForLSPLine:9 character:0], 2u); // line past end clamps to end
}

@end

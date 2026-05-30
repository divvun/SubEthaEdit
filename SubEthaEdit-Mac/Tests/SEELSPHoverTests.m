//  SEELSPHoverTests.m
//  SubEthaEdit

#import <XCTest/XCTest.h>
#import "NSStringSEEAdditions.h"
#import "FoldableTextStorage.h"
#import "FullTextStorage.h"
#import "SEELSPController.h"
#import "SEELSPMarkdownRenderer.h"

@interface SEELSPHoverTests : XCTestCase {
    NSMutableArray *_keepAlive;
}
@end

@implementation SEELSPHoverTests

- (void)setUp {
    _keepAlive = [NSMutableArray array];
}

- (FullTextStorage *)storageWithString:(NSString *)string {
    FoldableTextStorage *foldable = [[FoldableTextStorage alloc] init];
    [foldable replaceCharactersInRange:NSMakeRange(0, 0) withString:string];
    [_keepAlive addObject:foldable];
    return [foldable fullTextStorage];
}

- (NSFont *)fontAtIndex:(NSUInteger)index in:(NSAttributedString *)string {
    return [string attribute:NSFontAttributeName atIndex:index effectiveRange:NULL];
}

- (BOOL)font:(NSFont *)font hasTrait:(NSFontTraitMask)trait {
    return ([[NSFontManager sharedFontManager] traitsOfFont:font] & trait) != 0;
}

- (void)testPlaintextMarkupContent {
    NSAttributedString *s = [SEELSPMarkdownRenderer attributedStringFromHoverContents:@{@"kind": @"plaintext", @"value": @"hello world"}];
    XCTAssertEqualObjects(s.string, @"hello world");
    XCTAssertFalse([[self fontAtIndex:0 in:s] isFixedPitch]);
}

- (void)testMarkdownInlineCode {
    NSAttributedString *s = [SEELSPMarkdownRenderer attributedStringFromHoverContents:@{@"kind": @"markdown", @"value": @"call `foo()` now"}];
    XCTAssertEqualObjects(s.string, @"call foo() now");
    NSRange codeRange = [s.string rangeOfString:@"foo()"];
    XCTAssertTrue([[self fontAtIndex:codeRange.location in:s] isFixedPitch]);
    XCTAssertFalse([[self fontAtIndex:0 in:s] isFixedPitch]);
}

- (void)testMarkedStringDictionaryRendersAsCode {
    NSAttributedString *s = [SEELSPMarkdownRenderer attributedStringFromHoverContents:@{@"language": @"c", @"value": @"int x;"}];
    XCTAssertEqualObjects(s.string, @"int x;");
    XCTAssertTrue([[self fontAtIndex:0 in:s] isFixedPitch]);
}

- (void)testArrayContentsAreJoinedWithNewlines {
    NSAttributedString *s = [SEELSPMarkdownRenderer attributedStringFromHoverContents:@[@"alpha", @{@"language": @"c", @"value": @"beta"}]];
    XCTAssertEqualObjects(s.string, @"alpha\nbeta");
}

- (void)testFencedCodeBlockStripsFencesAndUsesCodeFont {
    NSAttributedString *s = [SEELSPMarkdownRenderer attributedStringFromMarkdown:@"before\n```\nint x;\n```\nafter"];
    XCTAssertEqualObjects(s.string, @"before\nint x;\nafter");
    NSRange codeRange = [s.string rangeOfString:@"int x;"];
    XCTAssertTrue([[self fontAtIndex:codeRange.location in:s] isFixedPitch]);
}

- (void)testBoldEmphasis {
    NSAttributedString *s = [SEELSPMarkdownRenderer attributedStringFromMarkdown:@"a **bold** b"];
    XCTAssertEqualObjects(s.string, @"a bold b");
    NSRange boldRange = [s.string rangeOfString:@"bold"];
    XCTAssertTrue([self font:[self fontAtIndex:boldRange.location in:s] hasTrait:NSBoldFontMask]);
}

- (void)testHoverRangeParsedFromResult {
    FullTextStorage *full = [self storageWithString:@"abc\ndef"];
    NSDictionary *result = @{
        @"contents": @"x",
        @"range": @{@"start": @{@"line": @1, @"character": @0}, @"end": @{@"line": @1, @"character": @3}},
    };
    NSRange r = [SEELSPController hoverFullRangeFromResult:result textStorage:full];
    XCTAssertTrue(NSEqualRanges(r, NSMakeRange(4, 3)));
}

- (void)testHoverRangeAbsentWhenNoRangeKey {
    FullTextStorage *full = [self storageWithString:@"abc"];
    NSRange r = [SEELSPController hoverFullRangeFromResult:@{@"contents": @"x"} textStorage:full];
    XCTAssertEqual(r.location, (NSUInteger)NSNotFound);
}

@end

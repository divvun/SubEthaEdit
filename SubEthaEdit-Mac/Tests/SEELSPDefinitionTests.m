//  SEELSPDefinitionTests.m
//  SubEthaEdit

#import <XCTest/XCTest.h>
#import "NSStringSEEAdditions.h"
#import "FoldableTextStorage.h"
#import "FullTextStorage.h"
#import "SEELSPController.h"

@interface SEELSPDefinitionTests : XCTestCase {
    NSMutableArray *_keepAlive;
}
@end

@implementation SEELSPDefinitionTests

- (void)setUp {
    _keepAlive = [NSMutableArray array];
}

- (FullTextStorage *)storageWithString:(NSString *)string {
    FoldableTextStorage *foldable = [[FoldableTextStorage alloc] init];
    [foldable replaceCharactersInRange:NSMakeRange(0, 0) withString:string];
    [_keepAlive addObject:foldable];
    return [foldable fullTextStorage];
}

- (NSDictionary *)lspRangeFromLine:(NSUInteger)startLine character:(NSUInteger)startCharacter
        toLine:(NSUInteger)endLine character:(NSUInteger)endCharacter {
    return @{
        @"start": @{@"line": @(startLine), @"character": @(startCharacter)},
        @"end": @{@"line": @(endLine), @"character": @(endCharacter)},
    };
}

- (void)testSingleLocation {
    NSDictionary *location = @{@"uri": @"file:///a.c", @"range": [self lspRangeFromLine:2 character:4 toLine:2 character:9]};
    NSArray *targets = [SEELSPController definitionTargetsFromResult:location];
    XCTAssertEqual(targets.count, 1u);
    XCTAssertEqualObjects(targets[0][@"uri"], @"file:///a.c");
    XCTAssertEqualObjects(targets[0][@"range"][@"start"][@"line"], @2);
}

- (void)testLocationArray {
    NSArray *locations = @[
        @{@"uri": @"file:///a.c", @"range": [self lspRangeFromLine:0 character:0 toLine:0 character:1]},
        @{@"uri": @"file:///b.c", @"range": [self lspRangeFromLine:5 character:2 toLine:5 character:3]},
    ];
    NSArray *targets = [SEELSPController definitionTargetsFromResult:locations];
    XCTAssertEqual(targets.count, 2u);
    XCTAssertEqualObjects(targets[1][@"uri"], @"file:///b.c");
}

- (void)testLocationLinkPrefersTargetSelectionRange {
    NSArray *links = @[@{
        @"targetUri": @"file:///c.c",
        @"targetRange": [self lspRangeFromLine:10 character:0 toLine:14 character:1],
        @"targetSelectionRange": [self lspRangeFromLine:10 character:8 toLine:10 character:11],
    }];
    NSArray *targets = [SEELSPController definitionTargetsFromResult:links];
    XCTAssertEqual(targets.count, 1u);
    XCTAssertEqualObjects(targets[0][@"uri"], @"file:///c.c");
    XCTAssertEqualObjects(targets[0][@"range"][@"start"][@"character"], @8);
}

- (void)testLocationLinkFallsBackToTargetRange {
    NSArray *links = @[@{
        @"targetUri": @"file:///d.c",
        @"targetRange": [self lspRangeFromLine:3 character:0 toLine:3 character:5],
    }];
    NSArray *targets = [SEELSPController definitionTargetsFromResult:links];
    XCTAssertEqual(targets.count, 1u);
    XCTAssertEqualObjects(targets[0][@"range"][@"start"][@"line"], @3);
}

- (void)testNullAndMalformedYieldEmpty {
    XCTAssertEqual([SEELSPController definitionTargetsFromResult:[NSNull null]].count, 0u);
    XCTAssertEqual([SEELSPController definitionTargetsFromResult:@[]].count, 0u);
    XCTAssertEqual([SEELSPController definitionTargetsFromResult:@[@{@"range": [self lspRangeFromLine:0 character:0 toLine:0 character:1]}]].count, 0u);
}

- (void)testFullTextRangeForLSPRange {
    FullTextStorage *full = [self storageWithString:@"abc\ndefgh\nij"];
    NSRange r = [SEELSPController fullTextRangeForLSPRange:[self lspRangeFromLine:1 character:1 toLine:1 character:4] textStorage:full];
    XCTAssertTrue(NSEqualRanges(r, NSMakeRange(5, 3)));
}

@end

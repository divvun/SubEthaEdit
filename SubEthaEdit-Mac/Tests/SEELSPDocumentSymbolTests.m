//  SEELSPDocumentSymbolTests.m
//  SubEthaEdit

#import <XCTest/XCTest.h>
#import "NSStringSEEAdditions.h"
#import "FoldableTextStorage.h"
#import "FullTextStorage.h"
#import "SEELSPController.h"
#import "SymbolTableEntry.h"

@interface SEELSPDocumentSymbolTests : XCTestCase {
    NSMutableArray *_keepAlive;
}
@end

@implementation SEELSPDocumentSymbolTests

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

- (void)testHierarchicalDocumentSymbolsFlattenWithIndentation {
    FullTextStorage *full = [self storageWithString:@"class Foo {\n  void a() {}\n  void b() {}\n}"];
    NSArray *result = @[
        @{ @"name": @"Foo", @"kind": @5,
           @"range": [self lspRangeFromLine:0 character:0 toLine:3 character:1],
           @"selectionRange": [self lspRangeFromLine:0 character:6 toLine:0 character:9],
           @"children": @[
               @{ @"name": @"a", @"kind": @6,
                  @"range": [self lspRangeFromLine:1 character:2 toLine:1 character:13],
                  @"selectionRange": [self lspRangeFromLine:1 character:7 toLine:1 character:8] },
               @{ @"name": @"b", @"kind": @6,
                  @"range": [self lspRangeFromLine:2 character:2 toLine:2 character:13],
                  @"selectionRange": [self lspRangeFromLine:2 character:7 toLine:2 character:8] },
           ] },
    ];

    NSArray *entries = [SEELSPController symbolTableEntriesFromDocumentSymbolResult:result textStorage:full];
    XCTAssertEqual(entries.count, 3u);

    SymbolTableEntry *foo = entries[0];
    XCTAssertEqualObjects(foo.name, @"Foo");
    XCTAssertEqual(foo.indentationLevel, 0);
    XCTAssertTrue(NSEqualRanges([foo range], NSMakeRange(0, 41)));
    XCTAssertTrue(NSEqualRanges([foo jumpRange], NSMakeRange(6, 3)));

    SymbolTableEntry *a = entries[1];
    XCTAssertEqualObjects(a.name, @"a");
    XCTAssertEqual(a.indentationLevel, 1);
    XCTAssertTrue(NSEqualRanges([a range], NSMakeRange(14, 11)));
    XCTAssertTrue(NSEqualRanges([a jumpRange], NSMakeRange(19, 1)));

    SymbolTableEntry *b = entries[2];
    XCTAssertEqualObjects(b.name, @"b");
    XCTAssertEqual(b.indentationLevel, 1);
    XCTAssertTrue(NSEqualRanges([b range], NSMakeRange(28, 11)));
    XCTAssertTrue(NSEqualRanges([b jumpRange], NSMakeRange(33, 1)));
}

- (void)testFlatSymbolInformationUsesLocationRange {
    FullTextStorage *full = [self storageWithString:@"class Foo {\n  void a() {}\n  void b() {}\n}"];
    NSArray *result = @[
        @{ @"name": @"a", @"kind": @12,
           @"location": @{ @"uri": @"file:///x.c",
                           @"range": [self lspRangeFromLine:1 character:7 toLine:1 character:8] } },
    ];

    NSArray *entries = [SEELSPController symbolTableEntriesFromDocumentSymbolResult:result textStorage:full];
    XCTAssertEqual(entries.count, 1u);
    SymbolTableEntry *a = entries[0];
    XCTAssertEqualObjects(a.name, @"a");
    XCTAssertEqual(a.indentationLevel, 0);
    XCTAssertTrue(NSEqualRanges([a range], NSMakeRange(19, 1)));
    XCTAssertTrue(NSEqualRanges([a jumpRange], NSMakeRange(19, 1)));
}

- (void)testMalformedEntriesAreSkipped {
    FullTextStorage *full = [self storageWithString:@"abcdef"];
    NSArray *result = @[
        @{ @"kind": @5, @"range": [self lspRangeFromLine:0 character:0 toLine:0 character:3] },
        @{ @"name": @"", @"kind": @5, @"range": [self lspRangeFromLine:0 character:0 toLine:0 character:3] },
        @{ @"name": @"ok", @"kind": @12, @"range": [self lspRangeFromLine:0 character:0 toLine:0 character:5] },
        @"not a dictionary",
    ];

    NSArray *entries = [SEELSPController symbolTableEntriesFromDocumentSymbolResult:result textStorage:full];
    XCTAssertEqual(entries.count, 1u);
    XCTAssertEqualObjects([entries[0] name], @"ok");
    XCTAssertTrue(NSEqualRanges([entries[0] range], NSMakeRange(0, 5)));
}

- (void)testEmptyResultYieldsEmptyArray {
    FullTextStorage *full = [self storageWithString:@"abc"];
    NSArray *entries = [SEELSPController symbolTableEntriesFromDocumentSymbolResult:@[] textStorage:full];
    XCTAssertNotNil(entries);
    XCTAssertEqual(entries.count, 0u);
}

@end

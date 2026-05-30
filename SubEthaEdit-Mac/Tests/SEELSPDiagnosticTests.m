//  SEELSPDiagnosticTests.m
//  SubEthaEdit

#import <XCTest/XCTest.h>
#import "NSStringSEEAdditions.h"
#import "FoldableTextStorage.h"
#import "FullTextStorage.h"
#import "SEELSPDiagnostic.h"
#import "SEELSPController.h"

@interface SEELSPDiagnosticTests : XCTestCase {
    NSMutableArray *_keepAlive;
}
@end

@implementation SEELSPDiagnosticTests

- (void)setUp {
    _keepAlive = [NSMutableArray array];
}

- (FullTextStorage *)storageWithString:(NSString *)string {
    FoldableTextStorage *foldable = [[FoldableTextStorage alloc] init];
    [foldable replaceCharactersInRange:NSMakeRange(0, 0) withString:string];
    [_keepAlive addObject:foldable];
    return [foldable fullTextStorage];
}

- (NSDictionary *)diagnosticAtStartLine:(NSUInteger)sl character:(NSUInteger)sc endLine:(NSUInteger)el character:(NSUInteger)ec extra:(NSDictionary *)extra {
    NSMutableDictionary *d = [@{ @"range": @{ @"start": @{@"line": @(sl), @"character": @(sc)},
                                              @"end": @{@"line": @(el), @"character": @(ec)} },
                                @"message": @"oops" } mutableCopy];
    [d addEntriesFromDictionary:extra];
    return d;
}

- (void)testParsesRangesSeverityAndFields {
    FullTextStorage *full = [self storageWithString:@"abc\ndef"]; // a0 b1 c2 \n3 d4 e5 f6
    NSDictionary *params = @{@"uri": @"file:///x", @"diagnostics": @[
        [self diagnosticAtStartLine:0 character:1 endLine:0 character:3 extra:@{@"severity": @2, @"source": @"clang", @"code": @"W1"}],
        [self diagnosticAtStartLine:1 character:0 endLine:1 character:3 extra:@{}],
    ]};
    NSArray<SEELSPDiagnostic *> *diagnostics = [SEELSPDiagnostic diagnosticsFromPublishParams:params textStorage:full];

    XCTAssertEqual(diagnostics.count, 2u);
    XCTAssertTrue(NSEqualRanges(diagnostics[0].fullRange, NSMakeRange(1, 2)));
    XCTAssertEqual(diagnostics[0].severity, SEELSPDiagnosticSeverityWarning);
    XCTAssertEqualObjects(diagnostics[0].message, @"oops");
    XCTAssertEqualObjects(diagnostics[0].source, @"clang");
    XCTAssertEqualObjects(diagnostics[0].code, @"W1");
    XCTAssertTrue(NSEqualRanges(diagnostics[1].fullRange, NSMakeRange(4, 3)));
}

- (void)testDefaultsToErrorWhenSeverityMissing {
    FullTextStorage *full = [self storageWithString:@"abc"];
    NSDictionary *params = @{@"diagnostics": @[[self diagnosticAtStartLine:0 character:0 endLine:0 character:1 extra:@{}]]};
    NSArray<SEELSPDiagnostic *> *diagnostics = [SEELSPDiagnostic diagnosticsFromPublishParams:params textStorage:full];
    XCTAssertEqual(diagnostics.count, 1u);
    XCTAssertEqual(diagnostics[0].severity, SEELSPDiagnosticSeverityError);
}

- (void)testSkipsMalformedAndHandlesEmpty {
    FullTextStorage *full = [self storageWithString:@"abc"];
    XCTAssertEqual([SEELSPDiagnostic diagnosticsFromPublishParams:@{@"diagnostics": @[]} textStorage:full].count, 0u);
    XCTAssertEqual([SEELSPDiagnostic diagnosticsFromPublishParams:@{} textStorage:full].count, 0u);
    NSDictionary *malformed = @{@"diagnostics": @[@{@"message": @"no range"}, @"not a dict"]};
    XCTAssertEqual([SEELSPDiagnostic diagnosticsFromPublishParams:malformed textStorage:full].count, 0u);
}

- (NSArray<SEELSPDiagnostic *> *)diagnosticsWithSeverities:(NSArray<NSNumber *> *)severities {
    FullTextStorage *full = [self storageWithString:@"abc"];
    NSMutableArray *items = [NSMutableArray array];
    for (NSNumber *severity in severities) {
        [items addObject:[self diagnosticAtStartLine:0 character:0 endLine:0 character:1 extra:@{@"severity": severity}]];
    }
    return [SEELSPDiagnostic diagnosticsFromPublishParams:@{@"diagnostics": items} textStorage:full];
}

- (void)testHighestSeverityPicksMostSevere {
    SEELSPDiagnosticSeverity warningWins = [SEELSPController highestSeverityInDiagnostics:[self diagnosticsWithSeverities:@[@4, @2, @3]]];
    SEELSPDiagnosticSeverity errorWins = [SEELSPController highestSeverityInDiagnostics:[self diagnosticsWithSeverities:@[@3, @1, @2]]];
    SEELSPDiagnosticSeverity hintOnly = [SEELSPController highestSeverityInDiagnostics:[self diagnosticsWithSeverities:@[@4]]];
    XCTAssertEqual(warningWins, SEELSPDiagnosticSeverityWarning);
    XCTAssertEqual(errorWins, SEELSPDiagnosticSeverityError);
    XCTAssertEqual(hintOnly, SEELSPDiagnosticSeverityHint);
}

- (void)testHighestSeverityHandlesEmpty {
    XCTAssertEqual([SEELSPController highestSeverityInDiagnostics:@[]], SEELSPDiagnosticSeverityHint);
}

- (void)testAttributedStringContainsMessagesAndJoinsLines {
    FullTextStorage *full = [self storageWithString:@"abc"];
    NSArray *params = @[
        [self diagnosticAtStartLine:0 character:0 endLine:0 character:1 extra:@{@"severity": @1, @"message": @"first", @"source": @"clang", @"code": @"E1"}],
        [self diagnosticAtStartLine:0 character:0 endLine:0 character:1 extra:@{@"severity": @2, @"message": @"second"}],
    ];
    NSArray<SEELSPDiagnostic *> *diagnostics = [SEELSPDiagnostic diagnosticsFromPublishParams:@{@"diagnostics": params} textStorage:full];
    NSAttributedString *attributed = [SEELSPController attributedStringForDiagnostics:diagnostics];
    NSString *string = attributed.string;

    XCTAssertTrue([string containsString:@"first"]);
    XCTAssertTrue([string containsString:@"second"]);
    XCTAssertTrue([string containsString:@"clang: E1"]);
    XCTAssertEqual([[string componentsSeparatedByString:@"\n"] count], 2u);

    NSColor *labelColor = [attributed attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
    XCTAssertEqualObjects(labelColor, [SEELSPController colorForSeverity:SEELSPDiagnosticSeverityError]);
}

@end

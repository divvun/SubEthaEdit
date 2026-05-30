//  SEELSPCompletionTests.m
//  SubEthaEdit

#import <XCTest/XCTest.h>
#import "SEELSPController.h"

@interface SEELSPCompletionTests : XCTestCase
@end

@implementation SEELSPCompletionTests

- (void)testCompletionItemArrayUsesLabelWhenNoInsertText {
    NSArray *result = @[
        @{@"label": @"alpha"},
        @{@"label": @"beta"},
    ];
    NSArray *strings = [SEELSPController completionStringsFromResult:result];
    XCTAssertEqualObjects(strings, (@[@"alpha", @"beta"]));
}

- (void)testCompletionListDictUnwrapsItems {
    NSDictionary *result = @{@"isIncomplete": @YES, @"items": @[@{@"label": @"gamma"}]};
    NSArray *strings = [SEELSPController completionStringsFromResult:result];
    XCTAssertEqualObjects(strings, (@[@"gamma"]));
}

- (void)testInsertTextPreferredOverLabel {
    NSArray *result = @[@{@"label": @"foo(…)", @"insertText": @"foo"}];
    NSArray *strings = [SEELSPController completionStringsFromResult:result];
    XCTAssertEqualObjects(strings, (@[@"foo"]));
}

- (void)testSnippetInsertTextFallsBackToLabel {
    NSArray *result = @[@{@"label": @"foo", @"insertText": @"foo(${1:bar})", @"insertTextFormat": @2}];
    NSArray *strings = [SEELSPController completionStringsFromResult:result];
    XCTAssertEqualObjects(strings, (@[@"foo"]));
}

- (void)testSortTextOrdersResults {
    NSArray *result = @[
        @{@"label": @"zebra", @"sortText": @"0001"},
        @{@"label": @"apple", @"sortText": @"0002"},
    ];
    NSArray *strings = [SEELSPController completionStringsFromResult:result];
    XCTAssertEqualObjects(strings, (@[@"zebra", @"apple"]));
}

- (void)testStableOrderWhenSortTextEqual {
    NSArray *result = @[
        @{@"label": @"first", @"sortText": @"x"},
        @{@"label": @"second", @"sortText": @"x"},
    ];
    NSArray *strings = [SEELSPController completionStringsFromResult:result];
    XCTAssertEqualObjects(strings, (@[@"first", @"second"]));
}

- (void)testDuplicatesAreRemoved {
    NSArray *result = @[
        @{@"label": @"dup"},
        @{@"label": @"dup"},
        @{@"label": @"unique"},
    ];
    NSArray *strings = [SEELSPController completionStringsFromResult:result];
    XCTAssertEqualObjects(strings, (@[@"dup", @"unique"]));
}

- (void)testMalformedEntriesSkipped {
    NSArray *result = @[
        @"not a dictionary",
        @{@"detail": @"no label or insert"},
        @{@"label": @"ok"},
    ];
    NSArray *strings = [SEELSPController completionStringsFromResult:result];
    XCTAssertEqualObjects(strings, (@[@"ok"]));
}

- (void)testNullResultYieldsEmpty {
    XCTAssertEqual([SEELSPController completionStringsFromResult:[NSNull null]].count, 0u);
    XCTAssertEqual([SEELSPController completionStringsFromResult:@{}].count, 0u);
}

@end

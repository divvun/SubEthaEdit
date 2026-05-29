//  SEELSPServerConfigurationTests.m
//  SubEthaEdit

#import <XCTest/XCTest.h>
#import "SEELSPServerConfiguration.h"

@interface SEELSPServerConfigurationTests : XCTestCase
@end

@implementation SEELSPServerConfigurationTests

- (NSData *)dummyBookmark {
    return [@"bookmark" dataUsingEncoding:NSUTF8StringEncoding];
}

- (void)testNilWhenNothingProvided {
    XCTAssertNil([SEELSPServerConfiguration configurationWithBundleDefaults:nil override:nil]);
    XCTAssertNil([SEELSPServerConfiguration configurationWithBundleDefaults:@{} override:@{}]);
}

- (void)testBundleDisabledIsNotStartable {
    SEELSPServerConfiguration *config = [SEELSPServerConfiguration configurationWithBundleDefaults:@{@"Enabled": @NO, @"LanguageId": @"c"} override:nil];
    XCTAssertNotNil(config);
    XCTAssertFalse(config.isEnabled);
    XCTAssertFalse(config.isStartable);
    XCTAssertEqualObjects(config.languageId, @"c");
}

- (void)testEnabledWithoutBookmarkIsNotStartable {
    SEELSPServerConfiguration *config = [SEELSPServerConfiguration configurationWithBundleDefaults:@{@"Enabled": @YES} override:nil];
    XCTAssertTrue(config.isEnabled);
    XCTAssertNil(config.executableBookmark);
    XCTAssertFalse(config.isStartable);
}

- (void)testOverrideEnablesAndSuppliesBookmark {
    NSDictionary *bundle = @{@"Enabled": @NO, @"LanguageId": @"c", @"Arguments": @[@"--from-bundle"]};
    NSDictionary *override = @{@"Enabled": @YES, @"ExecutableBookmark": [self dummyBookmark], @"Arguments": @[@"--background-index"]};
    SEELSPServerConfiguration *config = [SEELSPServerConfiguration configurationWithBundleDefaults:bundle override:override];
    XCTAssertTrue(config.isEnabled);
    XCTAssertTrue(config.isStartable);
    XCTAssertEqualObjects(config.arguments, (@[@"--background-index"])); // override wins
    XCTAssertEqualObjects(config.languageId, @"c");                       // languageId from bundle
}

- (void)testOverrideCanDisableABundleEnabledServer {
    NSDictionary *bundle = @{@"Enabled": @YES};
    NSDictionary *override = @{@"Enabled": @NO, @"ExecutableBookmark": [self dummyBookmark]};
    SEELSPServerConfiguration *config = [SEELSPServerConfiguration configurationWithBundleDefaults:bundle override:override];
    XCTAssertFalse(config.isEnabled);
    XCTAssertFalse(config.isStartable);
}

@end

//  SEELSPPreferencesTests.m
//  SubEthaEdit

#import <XCTest/XCTest.h>
#import "SEELSPPreferences.h"
#import "SEELSPServerConfiguration.h"

@interface SEELSPPreferencesTests : XCTestCase
@end

@implementation SEELSPPreferencesTests

- (void)testArgumentsFromStringSplitsAndTrims {
    NSArray *args = [SEELSPPreferences argumentsFromString:@"  --background-index   --log=verbose "];
    XCTAssertEqualObjects(args, (@[@"--background-index", @"--log=verbose"]));
}

- (void)testArgumentsFromEmptyStringIsEmpty {
    XCTAssertEqualObjects([SEELSPPreferences argumentsFromString:@""], (@[]));
    XCTAssertEqualObjects([SEELSPPreferences argumentsFromString:@"   "], (@[]));
}

- (void)testArgumentsRoundTrip {
    NSArray *args = @[@"-a", @"-b", @"-c"];
    XCTAssertEqualObjects([SEELSPPreferences argumentsFromString:[SEELSPPreferences stringFromArguments:args]], args);
}

- (void)testEnvironmentFromStringParsesLines {
    NSDictionary *env = [SEELSPPreferences environmentFromString:@"PATH=/usr/bin\nRUST_LOG=info"];
    XCTAssertEqualObjects(env, (@{@"PATH": @"/usr/bin", @"RUST_LOG": @"info"}));
}

- (void)testEnvironmentSkipsBlankAndMalformedLines {
    NSDictionary *env = [SEELSPPreferences environmentFromString:@"PATH=/usr/bin\n\nnoequalshere\n  KEY = value with spaces  "];
    XCTAssertEqualObjects(env, (@{@"PATH": @"/usr/bin", @"KEY": @"value with spaces"}));
}

- (void)testEnvironmentRoundTripIsSortedStable {
    NSString *string = [SEELSPPreferences stringFromEnvironment:@{@"ZED": @"1", @"alpha": @"2"}];
    XCTAssertEqualObjects(string, @"alpha=2\nZED=1");
    XCTAssertEqualObjects([SEELSPPreferences environmentFromString:string], (@{@"ZED": @"1", @"alpha": @"2"}));
}

- (void)testApplyBuildsOverrideAndRoundTripsThroughConfiguration {
    NSData *bookmark = [@"bm" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *modeDefaults = [SEELSPPreferences modeDefaultsByApplyingEnabled:YES
            arguments:@[@"--x"]
            environment:@{@"K": @"V"}
            bookmark:bookmark
            toModeDefaults:@{}];
    NSDictionary *override = modeDefaults[@"SEELanguageServerOverride"];
    SEELSPServerConfiguration *config = [SEELSPServerConfiguration configurationWithBundleDefaults:@{} override:override];
    XCTAssertTrue(config.isEnabled);
    XCTAssertEqualObjects(config.arguments, (@[@"--x"]));
    XCTAssertEqualObjects(config.environment, (@{@"K": @"V"}));
    XCTAssertEqualObjects(config.executableBookmark, bookmark);
    XCTAssertTrue(config.isStartable);
}

- (void)testApplyWithoutBookmarkIsNotStartable {
    NSDictionary *modeDefaults = [SEELSPPreferences modeDefaultsByApplyingEnabled:YES
            arguments:@[]
            environment:@{}
            bookmark:nil
            toModeDefaults:@{}];
    NSDictionary *override = modeDefaults[@"SEELanguageServerOverride"];
    SEELSPServerConfiguration *config = [SEELSPServerConfiguration configurationWithBundleDefaults:@{} override:override];
    XCTAssertTrue(config.isEnabled);
    XCTAssertNil(config.executableBookmark);
    XCTAssertFalse(config.isStartable);
}

- (void)testApplyPreservesOtherModeKeysAndClearsStaleBookmark {
    NSData *bookmark = [@"bm" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *existing = @{
        @"SomeOtherModeKey": @"keepme",
        @"SEELanguageServerOverride": @{@"ExecutableBookmark": bookmark, @"Enabled": @YES},
    };
    NSDictionary *modeDefaults = [SEELSPPreferences modeDefaultsByApplyingEnabled:NO
            arguments:@[]
            environment:@{}
            bookmark:nil
            toModeDefaults:existing];
    XCTAssertEqualObjects(modeDefaults[@"SomeOtherModeKey"], @"keepme");
    NSDictionary *override = modeDefaults[@"SEELanguageServerOverride"];
    XCTAssertNil(override[@"ExecutableBookmark"]);
    XCTAssertEqualObjects(override[@"Enabled"], @NO);
}

@end

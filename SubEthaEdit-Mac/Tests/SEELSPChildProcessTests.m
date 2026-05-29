//  SEELSPChildProcessTests.m
//  SubEthaEdit

#import <XCTest/XCTest.h>
#import "SEELSPChildProcess.h"

@interface SEELSPChildProcessTests : XCTestCase
@end

@implementation SEELSPChildProcessTests

- (SEELSPChildProcess *)catProcess {
    return [[SEELSPChildProcess alloc] initWithExecutableURL:[NSURL fileURLWithPath:@"/bin/cat"]
                                                  arguments:@[]
                                                environment:nil];
}

- (void)testRoundTripsNotificationThroughCat {
    SEELSPChildProcess *child = [self catProcess];
    XCTestExpectation *echoed = [self expectationWithDescription:@"notification echoed back"];
    __block NSString *capturedMethod = nil;
    __block id capturedParams = nil;
    child.notificationHandler = ^(NSString *method, id params) {
        capturedMethod = method;
        capturedParams = params;
        [echoed fulfill];
    };

    NSError *error = nil;
    XCTAssertTrue([child launchAndReturnError:&error], @"cat failed to launch: %@", error);

    [child sendNotificationMethod:@"test/echo" params:@{@"value": @42, @"items": @[@"a", @"b"]}];

    [self waitForExpectations:@[echoed] timeout:5.0];
    XCTAssertEqualObjects(capturedMethod, @"test/echo");
    XCTAssertEqualObjects(capturedParams, (@{@"value": @42, @"items": @[@"a", @"b"]}));
    [child terminate];
}

- (void)testRoundTripsMultipleNotifications {
    SEELSPChildProcess *child = [self catProcess];
    XCTestExpectation *gotBoth = [self expectationWithDescription:@"both notifications echoed"];
    NSMutableArray<NSString *> *methods = [NSMutableArray array];
    child.notificationHandler = ^(NSString *method, id params) {
        @synchronized (methods) {
            [methods addObject:method];
            if (methods.count == 2) { [gotBoth fulfill]; }
        }
    };

    NSError *error = nil;
    XCTAssertTrue([child launchAndReturnError:&error], @"cat failed to launch: %@", error);
    [child sendNotificationMethod:@"first" params:nil];
    [child sendNotificationMethod:@"second" params:nil];

    [self waitForExpectations:@[gotBoth] timeout:5.0];
    @synchronized (methods) {
        XCTAssertEqualObjects(methods[0], @"first");
        XCTAssertEqualObjects(methods[1], @"second");
    }
    [child terminate];
}

- (void)testInitializeHandshakeAgainstClangd {
    NSString *clangdPath = @"/usr/bin/clangd";
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:clangdPath]) {
        XCTSkip(@"clangd not available at %@", clangdPath);
    }

    SEELSPChildProcess *child = [[SEELSPChildProcess alloc] initWithExecutableURL:[NSURL fileURLWithPath:clangdPath]
                                                                        arguments:@[]
                                                                      environment:nil];
    XCTestExpectation *handshook = [self expectationWithDescription:@"clangd initialize handshake completes"];
    __block NSDictionary *capabilities = nil;
    __block NSError *handshakeError = nil;

    NSDictionary *params = @{
        @"processId": @((NSInteger)[[NSProcessInfo processInfo] processIdentifier]),
        @"rootUri": [NSNull null],
        @"capabilities": @{},
    };
    [child launchAndInitializeWithParams:params timeout:10.0 reply:^(NSDictionary *caps, NSError *error) {
        capabilities = caps;
        handshakeError = error;
        [handshook fulfill];
    }];

    [self waitForExpectations:@[handshook] timeout:15.0];
    XCTAssertNil(handshakeError, @"initialize handshake failed: %@", handshakeError);
    XCTAssertNotNil(capabilities);
    XCTAssertNotNil(capabilities[@"textDocumentSync"], @"clangd should advertise textDocumentSync");
    [child terminate];
}

- (void)testTerminationHandlerFiresOnTerminate {
    SEELSPChildProcess *child = [self catProcess];
    XCTestExpectation *terminated = [self expectationWithDescription:@"termination handler fires"];
    child.terminationHandler = ^(int status) {
        [terminated fulfill];
    };

    NSError *error = nil;
    XCTAssertTrue([child launchAndReturnError:&error], @"cat failed to launch: %@", error);
    XCTAssertTrue(child.isRunning);
    [child terminate];

    [self waitForExpectations:@[terminated] timeout:5.0];
}

@end

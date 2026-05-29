//  SEELSPServerSessionTests.m
//  SubEthaEdit

#import <XCTest/XCTest.h>
#import "SEELSPServerSession.h"

@interface SEELSPServerSessionTests : XCTestCase
@end

@implementation SEELSPServerSessionTests

- (NSDictionary *)minimalInitializeParams {
    return @{ @"processId": @((NSInteger)[[NSProcessInfo processInfo] processIdentifier]),
              @"rootUri": [NSNull null],
              @"capabilities": @{} };
}

- (void)testRestartsOnCrashThenTripsCircuitBreaker {
    SEELSPServerSession *session = [[SEELSPServerSession alloc] initWithExecutableURL:[NSURL fileURLWithPath:@"/usr/bin/false"]
                                                                           arguments:@[]
                                                                         environment:nil
                                                                    initializeParams:[self minimalInitializeParams]];
    session.initializeTimeout = 1.0;
    session.restartBackoffBase = 0.01;
    session.restartBackoffCap = 0.05;
    session.maxRestartsPerWindow = 3;
    session.restartWindow = 60.0;

    XCTestExpectation *gaveUp = [self expectationWithDescription:@"circuit breaker trips after the allowed restarts"];
    __block NSUInteger launchCount = 0;
    __block NSUInteger crashCount = 0;
    __block BOOL fulfilled = NO;
    NSObject *lock = [NSObject new];
    session.stateChangeHandler = ^(SEELSPServerState state) {
        @synchronized (lock) {
            if (state == SEELSPServerStateLaunching) { launchCount++; }
            if (state == SEELSPServerStateCrashed) {
                crashCount++;
                if (crashCount == session.maxRestartsPerWindow + 1 && !fulfilled) {
                    fulfilled = YES;
                    [gaveUp fulfill];
                }
            }
        }
    };

    [session start];
    [self waitForExpectations:@[gaveUp] timeout:10.0];

    // The (maxRestarts + 1)th crash trips the breaker, so there is no further launch.
    [NSThread sleepForTimeInterval:0.2];
    @synchronized (lock) {
        XCTAssertEqual(launchCount, session.maxRestartsPerWindow + 1);
        XCTAssertEqual(crashCount, session.maxRestartsPerWindow + 1);
    }
    XCTAssertEqual(session.state, SEELSPServerStateCrashed);
}

- (void)testStartsAndShutsDownCleanlyWithClangd {
    NSString *clangdPath = @"/usr/bin/clangd";
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:clangdPath]) {
        XCTSkip(@"clangd not available at %@", clangdPath);
    }

    SEELSPServerSession *session = [[SEELSPServerSession alloc] initWithExecutableURL:[NSURL fileURLWithPath:clangdPath]
                                                                           arguments:@[]
                                                                         environment:nil
                                                                    initializeParams:[self minimalInitializeParams]];

    XCTestExpectation *running = [self expectationWithDescription:@"reaches Running"];
    XCTestExpectation *stopped = [self expectationWithDescription:@"reaches Stopped"];
    __block BOOL didRunning = NO;
    __block BOOL didStopped = NO;
    session.stateChangeHandler = ^(SEELSPServerState state) {
        if (state == SEELSPServerStateRunning && !didRunning) { didRunning = YES; [running fulfill]; }
        if (state == SEELSPServerStateStopped && !didStopped) { didStopped = YES; [stopped fulfill]; }
    };

    [session start];
    [self waitForExpectations:@[running] timeout:15.0];
    XCTAssertEqual(session.state, SEELSPServerStateRunning);

    [session shutdown];
    [self waitForExpectations:@[stopped] timeout:10.0];
    XCTAssertEqual(session.state, SEELSPServerStateStopped);
}

@end

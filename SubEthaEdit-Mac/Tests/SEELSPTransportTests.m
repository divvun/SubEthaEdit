//  SEELSPTransportTests.m
//  SubEthaEdit
//
//  Unit tests for the LSP transport primitives (framing reader/writer + JSON-RPC
//  coordinator). These exercise the byte-level framing state machine directly, which is
//  the part the rest of the LSP feature depends on.

#import <XCTest/XCTest.h>
#import "SEELSPMessageReader.h"
#import "SEELSPMessageWriter.h"
#import "SEELSPRPCCoordinator.h"

@interface SEELSPTransportTests : XCTestCase
@end

@implementation SEELSPTransportTests

#pragma mark - Helpers

- (NSData *)dataFromString:(NSString *)string {
    return [string dataUsingEncoding:NSUTF8StringEncoding];
}

// Collect every message body the reader emits for the supplied chunks.
- (NSArray<NSData *> *)bodiesByFeeding:(NSArray<NSData *> *)chunks toReader:(SEELSPMessageReader *)reader {
    NSMutableArray<NSData *> *bodies = [NSMutableArray array];
    reader.messageHandler = ^(NSData *jsonBody) {
        [bodies addObject:jsonBody];
    };
    for (NSData *chunk in chunks) {
        [reader appendData:chunk];
    }
    return bodies;
}

#pragma mark - Writer

- (void)testWriterFramesContentLengthAndBody {
    NSError *error = nil;
    NSData *framed = [SEELSPMessageWriter framedDataForJSONObject:@{@"jsonrpc": @"2.0", @"method": @"initialized"} error:&error];
    XCTAssertNotNil(framed);
    XCTAssertNil(error);

    NSString *framedString = [[NSString alloc] initWithData:framed encoding:NSUTF8StringEncoding];
    NSRange separator = [framedString rangeOfString:@"\r\n\r\n"];
    XCTAssertNotEqual(separator.location, (NSUInteger)NSNotFound, @"framing must contain a header/body separator");

    NSString *header = [framedString substringToIndex:separator.location];
    NSString *body = [framedString substringFromIndex:NSMaxRange(separator)];
    XCTAssertEqualObjects(header, ([NSString stringWithFormat:@"Content-Length: %lu", (unsigned long)[[self dataFromString:body] length]]));
}

- (void)testWriterRejectsNonJSONObject {
    NSError *error = nil;
    NSData *framed = [SEELSPMessageWriter framedDataForJSONObject:[NSDate date] error:&error];
    XCTAssertNil(framed);
    XCTAssertNotNil(error);
}

#pragma mark - Reader

- (void)testReaderParsesSingleMessageInOneChunk {
    SEELSPMessageReader *reader = [SEELSPMessageReader new];
    NSData *body = [self dataFromString:@"{\"jsonrpc\":\"2.0\"}"];
    NSData *framed = [SEELSPMessageWriter framedDataForJSONBody:body];

    NSArray<NSData *> *bodies = [self bodiesByFeeding:@[framed] toReader:reader];
    XCTAssertEqual([bodies count], 1u);
    XCTAssertEqualObjects(bodies.firstObject, body);
}

- (void)testReaderReassemblesMessageSplitAcrossChunks {
    SEELSPMessageReader *reader = [SEELSPMessageReader new];
    NSData *body = [self dataFromString:@"{\"hello\":\"world\"}"];
    NSData *framed = [SEELSPMessageWriter framedDataForJSONBody:body];

    // Split at every single byte to stress the carry-over logic.
    NSMutableArray<NSData *> *chunks = [NSMutableArray array];
    for (NSUInteger i = 0; i < [framed length]; i++) {
        [chunks addObject:[framed subdataWithRange:NSMakeRange(i, 1)]];
    }

    NSArray<NSData *> *bodies = [self bodiesByFeeding:chunks toReader:reader];
    XCTAssertEqual([bodies count], 1u);
    XCTAssertEqualObjects(bodies.firstObject, body);
}

- (void)testReaderParsesMultipleMessagesInOneChunk {
    SEELSPMessageReader *reader = [SEELSPMessageReader new];
    NSData *bodyA = [self dataFromString:@"{\"id\":1}"];
    NSData *bodyB = [self dataFromString:@"{\"id\":2}"];
    NSMutableData *combined = [NSMutableData data];
    [combined appendData:[SEELSPMessageWriter framedDataForJSONBody:bodyA]];
    [combined appendData:[SEELSPMessageWriter framedDataForJSONBody:bodyB]];

    NSArray<NSData *> *bodies = [self bodiesByFeeding:@[combined] toReader:reader];
    XCTAssertEqual([bodies count], 2u);
    XCTAssertEqualObjects(bodies[0], bodyA);
    XCTAssertEqualObjects(bodies[1], bodyB);
}

- (void)testReaderHandlesAdditionalHeadersAndZeroLengthBody {
    SEELSPMessageReader *reader = [SEELSPMessageReader new];
    NSData *framed = [self dataFromString:@"Content-Length: 0\r\nContent-Type: application/vscode-jsonrpc; charset=utf-8\r\n\r\n"];

    NSArray<NSData *> *bodies = [self bodiesByFeeding:@[framed] toReader:reader];
    XCTAssertEqual([bodies count], 1u);
    XCTAssertEqual([bodies.firstObject length], 0u);
}

- (void)testReaderRoundTripsThroughJSON {
    SEELSPMessageReader *reader = [SEELSPMessageReader new];
    NSDictionary *original = @{@"jsonrpc": @"2.0", @"id": @7, @"method": @"textDocument/hover", @"params": @{@"line": @3, @"items": @[@"a", @"b"]}};
    NSData *framed = [SEELSPMessageWriter framedDataForJSONObject:original error:NULL];

    NSArray<NSData *> *bodies = [self bodiesByFeeding:@[framed] toReader:reader];
    XCTAssertEqual([bodies count], 1u);
    id decoded = [NSJSONSerialization JSONObjectWithData:bodies.firstObject options:0 error:NULL];
    XCTAssertEqualObjects(decoded, original);
}

- (void)testReaderReportsMissingContentLength {
    SEELSPMessageReader *reader = [SEELSPMessageReader new];
    __block NSError *capturedError = nil;
    reader.errorHandler = ^(NSError *error) {
        capturedError = error;
    };
    [reader appendData:[self dataFromString:@"Content-Type: text/plain\r\n\r\n"]];
    XCTAssertNotNil(capturedError);
    XCTAssertEqual(capturedError.code, SEELSPMessageReaderErrorMissingContentLength);
}

- (void)testReaderRejectsOversizedContentLength {
    SEELSPMessageReader *reader = [SEELSPMessageReader new];
    reader.maximumContentLength = 16;
    __block NSError *capturedError = nil;
    reader.errorHandler = ^(NSError *error) {
        capturedError = error;
    };
    [reader appendData:[self dataFromString:@"Content-Length: 1000\r\n\r\n"]];
    XCTAssertNotNil(capturedError);
    XCTAssertEqual(capturedError.code, SEELSPMessageReaderErrorContentLengthTooLarge);
}

#pragma mark - Coordinator

- (void)testCoordinatorBuildsRequestEnvelope {
    SEELSPRPCCoordinator *coordinator = [SEELSPRPCCoordinator new];
    NSDictionary *request = [coordinator requestObjectForMethod:@"initialize" params:@{@"rootUri": @"file:///x"} reply:^(id result, id errorObject) {}];
    XCTAssertEqualObjects(request[@"jsonrpc"], @"2.0");
    XCTAssertEqualObjects(request[@"method"], @"initialize");
    XCTAssertEqualObjects(request[@"params"], @{@"rootUri": @"file:///x"});
    XCTAssertNotNil(request[@"id"]);
    XCTAssertEqual([coordinator pendingRequestCount], 1u);
}

- (void)testCoordinatorCorrelatesResponseToReply {
    SEELSPRPCCoordinator *coordinator = [SEELSPRPCCoordinator new];
    __block id capturedResult = nil;
    __block id capturedError = (id)@"sentinel";
    NSDictionary *request = [coordinator requestObjectForMethod:@"initialize" params:nil reply:^(id result, id errorObject) {
        capturedResult = result;
        capturedError = errorObject;
    }];

    NSDictionary *response = @{@"jsonrpc": @"2.0", @"id": request[@"id"], @"result": @{@"capabilities": @{}}};
    [coordinator handleIncomingObject:response];

    XCTAssertEqualObjects(capturedResult, @{@"capabilities": @{}});
    XCTAssertNil(capturedError);
    XCTAssertEqual([coordinator pendingRequestCount], 0u);
}

- (void)testCoordinatorDeliversErrorResponse {
    SEELSPRPCCoordinator *coordinator = [SEELSPRPCCoordinator new];
    __block id capturedResult = (id)@"sentinel";
    __block id capturedError = nil;
    NSDictionary *request = [coordinator requestObjectForMethod:@"shutdown" params:nil reply:^(id result, id errorObject) {
        capturedResult = result;
        capturedError = errorObject;
    }];

    NSDictionary *response = @{@"jsonrpc": @"2.0", @"id": request[@"id"], @"error": @{@"code": @(-32603), @"message": @"boom"}};
    [coordinator handleIncomingObject:response];

    XCTAssertNil(capturedResult);
    XCTAssertEqualObjects(capturedError[@"message"], @"boom");
}

- (void)testCoordinatorDispatchesNotification {
    SEELSPRPCCoordinator *coordinator = [SEELSPRPCCoordinator new];
    __block NSString *capturedMethod = nil;
    __block id capturedParams = nil;
    coordinator.notificationHandler = ^(NSString *method, id params) {
        capturedMethod = method;
        capturedParams = params;
    };
    [coordinator handleIncomingObject:@{@"jsonrpc": @"2.0", @"method": @"textDocument/publishDiagnostics", @"params": @{@"uri": @"file:///x"}}];
    XCTAssertEqualObjects(capturedMethod, @"textDocument/publishDiagnostics");
    XCTAssertEqualObjects(capturedParams, @{@"uri": @"file:///x"});
}

- (void)testCoordinatorAnswersServerRequest {
    SEELSPRPCCoordinator *coordinator = [SEELSPRPCCoordinator new];
    __block NSDictionary *sentResponse = nil;
    coordinator.responseSender = ^(NSDictionary *responseObject) {
        sentResponse = responseObject;
    };
    coordinator.serverRequestHandler = ^(id requestID, NSString *method, id params, void (^respond)(id, id)) {
        respond(@[@{@"label": @"item"}], nil);
    };
    [coordinator handleIncomingObject:@{@"jsonrpc": @"2.0", @"id": @42, @"method": @"workspace/configuration", @"params": @{}}];

    XCTAssertEqualObjects(sentResponse[@"id"], @42);
    XCTAssertEqualObjects(sentResponse[@"result"], @[@{@"label": @"item"}]);
    XCTAssertNil(sentResponse[@"error"]);
}

- (void)testCoordinatorAnswersUnhandledServerRequestWithMethodNotFound {
    SEELSPRPCCoordinator *coordinator = [SEELSPRPCCoordinator new];
    __block NSDictionary *sentResponse = nil;
    coordinator.responseSender = ^(NSDictionary *responseObject) {
        sentResponse = responseObject;
    };
    [coordinator handleIncomingObject:@{@"jsonrpc": @"2.0", @"id": @5, @"method": @"window/showMessageRequest"}];
    XCTAssertEqualObjects(sentResponse[@"id"], @5);
    XCTAssertEqualObjects(sentResponse[@"error"][@"code"], @(-32601));
}

- (void)testCoordinatorFailsAllPendingOnTermination {
    SEELSPRPCCoordinator *coordinator = [SEELSPRPCCoordinator new];
    __block NSUInteger failures = 0;
    void (^reply)(id, id) = ^(id result, id errorObject) {
        if (errorObject) {
            failures++;
        }
    };
    [coordinator requestObjectForMethod:@"a" params:nil reply:reply];
    [coordinator requestObjectForMethod:@"b" params:nil reply:reply];
    XCTAssertEqual([coordinator pendingRequestCount], 2u);

    [coordinator failAllPendingWithErrorObject:@{@"message": @"server terminated"}];
    XCTAssertEqual(failures, 2u);
    XCTAssertEqual([coordinator pendingRequestCount], 0u);
}

@end

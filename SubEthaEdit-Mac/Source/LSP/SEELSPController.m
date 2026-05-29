//  SEELSPController.m
//  SubEthaEdit

#import "SEELSPController.h"
#import "PlainTextDocument.h"
#import "DocumentMode.h"
#import "FullTextStorage+LSPPosition.h"
#import "SEELSPDiagnostic.h"
#import "SEELSPServerConfiguration.h"
#import "SEELSPServerManager.h"

NSString * const SEELSPControllerDidChangeDiagnosticsNotification = @"SEELSPControllerDidChangeDiagnosticsNotification";

@implementation SEELSPController {
    __weak PlainTextDocument *I_document;
    NSString *I_serverInstanceID;
    NSString *I_documentURI;
    NSString *I_languageId;
    NSUInteger I_version;
    BOOL I_active;
    BOOL I_didOpen;
    NSMutableArray *I_pendingChanges;
    NSDictionary *I_capturedChange;
    BOOL I_flushScheduled;
    NSArray *I_diagnostics;
}

- (instancetype)initWithDocument:(PlainTextDocument *)document {
    self = [super init];
    if (self) {
        I_document = document;
        I_serverInstanceID = [[NSUUID UUID] UUIDString];
        I_version = 1;
        I_pendingChanges = [NSMutableArray array];
        I_diagnostics = @[];
    }
    return self;
}

- (NSArray *)diagnostics {
    return I_diagnostics;
}

- (BOOL)isActive {
    return I_active;
}

- (void)startIfNeeded {
    PlainTextDocument *document = I_document;
    SEELSPServerConfiguration *config = [[document documentMode] languageServerConfiguration];
    if (document && config.isStartable && !I_active) {
        I_active = YES;
        I_languageId = config.languageId ?: @"";
        I_documentURI = [self TCM_documentURIForDocument:document];
        [[SEELSPServerManager sharedManager] registerObserver:self forServerInstanceID:I_serverInstanceID];

        NSDictionary *configuration = [self TCM_xpcConfigurationWithServerConfig:config document:document];
        __weak typeof(self) weakSelf = self;
        [[SEELSPServerManager sharedManager] startServerWithConfiguration:configuration
                serverInstanceID:I_serverInstanceID
                bookmark:config.executableBookmark
                reply:^(BOOL started, NSError *error) {
            typeof(self) strongSelf = weakSelf;
            if (started) {
                [strongSelf TCM_sendDidOpen];
            } else {
                strongSelf->I_active = NO;
            }
        }];
    }
}

- (void)shutdown {
    if (I_active) {
        I_active = NO;
        [[SEELSPServerManager sharedManager] unregisterServerInstanceID:I_serverInstanceID];
        if (I_didOpen) {
            [[SEELSPServerManager sharedManager] sendNotificationForServer:I_serverInstanceID
                    method:@"textDocument/didClose"
                    params:@{@"textDocument": @{@"uri": I_documentURI}}];
        }
        [[SEELSPServerManager sharedManager] stopServer:I_serverInstanceID reply:^{}];
    }
}

- (NSString *)TCM_documentURIForDocument:(PlainTextDocument *)document {
    NSURL *fileURL = [document fileURL];
    return fileURL ? [fileURL absoluteString] : [@"untitled:" stringByAppendingString:I_serverInstanceID];
}

- (NSDictionary *)TCM_xpcConfigurationWithServerConfig:(SEELSPServerConfiguration *)config document:(PlainTextDocument *)document {
    NSMutableDictionary *configuration = [NSMutableDictionary dictionary];
    configuration[@"arguments"] = config.arguments ?: @[];
    if (config.environment) {
        configuration[@"environment"] = config.environment;
    }
    configuration[@"initializeParams"] = [self TCM_initializeParamsForDocument:document config:config];
    return configuration;
}

- (NSDictionary *)TCM_initializeParamsForDocument:(PlainTextDocument *)document config:(SEELSPServerConfiguration *)config {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    params[@"processId"] = @((NSInteger)[[NSProcessInfo processInfo] processIdentifier]);
    params[@"capabilities"] = @{};
    NSURL *rootURL = [[document fileURL] URLByDeletingLastPathComponent];
    params[@"rootUri"] = rootURL ? [rootURL absoluteString] : [NSNull null];
    if (config.initializationOptions) {
        params[@"initializationOptions"] = config.initializationOptions;
    }
    return params;
}

- (void)TCM_sendDidOpen {
    PlainTextDocument *document = I_document;
    if (document && I_active) {
        NSString *text = [document fullTextContentString] ?: @"";
        NSDictionary *params = @{@"textDocument": @{
            @"uri": I_documentURI,
            @"languageId": I_languageId,
            @"version": @(I_version),
            @"text": text,
        }};
        [[SEELSPServerManager sharedManager] sendNotificationForServer:I_serverInstanceID
                method:@"textDocument/didOpen"
                params:params];
        I_didOpen = YES;
    }
}

#pragma mark - didChange

- (void)noteWillReplaceCharactersInRange:(NSRange)range withString:(NSString *)string textStorage:(FullTextStorage *)textStorage {
    if (I_active && I_didOpen) {
        I_capturedChange = [textStorage lspContentChangeForRange:range replacementString:string];
    }
}

- (void)noteDidReplaceCharactersInRange:(NSRange)range withString:(NSString *)string {
    if (I_capturedChange) {
        [I_pendingChanges addObject:I_capturedChange];
        I_capturedChange = nil;
        if (!I_flushScheduled) {
            I_flushScheduled = YES;
            __weak typeof(self) weakSelf = self;
            dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf TCM_flushChanges]; });
        }
    }
}

- (void)TCM_flushChanges {
    I_flushScheduled = NO;
    if (I_active && I_didOpen && I_pendingChanges.count > 0) {
        I_version++;
        NSDictionary *params = @{
            @"textDocument": @{@"uri": I_documentURI, @"version": @(I_version)},
            @"contentChanges": [I_pendingChanges copy],
        };
        [I_pendingChanges removeAllObjects];
        [[SEELSPServerManager sharedManager] sendNotificationForServer:I_serverInstanceID
                method:@"textDocument/didChange"
                params:params];
    }
}

#pragma mark - Diagnostics

- (void)handleNotificationMethod:(NSString *)method params:(id)params {
    if ([method isEqualToString:@"textDocument/publishDiagnostics"] && [params isKindOfClass:[NSDictionary class]]) {
        [self TCM_updateDiagnosticsFromParams:params];
    }
}

- (void)TCM_updateDiagnosticsFromParams:(NSDictionary *)params {
    PlainTextDocument *document = I_document;
    NSString *uri = params[@"uri"];
    BOOL matchesDocument = (uri == nil) || (I_documentURI == nil) || [uri isEqualToString:I_documentURI];
    if (document && matchesDocument) {
        FullTextStorage *textStorage = [(FoldableTextStorage *)[document textStorage] fullTextStorage];
        I_diagnostics = [SEELSPDiagnostic diagnosticsFromPublishParams:params textStorage:textStorage];
        [[NSNotificationCenter defaultCenter] postNotificationName:SEELSPControllerDidChangeDiagnosticsNotification object:document];
        [[document plainTextEditors] makeObjectsPerformSelector:@selector(setNeedsDisplayForRuler)];
    }
}

@end

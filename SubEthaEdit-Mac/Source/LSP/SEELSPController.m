//  SEELSPController.m
//  SubEthaEdit

#import "SEELSPController.h"
#import "PlainTextDocument.h"
#import "PlainTextEditor.h"
#import "DocumentMode.h"
#import "LayoutManager.h"
#import "FullTextStorage+LSPPosition.h"
#import "SEELSPDiagnostic.h"
#import "SEELSPServerConfiguration.h"
#import "SEELSPServerManager.h"
#import "NSOperationQueue+TCMAdditions.h"
#import "NSStringTCMAdditions.h"

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
        I_serverInstanceID = [NSString UUIDString];
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
            [NSOperationQueue TCM_performBlockOnMainQueue:^{ [weakSelf TCM_flushChanges]; } afterDelay:0];
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
        [self TCM_applyDiagnosticUnderlines];
        [[NSNotificationCenter defaultCenter] postNotificationName:SEELSPControllerDidChangeDiagnosticsNotification object:document];
        [[document plainTextEditors] makeObjectsPerformSelector:@selector(setNeedsDisplayForRuler)];
    }
}

- (NSArray *)diagnosticsInFullRange:(NSRange)range {
    NSMutableArray *result = [NSMutableArray array];
    for (SEELSPDiagnostic *diagnostic in I_diagnostics) {
        NSRange diagnosticRange = diagnostic.fullRange;
        BOOL intersects = NSIntersectionRange(diagnosticRange, range).length > 0;
        BOOL pointInside = (diagnosticRange.length == 0) && NSLocationInRange(diagnosticRange.location, range);
        if (intersects || pointInside) {
            [result addObject:diagnostic];
        }
    }
    return result;
}

- (void)TCM_applyDiagnosticUnderlines {
    PlainTextDocument *document = I_document;
    FoldableTextStorage *foldable = (FoldableTextStorage *)[document textStorage];
    NSUInteger foldedLength = [foldable length];
    for (PlainTextEditor *editor in [document plainTextEditors]) {
        LayoutManager *layoutManager = (LayoutManager *)[[editor textView] layoutManager];
        NSRange whole = NSMakeRange(0, foldedLength);
        [layoutManager removeTemporaryAttributes:@[NSUnderlineStyleAttributeName, NSUnderlineColorAttributeName] forCharacterRange:whole];
        for (SEELSPDiagnostic *diagnostic in I_diagnostics) {
            NSRange foldedRange = [foldable foldedRangeForFullRange:diagnostic.fullRange expandIfFolded:NO];
            if (foldedRange.location != NSNotFound && foldedRange.length > 0 && NSMaxRange(foldedRange) <= foldedLength) {
                [layoutManager addTemporaryAttributes:@{
                    NSUnderlineStyleAttributeName: @(NSUnderlineStyleThick | NSUnderlinePatternDot),
                    NSUnderlineColorAttributeName: [[self class] colorForSeverity:diagnostic.severity],
                } forCharacterRange:foldedRange];
            }
        }
    }
}

+ (NSColor *)colorForSeverity:(SEELSPDiagnosticSeverity)severity {
    switch (severity) {
        case SEELSPDiagnosticSeverityError:       return [NSColor systemRedColor];
        case SEELSPDiagnosticSeverityWarning:     return [NSColor systemOrangeColor];
        case SEELSPDiagnosticSeverityInformation: return [NSColor systemBlueColor];
        case SEELSPDiagnosticSeverityHint:        return [NSColor systemGrayColor];
    }
    return [NSColor systemRedColor];
}

@end

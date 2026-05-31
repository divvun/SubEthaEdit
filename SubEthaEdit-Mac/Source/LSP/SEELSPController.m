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
#import "SEELSPJSONRPC.h"
#import "SEELSPMarkdownRenderer.h"
#import "SymbolTableEntry.h"
#import "NSImageTCMAdditions.h"
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
    NSArray *I_documentSymbolEntries;
    BOOL I_documentSymbolsDirty;
    BOOL I_documentSymbolsInFlight;
    BOOL I_serverSupportsDocumentSymbol;
    BOOL I_serverSupportsHover;
    BOOL I_serverSupportsDefinition;
    BOOL I_serverSupportsCompletion;
}

- (instancetype)initWithDocument:(PlainTextDocument *)document {
    self = [super init];
    if (self) {
        I_document = document;
        I_serverInstanceID = [NSString UUIDString];
        I_version = 1;
        I_pendingChanges = [NSMutableArray array];
        I_diagnostics = @[];
        I_serverSupportsDocumentSymbol = YES;
        I_serverSupportsHover = YES;
        I_serverSupportsDefinition = YES;
        I_serverSupportsCompletion = YES;
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
    if (config.suggestedCommand.length > 0) {
        configuration[@"command"] = config.suggestedCommand;
    }
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
        I_documentSymbolsDirty = YES;
        [self requestDocumentSymbolsIfNeeded];
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
        I_documentSymbolsDirty = YES;
    }
}

#pragma mark - Document symbols

- (NSArray *)documentSymbolEntries {
    return I_documentSymbolEntries;
}

- (void)requestDocumentSymbolsIfNeeded {
    if (I_active && I_didOpen && I_documentSymbolsDirty && !I_documentSymbolsInFlight && I_serverSupportsDocumentSymbol) {
        I_documentSymbolsInFlight = YES;
        I_documentSymbolsDirty = NO;
        NSDictionary *params = @{@"textDocument": @{@"uri": I_documentURI}};
        __weak typeof(self) weakSelf = self;
        [[SEELSPServerManager sharedManager] sendRequestForServer:I_serverInstanceID
                method:@"textDocument/documentSymbol"
                params:params
                reply:^(id result, NSDictionary *errorObject) {
            [weakSelf TCM_handleDocumentSymbolResult:result error:errorObject];
        }];
    }
}

- (void)TCM_handleDocumentSymbolResult:(id)result error:(NSDictionary *)errorObject {
    I_documentSymbolsInFlight = NO;
    PlainTextDocument *document = I_document;
    if (errorObject) {
        if ([errorObject[@"code"] integerValue] == SEELSPJSONRPCMethodNotFound) {
            I_serverSupportsDocumentSymbol = NO;
        }
    } else if ([result isKindOfClass:[NSArray class]] && document) {
        FullTextStorage *textStorage = [(FoldableTextStorage *)[document textStorage] fullTextStorage];
        I_documentSymbolEntries = [[self class] symbolTableEntriesFromDocumentSymbolResult:result textStorage:textStorage];
        [document updateSymbolTable];
    }
    [self requestDocumentSymbolsIfNeeded];
}

+ (NSArray *)symbolTableEntriesFromDocumentSymbolResult:(NSArray *)result textStorage:(FullTextStorage *)textStorage {
    NSMutableArray *entries = [NSMutableArray array];
    if ([result isKindOfClass:[NSArray class]]) {
        [self TCM_appendSymbolEntriesFromNodes:result depth:0 textStorage:textStorage into:entries];
    }
    return entries;
}

+ (void)TCM_appendSymbolEntriesFromNodes:(NSArray *)nodes depth:(int)depth textStorage:(FullTextStorage *)textStorage into:(NSMutableArray *)entries {
    for (id node in nodes) {
        if ([node isKindOfClass:[NSDictionary class]]) {
            NSDictionary *symbol = node;
            NSString *name = symbol[@"name"];
            NSDictionary *rangeDict = nil;
            NSDictionary *selectionDict = nil;
            if ([symbol[@"location"] isKindOfClass:[NSDictionary class]]) {
                rangeDict = symbol[@"location"][@"range"];
                selectionDict = rangeDict;
            } else {
                rangeDict = symbol[@"range"];
                selectionDict = [symbol[@"selectionRange"] isKindOfClass:[NSDictionary class]] ? symbol[@"selectionRange"] : rangeDict;
            }
            if ([name isKindOfClass:[NSString class]] && name.length > 0 && [rangeDict isKindOfClass:[NSDictionary class]]) {
                NSInteger kind = [symbol[@"kind"] integerValue];
                NSRange fullRange = [self TCM_fullRangeForLSPRange:rangeDict textStorage:textStorage];
                NSRange jumpRange = [self TCM_fullRangeForLSPRange:selectionDict textStorage:textStorage];
                SymbolTableEntry *entry = [SymbolTableEntry symbolTableEntryWithName:name
                        fontTraitMask:0
                        image:[self TCM_imageForSymbolKind:kind]
                        type:[self TCM_typeForSymbolKind:kind]
                        indentationLevel:depth
                        jumpRange:jumpRange
                        range:fullRange];
                [entries addObject:entry];
            }
            NSArray *children = symbol[@"children"];
            if ([children isKindOfClass:[NSArray class]]) {
                [self TCM_appendSymbolEntriesFromNodes:children depth:(depth + 1) textStorage:textStorage into:entries];
            }
        }
    }
}

+ (NSRange)TCM_fullRangeForLSPRange:(NSDictionary *)rangeDict textStorage:(FullTextStorage *)textStorage {
    NSRange result = NSMakeRange(0, 0);
    NSDictionary *start = rangeDict[@"start"];
    NSDictionary *end = rangeDict[@"end"];
    if ([start isKindOfClass:[NSDictionary class]] && [end isKindOfClass:[NSDictionary class]]) {
        NSUInteger startOffset = [textStorage offsetForLSPLine:[start[@"line"] unsignedIntegerValue] character:[start[@"character"] unsignedIntegerValue]];
        NSUInteger endOffset = [textStorage offsetForLSPLine:[end[@"line"] unsignedIntegerValue] character:[end[@"character"] unsignedIntegerValue]];
        if (endOffset < startOffset) { endOffset = startOffset; }
        result = NSMakeRange(startOffset, endOffset - startOffset);
    }
    return result;
}

+ (NSImage *)TCM_imageForSymbolKind:(NSInteger)kind {
    return [NSImage symbolImageNamed:[self TCM_badgeNameForSymbolKind:kind]];
}

+ (NSString *)TCM_badgeNameForSymbolKind:(NSInteger)kind {
    NSString *badge;
    switch (kind) {
        case 6:
        case 9:
        case 12: badge = @"f()_#6AB18D"; break;
        case 5:  badge = @"C_#6D5E85"; break;
        case 23: badge = @"S_#6D5E85"; break;
        case 11: badge = @"I_#6D5E85"; break;
        case 10: badge = @"E_#6D5E85"; break;
        case 22: badge = @"e_#6D5E85"; break;
        case 26: badge = @"T_#6D5E85"; break;
        case 7:  badge = @"P_#6D5E85"; break;
        case 8:  badge = @"F_#6D5E85"; break;
        case 2:
        case 3:
        case 4:  badge = @"N_#4094E4"; break;
        case 13: badge = @"v_#4094E4"; break;
        case 14: badge = @"c_#4094E4"; break;
        default: badge = @"·_#6D5E85"; break;
    }
    return badge;
}

+ (NSString *)TCM_typeForSymbolKind:(NSInteger)kind {
    return [NSString stringWithFormat:@"lsp.symbol.%ld", (long)kind];
}

#pragma mark - Hover

- (void)requestHoverAtFullOffset:(NSUInteger)offset reply:(void (^)(NSAttributedString *, NSRange, BOOL))reply {
    PlainTextDocument *document = I_document;
    if (I_active && I_didOpen && I_serverSupportsHover && document) {
        FullTextStorage *textStorage = [(FoldableTextStorage *)[document textStorage] fullTextStorage];
        NSUInteger line = 0, character = 0;
        [textStorage lspLine:&line character:&character forOffset:offset];
        NSDictionary *params = @{
            @"textDocument": @{@"uri": I_documentURI},
            @"position": @{@"line": @(line), @"character": @(character)},
        };
        __weak typeof(self) weakSelf = self;
        [[SEELSPServerManager sharedManager] sendRequestForServer:I_serverInstanceID
                method:@"textDocument/hover"
                params:params
                reply:^(id result, NSDictionary *errorObject) {
            typeof(self) strongSelf = weakSelf;
            NSAttributedString *contents = nil;
            NSRange fullRange = NSMakeRange(0, 0);
            BOOL hasRange = NO;
            if (errorObject) {
                if (strongSelf && [errorObject[@"code"] integerValue] == SEELSPJSONRPCMethodNotFound) {
                    strongSelf->I_serverSupportsHover = NO;
                }
            } else if ([result isKindOfClass:[NSDictionary class]]) {
                contents = [SEELSPMarkdownRenderer attributedStringFromHoverContents:result[@"contents"]];
                NSRange parsedRange = [SEELSPController hoverFullRangeFromResult:result textStorage:textStorage];
                if (parsedRange.location != NSNotFound) {
                    fullRange = parsedRange;
                    hasRange = YES;
                }
            }
            reply(contents, fullRange, hasRange);
        }];
    } else {
        reply(nil, NSMakeRange(0, 0), NO);
    }
}

+ (NSRange)hoverFullRangeFromResult:(NSDictionary *)result textStorage:(FullTextStorage *)textStorage {
    NSRange range = NSMakeRange(NSNotFound, 0);
    if ([result[@"range"] isKindOfClass:[NSDictionary class]]) {
        range = [self TCM_fullRangeForLSPRange:result[@"range"] textStorage:textStorage];
    }
    return range;
}

#pragma mark - Definition

- (void)requestDefinitionAtFullOffset:(NSUInteger)offset reply:(void (^)(NSArray *))reply {
    PlainTextDocument *document = I_document;
    if (I_active && I_didOpen && I_serverSupportsDefinition && document) {
        FullTextStorage *textStorage = [(FoldableTextStorage *)[document textStorage] fullTextStorage];
        NSUInteger line = 0, character = 0;
        [textStorage lspLine:&line character:&character forOffset:offset];
        NSDictionary *params = @{
            @"textDocument": @{@"uri": I_documentURI},
            @"position": @{@"line": @(line), @"character": @(character)},
        };
        __weak typeof(self) weakSelf = self;
        [[SEELSPServerManager sharedManager] sendRequestForServer:I_serverInstanceID
                method:@"textDocument/definition"
                params:params
                reply:^(id result, NSDictionary *errorObject) {
            typeof(self) strongSelf = weakSelf;
            NSArray *targets = @[];
            if (errorObject) {
                if (strongSelf && [errorObject[@"code"] integerValue] == SEELSPJSONRPCMethodNotFound) {
                    strongSelf->I_serverSupportsDefinition = NO;
                }
            } else {
                targets = [SEELSPController definitionTargetsFromResult:result];
            }
            reply(targets);
        }];
    } else {
        reply(@[]);
    }
}

+ (NSArray *)definitionTargetsFromResult:(id)result {
    NSMutableArray *targets = [NSMutableArray array];
    if ([result isKindOfClass:[NSArray class]]) {
        for (id element in result) {
            [self TCM_appendDefinitionTargetFromNode:element into:targets];
        }
    } else if ([result isKindOfClass:[NSDictionary class]]) {
        [self TCM_appendDefinitionTargetFromNode:result into:targets];
    }
    return targets;
}

+ (void)TCM_appendDefinitionTargetFromNode:(id)node into:(NSMutableArray *)targets {
    if ([node isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = node;
        NSString *uri = dict[@"uri"];
        NSDictionary *range = dict[@"range"];
        if (![uri isKindOfClass:[NSString class]]) {
            uri = dict[@"targetUri"];
            range = [dict[@"targetSelectionRange"] isKindOfClass:[NSDictionary class]] ? dict[@"targetSelectionRange"] : dict[@"targetRange"];
        }
        if ([uri isKindOfClass:[NSString class]] && [range isKindOfClass:[NSDictionary class]]) {
            [targets addObject:@{@"uri": uri, @"range": range}];
        }
    }
}

+ (NSRange)fullTextRangeForLSPRange:(NSDictionary *)rangeDict textStorage:(FullTextStorage *)textStorage {
    return [self TCM_fullRangeForLSPRange:rangeDict textStorage:textStorage];
}

#pragma mark - Completion

- (void)requestCompletionAtFullOffset:(NSUInteger)offset reply:(void (^)(NSArray *))reply {
    PlainTextDocument *document = I_document;
    if (I_active && I_didOpen && I_serverSupportsCompletion && document) {
        FullTextStorage *textStorage = [(FoldableTextStorage *)[document textStorage] fullTextStorage];
        NSUInteger line = 0, character = 0;
        [textStorage lspLine:&line character:&character forOffset:offset];
        NSDictionary *params = @{
            @"textDocument": @{@"uri": I_documentURI},
            @"position": @{@"line": @(line), @"character": @(character)},
        };
        __weak typeof(self) weakSelf = self;
        [[SEELSPServerManager sharedManager] sendRequestForServer:I_serverInstanceID
                method:@"textDocument/completion"
                params:params
                reply:^(id result, NSDictionary *errorObject) {
            typeof(self) strongSelf = weakSelf;
            NSArray *strings = @[];
            if (errorObject) {
                if (strongSelf && [errorObject[@"code"] integerValue] == SEELSPJSONRPCMethodNotFound) {
                    strongSelf->I_serverSupportsCompletion = NO;
                }
            } else {
                strings = [SEELSPController completionStringsFromResult:result];
            }
            reply(strings);
        }];
    } else {
        reply(@[]);
    }
}

+ (NSArray *)completionStringsFromResult:(id)result {
    NSArray *items = nil;
    if ([result isKindOfClass:[NSArray class]]) {
        items = result;
    } else if ([result isKindOfClass:[NSDictionary class]] && [result[@"items"] isKindOfClass:[NSArray class]]) {
        items = result[@"items"];
    }
    NSMutableArray *sortable = [NSMutableArray array];
    NSUInteger order = 0;
    for (id item in items) {
        if ([item isKindOfClass:[NSDictionary class]]) {
            NSString *insertString = [self TCM_insertStringForCompletionItem:item];
            if (insertString.length > 0) {
                NSString *sortText = [item[@"sortText"] isKindOfClass:[NSString class]] ? item[@"sortText"] : insertString;
                [sortable addObject:@{@"insert": insertString, @"sort": sortText, @"order": @(order)}];
                order++;
            }
        }
    }
    [sortable sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSComparisonResult result = [a[@"sort"] compare:b[@"sort"]];
        if (result == NSOrderedSame) {
            result = [a[@"order"] compare:b[@"order"]];
        }
        return result;
    }];
    NSMutableArray *strings = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (NSDictionary *entry in sortable) {
        NSString *insertString = entry[@"insert"];
        if (![seen containsObject:insertString]) {
            [seen addObject:insertString];
            [strings addObject:insertString];
        }
    }
    return strings;
}

+ (NSString *)TCM_insertStringForCompletionItem:(NSDictionary *)item {
    NSString *result = nil;
    BOOL isSnippet = [item[@"insertTextFormat"] integerValue] == 2;
    NSString *insertText = [item[@"insertText"] isKindOfClass:[NSString class]] ? item[@"insertText"] : nil;
    NSString *label = [item[@"label"] isKindOfClass:[NSString class]] ? item[@"label"] : nil;
    if (insertText && !isSnippet) {
        result = insertText;
    } else if (label) {
        result = label;
    }
    return result;
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

+ (SEELSPDiagnosticSeverity)highestSeverityInDiagnostics:(NSArray *)diagnostics {
    SEELSPDiagnosticSeverity result = SEELSPDiagnosticSeverityHint;
    for (SEELSPDiagnostic *diagnostic in diagnostics) {
        if (diagnostic.severity < result) {
            result = diagnostic.severity;
        }
    }
    return result;
}

+ (NSString *)TCM_labelForSeverity:(SEELSPDiagnosticSeverity)severity {
    switch (severity) {
        case SEELSPDiagnosticSeverityError:       return NSLocalizedString(@"error", @"LSP diagnostic severity label");
        case SEELSPDiagnosticSeverityWarning:     return NSLocalizedString(@"warning", @"LSP diagnostic severity label");
        case SEELSPDiagnosticSeverityInformation: return NSLocalizedString(@"info", @"LSP diagnostic severity label");
        case SEELSPDiagnosticSeverityHint:        return NSLocalizedString(@"hint", @"LSP diagnostic severity label");
    }
    return NSLocalizedString(@"error", @"LSP diagnostic severity label");
}

+ (NSAttributedString *)attributedStringForDiagnostics:(NSArray *)diagnostics {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    NSFont *font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    for (SEELSPDiagnostic *diagnostic in diagnostics) {
        if (result.length > 0) {
            [result appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
        }
        NSString *label = [self TCM_labelForSeverity:diagnostic.severity];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:[label stringByAppendingString:@": "]
                attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: [self colorForSeverity:diagnostic.severity]}]];
        [result appendAttributedString:[[NSAttributedString alloc] initWithString:(diagnostic.message ?: @"")
                attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: [NSColor labelColor]}]];

        NSString *origin = [self TCM_originForDiagnostic:diagnostic];
        if (origin.length > 0) {
            [result appendAttributedString:[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@" (%@)", origin]
                    attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: [NSColor secondaryLabelColor]}]];
        }
    }
    return result;
}

+ (NSString *)TCM_originForDiagnostic:(SEELSPDiagnostic *)diagnostic {
    NSString *result = nil;
    if (diagnostic.source.length > 0 && diagnostic.code.length > 0) {
        result = [NSString stringWithFormat:@"%@: %@", diagnostic.source, diagnostic.code];
    } else if (diagnostic.source.length > 0) {
        result = diagnostic.source;
    } else if (diagnostic.code.length > 0) {
        result = diagnostic.code;
    }
    return result;
}

@end

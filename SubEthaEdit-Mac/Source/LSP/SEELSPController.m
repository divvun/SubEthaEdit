//  SEELSPController.m
//  SubEthaEdit

#import "SEELSPController.h"
#import "PlainTextDocument.h"
#import "DocumentMode.h"
#import "SEELSPServerConfiguration.h"
#import "SEELSPServerManager.h"

@implementation SEELSPController {
    __weak PlainTextDocument *I_document;
    NSString *I_serverInstanceID;
    NSString *I_documentURI;
    NSString *I_languageId;
    NSUInteger I_version;
    BOOL I_active;
    BOOL I_didOpen;
}

- (instancetype)initWithDocument:(PlainTextDocument *)document {
    self = [super init];
    if (self) {
        I_document = document;
        I_serverInstanceID = [[NSUUID UUID] UUIDString];
        I_version = 1;
    }
    return self;
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

@end

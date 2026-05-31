//  SEELSPPreferences.m
//  SubEthaEdit

#import "SEELSPPreferences.h"
#import "DocumentModeManager.h"
#import "DocumentMode.h"
#import "PlainTextDocument.h"
#import "SEEDocumentController.h"
#import "SEELSPServerManager.h"
#import "SEELSPServerConfiguration.h"
#import "SEEScopedBookmarkManager.h"

static NSString * const SEELSPOverrideKey = @"SEELanguageServerOverride";

@implementation SEELSPPreferences

- (NSImage *)icon {
    if (@available(macOS 10.16, *)) {
        return [NSImage imageWithSystemSymbolName:@"chevron.left.forwardslash.chevron.right" accessibilityDescription:nil];
    } else {
        return [NSImage imageNamed:@"EditPrefs"];
    }
}

- (NSString *)iconLabel {
    return NSLocalizedStringWithDefaultValue(@"LanguageServersPrefsIconLabel", nil, [NSBundle mainBundle], @"Language Servers", @"Label displayed below the language servers icon and used as window title.");
}

- (NSString *)identifier {
    return @"de.codingmonkeys.subethaedit.preferences.languageservers";
}

- (NSString *)mainNibName {
    return @"SEELSPPreferences";
}

- (void)mainViewDidLoad {
    [O_environmentTextView setRichText:NO];
    [O_environmentTextView setAutomaticQuoteSubstitutionEnabled:NO];
    [O_environmentTextView setFont:[NSFont userFixedPitchFontOfSize:0]];
    [O_environmentTextView setDelegate:self];

    [self changeMode:O_modePopUpButton];
}

- (NSString *)TCM_selectedModeIdentifier {
    return [O_modePopUpButton selectedModeIdentifier];
}

- (NSDictionary *)TCM_modeDefaults {
    return [[NSUserDefaults standardUserDefaults] dictionaryForKey:[self TCM_selectedModeIdentifier]] ?: @{};
}

- (NSDictionary *)TCM_override {
    NSDictionary *override = [self TCM_modeDefaults][SEELSPOverrideKey];
    return [override isKindOfClass:[NSDictionary class]] ? override : @{};
}

- (IBAction)changeMode:(id)aSender {
    NSDictionary *override = [self TCM_override];
    DocumentMode *mode = [[DocumentModeManager sharedInstance] documentModeForIdentifier:[self TCM_selectedModeIdentifier]];
    SEELSPServerConfiguration *config = [mode languageServerConfiguration];

    [O_enabledButton setState:config.isEnabled ? NSControlStateValueOn : NSControlStateValueOff];
    [O_argumentsField setStringValue:[[self class] stringFromArguments:config.arguments]];
    [O_environmentTextView setString:[[self class] stringFromEnvironment:config.environment]];
    NSString *serverDisplay = [self TCM_executablePathForBookmark:override[@"ExecutableBookmark"]];
    if (serverDisplay.length == 0) {
        serverDisplay = config.suggestedCommand; // the mode's bundled default server, resolved on PATH at launch
    }
    [O_executablePathField setStringValue:serverDisplay ?: @""];
    [self TCM_updateStatus];
}

- (NSString *)TCM_executablePathForBookmark:(NSData *)bookmark {
    NSString *result = nil;
    if ([bookmark isKindOfClass:[NSData class]]) {
        BOOL stale = NO;
        NSURL *url = [NSURL URLByResolvingBookmarkData:bookmark
                                               options:NSURLBookmarkResolutionWithSecurityScope
                                         relativeToURL:nil
                                   bookmarkDataIsStale:&stale
                                                 error:NULL];
        result = [url path];
    }
    return result;
}

- (void)TCM_updateStatus {
    if ([O_enabledButton state] != NSControlStateValueOn) {
        [O_statusField setStringValue:NSLocalizedString(@"Disabled", @"LSP server status: disabled for this mode.")];
        return;
    }
    NSString *bookmarkPath = [self TCM_executablePathForBookmark:[self TCM_override][@"ExecutableBookmark"]];
    if (bookmarkPath.length > 0) {
        [O_statusField setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Enabled — %@", @"LSP server status: enabled with executable path."), bookmarkPath]];
        return;
    }
    DocumentMode *mode = [[DocumentModeManager sharedInstance] documentModeForIdentifier:[self TCM_selectedModeIdentifier]];
    NSString *command = [[mode languageServerConfiguration] suggestedCommand];
    if (command.length == 0) {
        [O_statusField setStringValue:NSLocalizedString(@"Enabled (no server chosen)", @"LSP server status: enabled but no executable picked.")];
        return;
    }
    // Ask the host whether the suggested command resolves on PATH, then reflect it.
    NSString *modeIdentifier = [self TCM_selectedModeIdentifier];
    [[SEELSPServerManager sharedManager] locateCommand:command reply:^(NSString *path) {
        if (![[self TCM_selectedModeIdentifier] isEqualToString:modeIdentifier]) {
            return;
        }
        if (path.length > 0) {
            NSString *found = [NSString stringWithFormat:@"%@ (%@)", command, path];
            [O_statusField setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Enabled — %@", @"LSP server status: enabled with executable path."), found]];
        } else {
            [O_statusField setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Enabled — %@ not found on PATH", @"LSP server status: enabled but the suggested command is not installed."), command]];
        }
    }];
}

- (IBAction)toggleEnabled:(id)aSender {
    [self TCM_persistOverride];
}

- (IBAction)changeArguments:(id)aSender {
    [self TCM_persistOverride];
}

- (void)textDidEndEditing:(NSNotification *)aNotification {
    if ([aNotification object] == O_environmentTextView) {
        [self TCM_persistOverride];
    }
}

- (IBAction)chooseExecutable:(id)aSender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setAllowsMultipleSelection:NO];
    [panel setMessage:NSLocalizedString(@"Choose the language server executable.", @"NSOpenPanel message when picking an LSP server binary.")];
    [panel setDirectoryURL:[NSURL fileURLWithPath:@"/opt/homebrew/bin"]]; // common install dir; user can navigate elsewhere
    if ([panel runModal] == NSFileHandlingPanelOKButton) {
        NSURL *url = [[panel URLs] firstObject];
        NSError *error = nil;
        NSData *bookmark = [SEELSPServerManager bookmarkForExecutableURL:url error:&error];
        if (bookmark) {
            [O_executablePathField setStringValue:[url path]];
            [self TCM_persistOverrideWithBookmark:bookmark];
        } else {
            [self presentError:error];
        }
    }
}

- (void)TCM_persistOverride {
    NSData *existingBookmark = [self TCM_override][@"ExecutableBookmark"];
    [self TCM_persistOverrideWithBookmark:existingBookmark];
}

- (void)TCM_persistOverrideWithBookmark:(NSData *)bookmark {
    NSString *modeIdentifier = [self TCM_selectedModeIdentifier];
    BOOL enabled = [O_enabledButton state] == NSControlStateValueOn;
    NSArray *arguments = [[self class] argumentsFromString:[O_argumentsField stringValue]];
    NSDictionary *environment = [[self class] environmentFromString:[O_environmentTextView string]];
    NSDictionary *newModeDefaults = [[self class] modeDefaultsByApplyingEnabled:enabled
            arguments:arguments
            environment:environment
            bookmark:bookmark
            toModeDefaults:[self TCM_modeDefaults]];
    [[NSUserDefaults standardUserDefaults] setObject:newModeDefaults forKey:modeIdentifier];
    [self TCM_updateStatus];
    [self TCM_reloadOpenDocumentsForMode:modeIdentifier];
}

- (void)TCM_reloadOpenDocumentsForMode:(NSString *)modeIdentifier {
    DocumentMode *mode = [[DocumentModeManager sharedInstance] documentModeForIdentifier:modeIdentifier];
    for (PlainTextDocument *document in [[SEEDocumentController sharedInstance] documentsInMode:mode]) {
        [document reloadLanguageServerConfiguration];
    }
}

#pragma mark - Pure helpers

+ (NSArray<NSString *> *)argumentsFromString:(NSString *)string {
    NSMutableArray *result = [NSMutableArray array];
    for (NSString *token in [string componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]) {
        if (token.length > 0) {
            [result addObject:token];
        }
    }
    return result;
}

+ (NSString *)stringFromArguments:(NSArray<NSString *> *)arguments {
    return [arguments componentsJoinedByString:@" "] ?: @"";
}

+ (NSDictionary<NSString *, NSString *> *)environmentFromString:(NSString *)string {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *line in [string componentsSeparatedByString:@"\n"]) {
        NSRange equals = [line rangeOfString:@"="];
        if (equals.location != NSNotFound) {
            NSString *key = [[line substringToIndex:equals.location] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            NSString *value = [[line substringFromIndex:NSMaxRange(equals)] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (key.length > 0) {
                result[key] = value;
            }
        }
    }
    return result;
}

+ (NSString *)stringFromEnvironment:(NSDictionary<NSString *, NSString *> *)environment {
    NSMutableArray *lines = [NSMutableArray array];
    for (NSString *key in [[environment allKeys] sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)]) {
        [lines addObject:[NSString stringWithFormat:@"%@=%@", key, environment[key]]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

+ (NSDictionary *)modeDefaultsByApplyingEnabled:(BOOL)enabled
        arguments:(NSArray<NSString *> *)arguments
        environment:(NSDictionary<NSString *, NSString *> *)environment
        bookmark:(NSData *)bookmark
        toModeDefaults:(NSDictionary *)existing {
    NSMutableDictionary *modeDefaults = [existing mutableCopy] ?: [NSMutableDictionary dictionary];
    NSDictionary *existingOverride = modeDefaults[SEELSPOverrideKey];
    NSMutableDictionary *override = [existingOverride isKindOfClass:[NSDictionary class]] ? [existingOverride mutableCopy] : [NSMutableDictionary dictionary];

    override[@"Enabled"] = @(enabled);
    override[@"Arguments"] = arguments ?: @[];
    override[@"Environment"] = environment ?: @{};
    if (bookmark) {
        override[@"ExecutableBookmark"] = bookmark;
    } else {
        [override removeObjectForKey:@"ExecutableBookmark"];
    }

    modeDefaults[SEELSPOverrideKey] = override;
    return modeDefaults;
}

@end

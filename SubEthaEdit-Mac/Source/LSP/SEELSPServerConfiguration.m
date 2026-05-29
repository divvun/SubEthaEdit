//  SEELSPServerConfiguration.m
//  SubEthaEdit

#import "SEELSPServerConfiguration.h"

@implementation SEELSPServerConfiguration

+ (instancetype)configurationWithBundleDefaults:(NSDictionary *)bundleDefaults override:(NSDictionary *)override {
    SEELSPServerConfiguration *result = nil;
    if (bundleDefaults.count > 0 || override.count > 0) {
        result = [[self alloc] initWithBundleDefaults:bundleDefaults override:override];
    }
    return result;
}

- (instancetype)initWithBundleDefaults:(NSDictionary *)bundleDefaults override:(NSDictionary *)override {
    self = [super init];
    if (self) {
        NSNumber *overrideEnabled = override[@"Enabled"];
        _enabled = overrideEnabled ? [overrideEnabled boolValue] : [bundleDefaults[@"Enabled"] boolValue];
        _languageId = [bundleDefaults[@"LanguageId"] copy];
        _suggestedCommand = [bundleDefaults[@"SuggestedCommand"] copy];
        _arguments = [(override[@"Arguments"] ?: bundleDefaults[@"Arguments"] ?: @[]) copy];
        _environment = [(override[@"Environment"] ?: bundleDefaults[@"Environment"]) copy];
        _initializationOptions = [(override[@"InitializationOptions"] ?: bundleDefaults[@"InitializationOptions"]) copy];
        _executableBookmark = [override[@"ExecutableBookmark"] copy];
    }
    return self;
}

- (BOOL)isStartable {
    return self.enabled && self.executableBookmark != nil;
}

@end

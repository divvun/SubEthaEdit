//  SEELSPServerConfiguration.h
//  SubEthaEdit

#import <Foundation/Foundation.h>

@interface SEELSPServerConfiguration : NSObject

// Merge a mode's bundled LanguageServer.plist defaults with the per-mode user override
// (override wins per key). Returns nil when neither side provides anything.
+ (instancetype)configurationWithBundleDefaults:(NSDictionary *)bundleDefaults
        override:(NSDictionary *)override;

@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;
@property (nonatomic, readonly, copy) NSString *languageId;
@property (nonatomic, readonly, copy) NSString *suggestedCommand;
@property (nonatomic, readonly, copy) NSArray<NSString *> *arguments;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *environment;
@property (nonatomic, readonly, copy) NSDictionary *initializationOptions;
@property (nonatomic, readonly, copy) NSData *executableBookmark;

// Enabled and has an executable bookmark, so a server can actually be launched.
@property (nonatomic, readonly, getter=isStartable) BOOL startable;

@end

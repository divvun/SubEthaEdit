//  SEELSPServerConfiguration.h
//  SubEthaEdit

#import <Foundation/Foundation.h>

@interface SEELSPServerConfiguration : NSObject

+ (instancetype)configurationWithBundleDefaults:(NSDictionary *)bundleDefaults
        override:(NSDictionary *)override;

@property (nonatomic, readonly, getter=isEnabled) BOOL enabled;
@property (nonatomic, readonly, copy) NSString *languageId;
@property (nonatomic, readonly, copy) NSString *suggestedCommand;
@property (nonatomic, readonly, copy) NSArray<NSString *> *arguments;
@property (nonatomic, readonly, copy) NSDictionary<NSString *, NSString *> *environment;
@property (nonatomic, readonly, copy) NSDictionary *initializationOptions;
@property (nonatomic, readonly, copy) NSData *executableBookmark;

@property (nonatomic, readonly, getter=isStartable) BOOL startable;

@end

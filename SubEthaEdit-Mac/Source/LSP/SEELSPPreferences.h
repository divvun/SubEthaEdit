//  SEELSPPreferences.h
//  SubEthaEdit

#import "TCMPreferenceModule.h"

@class DocumentModePopUpButton;

@interface SEELSPPreferences : TCMPreferenceModule {
    IBOutlet DocumentModePopUpButton *O_modePopUpButton;
    IBOutlet NSButton *O_enabledButton;
    IBOutlet NSTextField *O_executablePathField;
    IBOutlet NSButton *O_chooseExecutableButton;
    IBOutlet NSTextField *O_argumentsField;
    IBOutlet NSTextView *O_environmentTextView;
    IBOutlet NSTextField *O_statusField;
}

- (IBAction)changeMode:(id)aSender;
- (IBAction)toggleEnabled:(id)aSender;
- (IBAction)chooseExecutable:(id)aSender;
- (IBAction)changeArguments:(id)aSender;

+ (NSArray<NSString *> *)argumentsFromString:(NSString *)string;
+ (NSString *)stringFromArguments:(NSArray<NSString *> *)arguments;
+ (NSDictionary<NSString *, NSString *> *)environmentFromString:(NSString *)string;
+ (NSString *)stringFromEnvironment:(NSDictionary<NSString *, NSString *> *)environment;
+ (NSDictionary *)modeDefaultsByApplyingEnabled:(BOOL)enabled
        arguments:(NSArray<NSString *> *)arguments
        environment:(NSDictionary<NSString *, NSString *> *)environment
        bookmark:(NSData *)bookmark
        toModeDefaults:(NSDictionary *)existing;

@end

//  SEELSPMarkdownRenderer.h
//  SubEthaEdit

#import <Cocoa/Cocoa.h>

@interface SEELSPMarkdownRenderer : NSObject

+ (NSAttributedString *)attributedStringFromHoverContents:(id)contents;
+ (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown;

@end

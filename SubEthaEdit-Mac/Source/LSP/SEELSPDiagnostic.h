//  SEELSPDiagnostic.h
//  SubEthaEdit

#import <Foundation/Foundation.h>

@class FullTextStorage;

typedef NS_ENUM(NSInteger, SEELSPDiagnosticSeverity) {
    SEELSPDiagnosticSeverityError = 1,
    SEELSPDiagnosticSeverityWarning = 2,
    SEELSPDiagnosticSeverityInformation = 3,
    SEELSPDiagnosticSeverityHint = 4,
};

@interface SEELSPDiagnostic : NSObject

@property (nonatomic, readonly) NSRange fullRange;
@property (nonatomic, readonly) SEELSPDiagnosticSeverity severity;
@property (nonatomic, readonly, copy) NSString *message;
@property (nonatomic, readonly, copy) NSString *source;
@property (nonatomic, readonly, copy) NSString *code;

+ (NSArray<SEELSPDiagnostic *> *)diagnosticsFromPublishParams:(NSDictionary *)params textStorage:(FullTextStorage *)textStorage;

@end

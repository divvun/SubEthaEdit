//  SEELSPDiagnostic.m
//  SubEthaEdit

#import "SEELSPDiagnostic.h"
#import "FullTextStorage+LSPPosition.h"

@implementation SEELSPDiagnostic

+ (NSArray<SEELSPDiagnostic *> *)diagnosticsFromPublishParams:(NSDictionary *)params textStorage:(FullTextStorage *)textStorage {
    NSMutableArray *result = [NSMutableArray array];
    NSArray *items = params[@"diagnostics"];
    if ([items isKindOfClass:[NSArray class]]) {
        for (id item in items) {
            if ([item isKindOfClass:[NSDictionary class]]) {
                SEELSPDiagnostic *diagnostic = [[self alloc] initWithDictionary:item textStorage:textStorage];
                if (diagnostic) {
                    [result addObject:diagnostic];
                }
            }
        }
    }
    return result;
}

- (instancetype)initWithDictionary:(NSDictionary *)dictionary textStorage:(FullTextStorage *)textStorage {
    NSDictionary *range = dictionary[@"range"];
    NSDictionary *start = range[@"start"];
    NSDictionary *end = range[@"end"];
    if (![start isKindOfClass:[NSDictionary class]] || ![end isKindOfClass:[NSDictionary class]]) {
        return nil;
    }
    self = [super init];
    if (self) {
        NSUInteger startOffset = [textStorage offsetForLSPLine:[start[@"line"] unsignedIntegerValue]
                                                     character:[start[@"character"] unsignedIntegerValue]];
        NSUInteger endOffset = [textStorage offsetForLSPLine:[end[@"line"] unsignedIntegerValue]
                                                   character:[end[@"character"] unsignedIntegerValue]];
        if (endOffset < startOffset) {
            endOffset = startOffset;
        }
        _fullRange = NSMakeRange(startOffset, endOffset - startOffset);

        NSNumber *severity = dictionary[@"severity"];
        _severity = severity ? (SEELSPDiagnosticSeverity)[severity integerValue] : SEELSPDiagnosticSeverityError;
        _message = [dictionary[@"message"] copy] ?: @"";
        _source = [dictionary[@"source"] copy];

        id code = dictionary[@"code"];
        if ([code isKindOfClass:[NSString class]]) {
            _code = [code copy];
        } else if ([code isKindOfClass:[NSNumber class]]) {
            _code = [code stringValue];
        }
    }
    return self;
}

@end

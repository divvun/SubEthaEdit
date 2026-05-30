//  SEELSPMarkdownRenderer.m
//  SubEthaEdit

#import "SEELSPMarkdownRenderer.h"

@implementation SEELSPMarkdownRenderer

+ (NSFont *)TCM_bodyFont {
    return [NSFont systemFontOfSize:[NSFont systemFontSize]];
}

+ (NSFont *)TCM_codeFont {
    return [NSFont userFixedPitchFontOfSize:[NSFont systemFontSize]];
}

+ (NSAttributedString *)attributedStringFromHoverContents:(id)contents {
    NSAttributedString *result = nil;
    if ([contents isKindOfClass:[NSArray class]]) {
        NSMutableAttributedString *combined = [[NSMutableAttributedString alloc] init];
        for (id element in contents) {
            NSAttributedString *part = [self TCM_attributedStringFromHoverElement:element];
            if (part.length > 0) {
                if (combined.length > 0) {
                    [combined appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
                }
                [combined appendAttributedString:part];
            }
        }
        result = combined;
    } else if (contents) {
        result = [self TCM_attributedStringFromHoverElement:contents];
    }
    return result;
}

+ (NSAttributedString *)TCM_attributedStringFromHoverElement:(id)element {
    NSAttributedString *result = [[NSAttributedString alloc] init];
    if ([element isKindOfClass:[NSString class]]) {
        result = [self attributedStringFromMarkdown:element];
    } else if ([element isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = element;
        NSString *value = [dict[@"value"] isKindOfClass:[NSString class]] ? dict[@"value"] : @"";
        if (dict[@"kind"]) {
            if ([dict[@"kind"] isEqualToString:@"markdown"]) {
                result = [self attributedStringFromMarkdown:value];
            } else {
                result = [[NSAttributedString alloc] initWithString:value attributes:@{NSFontAttributeName: [self TCM_bodyFont]}];
            }
        } else if (dict[@"value"]) {
            result = [[NSAttributedString alloc] initWithString:value attributes:@{NSFontAttributeName: [self TCM_codeFont]}];
        }
    }
    return result;
}

+ (NSAttributedString *)attributedStringFromMarkdown:(NSString *)markdown {
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
    if ([markdown isKindOfClass:[NSString class]]) {
        NSArray *lines = [markdown componentsSeparatedByString:@"\n"];
        NSMutableArray *rendered = [NSMutableArray array];
        BOOL inCodeFence = NO;
        for (NSString *line in lines) {
            NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if ([trimmed hasPrefix:@"```"]) {
                inCodeFence = !inCodeFence;
            } else if (inCodeFence) {
                [rendered addObject:[[NSAttributedString alloc] initWithString:line attributes:@{NSFontAttributeName: [self TCM_codeFont]}]];
            } else {
                [rendered addObject:[self TCM_attributedInlineFromLine:line]];
            }
        }
        for (NSUInteger i = 0; i < rendered.count; i++) {
            if (i > 0) {
                [out appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
            }
            [out appendAttributedString:rendered[i]];
        }
    }
    return out;
}

+ (NSAttributedString *)TCM_attributedInlineFromLine:(NSString *)line {
    NSUInteger hashes = 0;
    while (hashes < line.length && [line characterAtIndex:hashes] == '#') {
        hashes++;
    }
    NSFont *baseFont = [self TCM_bodyFont];
    if (hashes > 0 && hashes < line.length && [line characterAtIndex:hashes] == ' ') {
        line = [line substringFromIndex:hashes + 1];
        baseFont = [[NSFontManager sharedFontManager] convertFont:baseFont toHaveTrait:NSBoldFontMask];
    }
    return [self TCM_attributedSpansFromString:line baseFont:baseFont];
}

+ (NSAttributedString *)TCM_attributedSpansFromString:(NSString *)string baseFont:(NSFont *)baseFont {
    NSMutableAttributedString *out = [[NSMutableAttributedString alloc] init];
    NSMutableString *plain = [NSMutableString string];
    NSUInteger i = 0;
    NSUInteger length = string.length;
    while (i < length) {
        unichar c = [string characterAtIndex:i];
        NSRange spanRange = NSMakeRange(NSNotFound, 0);
        NSString *innerText = nil;
        NSFont *spanFont = nil;
        if (c == '`') {
            NSRange close = [string rangeOfString:@"`" options:0 range:NSMakeRange(i + 1, length - (i + 1))];
            if (close.location != NSNotFound && close.location > i + 1) {
                innerText = [string substringWithRange:NSMakeRange(i + 1, close.location - (i + 1))];
                spanFont = [self TCM_codeFont];
                spanRange = NSMakeRange(i, NSMaxRange(close) - i);
            }
        } else if ((c == '*' || c == '_')) {
            BOOL isDouble = (i + 1 < length && [string characterAtIndex:i + 1] == c);
            BOOL isItalic = (c == '*' && !isDouble);
            if (isDouble || isItalic) {
                NSString *delimiter = isDouble ? [NSString stringWithFormat:@"%C%C", c, c] : [NSString stringWithFormat:@"%C", c];
                NSUInteger searchStart = i + delimiter.length;
                NSRange close = [string rangeOfString:delimiter options:0 range:NSMakeRange(searchStart, length - searchStart)];
                if (close.location != NSNotFound && close.location > searchStart) {
                    NSString *raw = [string substringWithRange:NSMakeRange(searchStart, close.location - searchStart)];
                    NSFontTraitMask trait = isDouble ? NSBoldFontMask : NSItalicFontMask;
                    NSFont *styledFont = [[NSFontManager sharedFontManager] convertFont:baseFont toHaveTrait:trait];
                    if (plain.length > 0) {
                        [out appendAttributedString:[[NSAttributedString alloc] initWithString:plain attributes:@{NSFontAttributeName: baseFont}]];
                        [plain setString:@""];
                    }
                    [out appendAttributedString:[self TCM_attributedSpansFromString:raw baseFont:styledFont]];
                    i = NSMaxRange(close);
                    continue;
                }
            }
        }
        if (innerText) {
            if (plain.length > 0) {
                [out appendAttributedString:[[NSAttributedString alloc] initWithString:plain attributes:@{NSFontAttributeName: baseFont}]];
                [plain setString:@""];
            }
            [out appendAttributedString:[[NSAttributedString alloc] initWithString:innerText attributes:@{NSFontAttributeName: spanFont}]];
            i = NSMaxRange(spanRange);
        } else {
            [plain appendFormat:@"%C", c];
            i++;
        }
    }
    if (plain.length > 0) {
        [out appendAttributedString:[[NSAttributedString alloc] initWithString:plain attributes:@{NSFontAttributeName: baseFont}]];
    }
    return out;
}

@end

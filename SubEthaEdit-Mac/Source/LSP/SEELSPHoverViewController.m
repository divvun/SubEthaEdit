//  SEELSPHoverViewController.m
//  SubEthaEdit

#import "SEELSPHoverViewController.h"

static CGFloat const SEELSPHoverContentWidth = 420.0;
static CGFloat const SEELSPHoverMaxHeight = 320.0;
static CGFloat const SEELSPHoverInset = 8.0;

@implementation SEELSPHoverViewController {
    NSAttributedString *I_attributedString;
}

- (instancetype)initWithAttributedString:(NSAttributedString *)attributedString {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        I_attributedString = [attributedString copy];
    }
    return self;
}

- (void)loadView {
    NSTextView *textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, SEELSPHoverContentWidth, SEELSPHoverMaxHeight)];
    textView.editable = NO;
    textView.selectable = YES;
    textView.drawsBackground = NO;
    textView.textContainerInset = NSMakeSize(SEELSPHoverInset, SEELSPHoverInset);
    [textView setVerticallyResizable:YES];
    [textView setHorizontallyResizable:NO];
    textView.textContainer.widthTracksTextView = YES;
    textView.textContainer.containerSize = NSMakeSize(SEELSPHoverContentWidth, FLT_MAX);
    [[textView textStorage] setAttributedString:I_attributedString];

    [textView.layoutManager ensureLayoutForTextContainer:textView.textContainer];
    NSRect used = [textView.layoutManager usedRectForTextContainer:textView.textContainer];
    CGFloat contentHeight = NSHeight(used) + SEELSPHoverInset * 2.0;
    CGFloat viewHeight = MIN(contentHeight, SEELSPHoverMaxHeight);

    NSScrollView *scrollView = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, SEELSPHoverContentWidth, viewHeight)];
    scrollView.drawsBackground = NO;
    scrollView.hasVerticalScroller = (contentHeight > SEELSPHoverMaxHeight);
    scrollView.documentView = textView;

    self.view = scrollView;
    self.preferredContentSize = NSMakeSize(SEELSPHoverContentWidth, viewHeight);
}

@end

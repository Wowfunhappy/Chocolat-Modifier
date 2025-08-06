/*
* 
* When using Find, highlight all matches.
* 
*/


#import <objc/runtime.h>
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import "ZKSwizzle/ZKSwizzle.h"

// MARK: - Private Chocolat Interface Declarations

@interface XBFileFindController_Normal : NSObject
- (id)findString;
- (BOOL)ignoreCase;
@end

@interface XBFileFindController_Regex : NSObject
- (id)findString;
- (unsigned int)regexOptions:(BOOL)arg1;
- (int)syntax;
@end

@interface OGRegularExpression : NSObject
- (id)initWithString:(NSString *)pattern options:(unsigned int)options syntax:(int)syntax escapeCharacter:(NSString *)escape;
- (NSArray *)allMatchesInString:(NSString *)string options:(unsigned int)options range:(NSRange)range;
@end

@interface OGRegularExpressionMatch : NSObject
- (NSRange)rangeOfMatchedString;
@end

@interface XBFileFindView : NSView
{
    id controller;
    BOOL regexMode;
}
- (id)textView;
@end

@interface CHTextView : NSTextView
@end

@interface CHFullTextView : NSTextView
@end

// MARK: - Pass-Through View for Click-Through Overlays

@interface PassThroughView : NSView
@end

@implementation PassThroughView

- (NSView *)hitTest:(NSPoint)point {
    return nil; // Pass all mouse events through
}

- (BOOL)acceptsFirstResponder {
    return NO;
}

@end

// MARK: - Shared State Management

@interface FindHighlightState : NSObject
+ (BOOL)hasActiveHighlights;
+ (void)setHasActiveHighlights:(BOOL)active;
@end

@implementation FindHighlightState
static BOOL _hasActiveHighlights = NO;

+ (BOOL)hasActiveHighlights {
    return _hasActiveHighlights;
}

+ (void)setHasActiveHighlights:(BOOL)active {
    _hasActiveHighlights = active;
}
@end

// MARK: - Swizzle Interfaces

ZKSwizzleInterface(_FindHighlightAll_XBFileFindView, XBFileFindView, NSView);
ZKSwizzleInterface(_FindHighlightAll_CHFullTextView, CHFullTextView, NSTextView);

// MARK: - Find View Implementation

@implementation _FindHighlightAll_XBFileFindView

static __strong NSMutableArray *currentHighlightRanges = nil;
static __strong PassThroughView *dimOverlay = nil;
static __strong NSMutableArray *highlightViews = nil;
static NSTimer *debounceTimer = nil;
static BOOL isAnimatingOut = NO;

- (void)findButtons:(BOOL)forward {
    ZKOrig(void, forward);
    
    // Update immediately when navigating between matches (no debounce)
    [self updateFindHighlights];
}

- (id)textView {
    return ZKOrig(id);
}

- (void)setFieldColors:(int)color {
    ZKOrig(void, color);
    
    // Debounce updates when typing in find field
    [self scheduleUpdateFindHighlights];
}

- (void)scheduleUpdateFindHighlights {
    if (debounceTimer) {
        [debounceTimer invalidate];
        debounceTimer = nil;
    }
    
    debounceTimer = [NSTimer scheduledTimerWithTimeInterval:0.3
                                                     target:self
                                                   selector:@selector(updateFindHighlights)
                                                   userInfo:nil
                                                    repeats:NO];
}

- (void)close:(id)sender {
    if (debounceTimer) {
        [debounceTimer invalidate];
        debounceTimer = nil;
    }
    
    [self clearFindHighlights];
    
    ZKOrig(void, sender);
}

- (void)updateFindHighlights {
    // Cancel any pending timer
    if (debounceTimer) {
        [debounceTimer invalidate];
        debounceTimer = nil;
    }
    
    // Cancel any in-progress fade out animations
    if (isAnimatingOut && dimOverlay) {
        [[dimOverlay layer] removeAllAnimations];
        [dimOverlay setAlphaValue:1.0];
        
        for (NSView *view in highlightViews) {
            [[view layer] removeAllAnimations];
            [view setAlphaValue:1.0];
        }
        isAnimatingOut = NO;
    }
    
    [self clearFindHighlightsForUpdate];
    
    CHTextView *textView = (CHTextView *)[self textView];
    id controller = [self valueForKey:@"controller"];
    
    NSString *findString = [controller findString];
    if (!findString || [findString length] == 0) return;
    
    NSString *text = [textView string];
    
    currentHighlightRanges = [[NSMutableArray alloc] init];
    highlightViews = [[NSMutableArray alloc] init];
    
    // Add timeout protection for large documents
    NSDate *startTime = [NSDate date];
    const NSTimeInterval timeoutInterval = 0.5; // 500ms timeout
    const NSUInteger maxHighlights = 1000; // Maximum number of highlights to show
    
    // Perform search based on mode
    BOOL isRegexMode = [self valueForKey:@"regexMode"] ? [[self valueForKey:@"regexMode"] boolValue] : NO;
    
    if (isRegexMode && [controller isKindOfClass:NSClassFromString(@"XBFileFindController_Regex")]) {
        // Regex search
        @try {
            OGRegularExpression *regex = [[NSClassFromString(@"OGRegularExpression") alloc] 
                initWithString:findString 
                options:[controller regexOptions:YES] 
                syntax:[controller syntax] 
                escapeCharacter:@"\\"];
            
            NSArray *matches = [regex allMatchesInString:text 
                options:[controller regexOptions:YES] 
                range:NSMakeRange(0, [text length])];
            
            for (id match in matches) {
                    // Check timeout
                    if ([[NSDate date] timeIntervalSinceDate:startTime] > timeoutInterval) {
                        break;
                    }
                    
                    // Check max highlights limit
                    if ([currentHighlightRanges count] >= maxHighlights) {
                        break;
                    }
                    
                    NSRange range = [match rangeOfMatchedString];
                    [currentHighlightRanges addObject:[NSValue valueWithRange:range]];
            }
        } @catch (NSException *exception) {
            // Invalid regex
            currentHighlightRanges = nil;
            highlightViews = nil;
            return;
        }
    } else {
        // Normal string search
        NSStringCompareOptions options = 0;
        if ([controller respondsToSelector:@selector(ignoreCase)] && [controller ignoreCase]) {
            options |= NSCaseInsensitiveSearch;
        }
        
        NSRange searchRange = NSMakeRange(0, [text length]);
        NSRange foundRange;
        
        while (searchRange.location < [text length]) {
            // Check timeout
            if ([[NSDate date] timeIntervalSinceDate:startTime] > timeoutInterval) {
                break;
            }
            
            // Check max highlights limit
            if ([currentHighlightRanges count] >= maxHighlights) {
                break;
            }
            
            foundRange = [text rangeOfString:findString options:options range:searchRange];
            
            if (foundRange.location == NSNotFound) break;
            
            [currentHighlightRanges addObject:[NSValue valueWithRange:foundRange]];
            
            searchRange.location = foundRange.location + foundRange.length;
            searchRange.length = [text length] - searchRange.location;
        }
    }
    
    if ([currentHighlightRanges count] == 0) {
        currentHighlightRanges = nil;
        highlightViews = nil;
        [FindHighlightState setHasActiveHighlights:NO];
        
        // Clear the overlay when no matches are found
        [self clearFindHighlights];
        return;
    }
    
    [FindHighlightState setHasActiveHighlights:YES];
    
    // Create visual highlights
    NSScrollView *scrollView = [textView enclosingScrollView];
    NSView *containerView = [scrollView documentView];
    
    // Create dimming overlay if needed
    BOOL needsFadeIn = NO;
    if (!dimOverlay) {
        dimOverlay = [[PassThroughView alloc] initWithFrame:[containerView bounds]];
        [dimOverlay setWantsLayer:YES];
        CALayer *layer = [dimOverlay layer];
        [layer setBackgroundColor:[[NSColor colorWithCalibratedWhite:0.0 alpha:0.3] CGColor]];
        [dimOverlay setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [dimOverlay setAlphaValue:0.0];
        needsFadeIn = YES;
    }
    
    [dimOverlay setFrame:[containerView bounds]];
    
    if (![dimOverlay superview]) {
        [containerView addSubview:dimOverlay positioned:NSWindowAbove relativeTo:nil];
    }
    
    if (needsFadeIn) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            [context setDuration:0.15];
            [[dimOverlay animator] setAlphaValue:1.0];
        } completionHandler:nil];
    }
    
    // Create highlight views for each match
    NSLayoutManager *layoutManager = [textView layoutManager];
    NSTextContainer *textContainer = [textView textContainer];
    NSRange selectedRange = [textView selectedRange];
    
    for (NSValue *rangeValue in currentHighlightRanges) {
        // Check timeout for view creation
        if ([[NSDate date] timeIntervalSinceDate:startTime] > timeoutInterval) {
            break;
        }
        
        NSRange range = [rangeValue rangeValue];
        
        // Skip the currently selected match
        if (NSEqualRanges(range, selectedRange)) {
            continue;
        }
        
        NSRange glyphRange = [layoutManager glyphRangeForCharacterRange:range actualCharacterRange:NULL];
        NSRect boundingRect = [layoutManager boundingRectForGlyphRange:glyphRange inTextContainer:textContainer];
        
        PassThroughView *highlightView = [[PassThroughView alloc] initWithFrame:boundingRect];
        [highlightView setWantsLayer:YES];
        CALayer *layer = [highlightView layer];
        [layer setBackgroundColor:[[NSColor colorWithCalibratedWhite:1.0 alpha:0.20] CGColor]];
        [highlightView setAlphaValue:0.0];
        
        [containerView addSubview:highlightView positioned:NSWindowAbove relativeTo:dimOverlay];
        [highlightViews addObject:highlightView];
    }
    
    // Fade in highlight views
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [context setDuration:0.15];
        for (NSView *view in highlightViews) {
            [[view animator] setAlphaValue:1.0];
        }
    } completionHandler:nil];
}

- (void)clearFindHighlightsForUpdate {
    // Clear highlights immediately without animation when updating
    if (highlightViews) {
        for (NSView *view in highlightViews) {
            [view removeFromSuperview];
        }
        highlightViews = nil;
    }
    
    currentHighlightRanges = nil;
}

- (void)clearFindHighlights {
    [FindHighlightState setHasActiveHighlights:NO];
    
    if (dimOverlay) {
        isAnimatingOut = YES;
        
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            [context setDuration:0.15];
            [[dimOverlay animator] setAlphaValue:0.0];
            
            for (NSView *view in highlightViews) {
                [[view animator] setAlphaValue:0.0];
            }
        } completionHandler:^{
            if (isAnimatingOut) {
                [dimOverlay removeFromSuperview];
                dimOverlay = nil;
                
                if (highlightViews) {
                    for (NSView *view in highlightViews) {
                        [view removeFromSuperview];
                    }
                    highlightViews = nil;
                }
                isAnimatingOut = NO;
            }
        }];
    } else {
        if (highlightViews) {
            for (NSView *view in highlightViews) {
                [view removeFromSuperview];
            }
            highlightViews = nil;
        }
    }
    
    currentHighlightRanges = nil;
}

@end

// MARK: - Text View Implementation

@implementation _FindHighlightAll_CHFullTextView

- (void)mouseDown:(NSEvent *)event {
    // Clear highlights when clicking in text view (matches Chocolat's native behavior)
    if ([FindHighlightState hasActiveHighlights]) {
        NSView *findView = [self findXBFileFindView];
        if (findView && [findView respondsToSelector:@selector(clearFindHighlights)]) {
            [findView performSelector:@selector(clearFindHighlights)];
        }
    }
    
    ZKOrig(void, event);
}

- (NSView *)findXBFileFindView {
    NSWindow *window = [self window];
    return [self findViewOfClass:@"XBFileFindView" inView:[window contentView] depth:0];
}

- (NSView *)findViewOfClass:(NSString *)className inView:(NSView *)view depth:(int)depth {
    if (depth > 10) return nil; // Prevent infinite recursion
    
    if ([view isKindOfClass:NSClassFromString(className)]) {
        return view;
    }
    
    for (NSView *subview in [view subviews]) {
        NSView *found = [self findViewOfClass:className inView:subview depth:depth+1];
        if (found) return found;
    }
    
    return nil;
}

- (void)scrollRangeToVisible:(NSRange)range {
    ZKOrig(void, range);
    
    // Update highlights immediately when scrolling to a match
    NSView *findView = nil;
    NSArray *subviews = [[[self enclosingScrollView] superview] subviews];
    for (NSView *view in subviews) {
        if ([view isKindOfClass:NSClassFromString(@"XBFileFindView")]) {
            findView = view;
            break;
        }
    }
    
    if (findView && [findView respondsToSelector:@selector(updateFindHighlights)]) {
        [findView performSelector:@selector(updateFindHighlights)];
    }
}

- (void)setString:(NSString *)string {
    ZKOrig(void, string);
    
    // Schedule update when text changes
    NSView *findView = nil;
    NSArray *subviews = [[[self enclosingScrollView] superview] subviews];
    for (NSView *view in subviews) {
        if ([view isKindOfClass:NSClassFromString(@"XBFileFindView")]) {
            findView = view;
            break;
        }
    }
    
    if (findView && [findView respondsToSelector:@selector(scheduleUpdateFindHighlights)]) {
        [findView performSelector:@selector(scheduleUpdateFindHighlights)];
    }
}

@end
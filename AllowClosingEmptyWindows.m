/*
 * Allow using file > close (or cmd-w) to close a window even if no document is open.
 */

#import <objc/runtime.h>
#import <objc/message.h>
#import <Cocoa/Cocoa.h>
#import "ZKSwizzle/ZKSwizzle.h"
#define EMPTY_SWIZZLE_INTERFACE(CLASS_NAME, SUPERCLASS) @interface CLASS_NAME : SUPERCLASS @end

EMPTY_SWIZZLE_INTERFACE(ChocolatModifier_CHApplicationController_CloseCmdWEmptyWindow, NSObject);
@implementation ChocolatModifier_CHApplicationController_CloseCmdWEmptyWindow

- (void)primaryCloseMenuItem:(id)sender {
    // Get the key window
    NSWindow *keyWindow = [[NSApplication sharedApplication] keyWindow];
    id windowController = [keyWindow windowController];
    id activeTab = [windowController performSelector:@selector(activeTab)];

    id visibleSplitControllers = [activeTab performSelector:@selector(visibleSplitControllers)];
    NSUInteger splitCount = [visibleSplitControllers count];
    
    if (splitCount == 0) {
        // No documents open, close the window
        [keyWindow close];
        return;
    }
    
    // Call original
    ZKOrig(void, sender);
}

@end

@implementation NSObject (ChocolatModifier_CloseCmdWEmptyWindow)
+ (void)load {
    ZKSwizzle(ChocolatModifier_CHApplicationController_CloseCmdWEmptyWindow, CHApplicationController);
}
@end
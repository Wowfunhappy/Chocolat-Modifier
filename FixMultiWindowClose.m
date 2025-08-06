/*
*
* Closing a file in one window should not close the file in the other window!
*	
*/

#import <objc/runtime.h>
#import <objc/message.h>
#import <Cocoa/Cocoa.h>
#import "ZKSwizzle/ZKSwizzle.h"
#define EMPTY_SWIZZLE_INTERFACE(CLASS_NAME, SUPERCLASS) @interface CLASS_NAME : SUPERCLASS @end

EMPTY_SWIZZLE_INTERFACE(ChocolatModifier_CHSingleFileDocument_FixMultiWindowClose, NSDocument);
@implementation ChocolatModifier_CHSingleFileDocument_FixMultiWindowClose

static NSMutableDictionary *windowCountCache = nil;

+ (void)initialize {
    if (self == [ChocolatModifier_CHSingleFileDocument_FixMultiWindowClose class]) {
        windowCountCache = [[NSMutableDictionary alloc] init];
    }
}

- (void)willCloseOrSplitClosed {
    NSString *path = [[self fileURL] path];
    if (path) {
        // Count unique window controllers before split is removed
        id splits = [self performSelector:@selector(splitControllers)];
        NSMutableSet *controllers = [NSMutableSet set];
        
        for (id split in splits) {
            id controller = [split performSelector:@selector(windowController)];
            if (controller) [controllers addObject:controller];
        }
        
        [windowCountCache setObject:@([controllers count]) forKey:path];
    }
    
    ZKOrig(void);
}

- (void)close {
    NSString *path = [[self fileURL] path];
    NSNumber *previousCount = path ? [windowCountCache objectForKey:path] : nil;
    
    // If document was in multiple windows, don't close
    if (previousCount && [previousCount integerValue] > 1) {
        if (path) [windowCountCache removeObjectForKey:path];
        return;
    }
    
    // Clean up and proceed with close
    if (path) [windowCountCache removeObjectForKey:path];
    ZKOrig(void);
}

@end

@implementation NSObject (ChocolatModifier_FixMultiWindowClose)
+ (void)load {
    ZKSwizzle(ChocolatModifier_CHSingleFileDocument_FixMultiWindowClose, CHSingleFileDocument);
}
@end
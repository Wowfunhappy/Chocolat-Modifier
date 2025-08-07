#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <AppKit/AppKit.h>

@interface AddHelpBook : NSObject
@end

@implementation AddHelpBook

+ (void)load {
    // Register the Help Book with the system
    dispatch_async(dispatch_get_main_queue(), ^{
        // The Help Book is already in Info.plist, just need to ensure the help system recognizes it
        [[NSHelpManager sharedHelpManager] registerBooksInBundle:[NSBundle mainBundle]];
    });
}

@end
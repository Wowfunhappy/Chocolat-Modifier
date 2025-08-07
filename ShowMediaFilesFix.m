//
//  ShowMediaFilesFix.m
//  Chocolat Modifier
//
//  Makes the "Show Media Files" menu item work properly.
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "ZKSwizzle/ZKSwizzle.h"

// Fix the toggleMediaShown: action and menu validation
@interface ChocolatModifier_CHApplicationController_ShowMediaFix : NSObject
@end

@implementation ChocolatModifier_CHApplicationController_ShowMediaFix

- (void)toggleMediaShown:(id)sender {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // Get current value and toggle it
    BOOL currentValue = [defaults boolForKey:@"CHShowMediaInProjectBar"];
    BOOL newValue = !currentValue;
    [defaults setBool:newValue forKey:@"CHShowMediaInProjectBar"];
    [defaults synchronize];
    
    // Update the menu item state immediately
    // CHShowMediaInProjectBar: YES = hide media (menu unchecked), NO = show media (menu checked)
    if ([sender isKindOfClass:[NSMenuItem class]]) {
        NSMenuItem *menuItem = (NSMenuItem *)sender;
        [menuItem setState:newValue ? NSOffState : NSOnState];
    }
    
    // Call original to refresh the file listings
    ZKOrig(void, sender);
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
    // Handle "Show Media Files" menu item
    if ([menuItem action] == @selector(toggleMediaShown:)) {
        // CHShowMediaInProjectBar: YES = hide media (menu unchecked), NO = show media (menu checked)
        BOOL prefValue = [[NSUserDefaults standardUserDefaults] boolForKey:@"CHShowMediaInProjectBar"];
        [menuItem setState:prefValue ? NSOffState : NSOnState];
        return YES; // Enable the menu item
    }
    
    return ZKOrig(BOOL, menuItem);
}

@end

@implementation NSObject (ChocolatModifier_ShowMediaFilesFix)
+ (void)load {
    ZKSwizzle(ChocolatModifier_CHApplicationController_ShowMediaFix, CHApplicationController);
}
@end
/*
* 
* If "Close windows when quitting an application" is disabled in System Preferences,
* Chocolat will restore windows when it is quit and re-opened.
* Not everything is restored perfectly, but it works well enough.
* 
*/

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "ZKSwizzle/ZKSwizzle.h"
#define EMPTY_SWIZZLE_INTERFACE(CLASS_NAME, SUPERCLASS) @interface CLASS_NAME : SUPERCLASS @end

EMPTY_SWIZZLE_INTERFACE(ChocolatModifier_NSUserDefaults, NSUserDefaults);
@implementation ChocolatModifier_NSUserDefaults
- (void)setObject:(id)value forKey:(NSString *)defaultName {
	// Ignore attempts to set NSQuitAlwaysKeepsWindows
	if ([defaultName isEqualToString:@"NSQuitAlwaysKeepsWindows"]) {
		return;
	}
	// For all other keys, call the original implementation
	ZKOrig(void, value, defaultName);
}
@end

EMPTY_SWIZZLE_INTERFACE(ChocolatModifier_CHApp, NSApplication);
@implementation ChocolatModifier_CHApp

- (BOOL)_doOpenUntitled {
	// If NSQuitAlwaysKeepsWindows is enabled, check if we're in the process of restoring windows
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"NSQuitAlwaysKeepsWindows"]) {
		// Check if we have saved window state
		NSArray *savedWindows = [[NSUserDefaults standardUserDefaults] objectForKey:@"ChocolatModifier_SavedWindows"];
		if (savedWindows && [savedWindows count] > 0) {

			// Manually trigger window restoration since the system isn't calling it
			dispatch_async(dispatch_get_main_queue(), ^{
				NSDocumentController *docController = [NSDocumentController sharedDocumentController];
				for (NSString *path in savedWindows) {
					NSURL *url = [NSURL fileURLWithPath:path];
					[docController openDocumentWithContentsOfURL:url display:YES error:nil];
				}

				// Clear the saved windows after restoring
				[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"ChocolatModifier_SavedWindows"];
			});

			return NO; // Don't open untitled window during restoration
		}
	}

	// Otherwise use original behavior
	BOOL result = ZKOrig(BOOL);
	return result;
}

@end

// Swizzle CHApplicationController to save open windows on termination
EMPTY_SWIZZLE_INTERFACE(ChocolatModifier_CHApplicationController_ReopenWindows, NSObject);
@implementation ChocolatModifier_CHApplicationController_ReopenWindows

- (void)terminate:(id)sender {

	// Save currently open document windows
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"NSQuitAlwaysKeepsWindows"]) {
		NSMutableArray *openDocuments = [NSMutableArray array];

		// Get all windows
		for (NSWindow *window in [[NSApplication sharedApplication] windows]) {
			NSWindowController *windowController = [window windowController];
			if (!windowController) continue;
			
			// Skip window controllers that don't have tabControllers (like preferences)
			if (![windowController respondsToSelector:@selector(tabControllers)]) continue;
			
			// Get all tab controllers from the window controller
			NSArray *tabControllers = [windowController performSelector:@selector(tabControllers)];
			
			// Process each tab controller
			for (id tabController in tabControllers) {
				// Get active documents from the tab controller
				NSArray *activeDocuments = [tabController performSelector:@selector(activeDocumentsArray)];
				
				// Save paths for all active documents
				for (id document in activeDocuments) {
					NSURL *url = [document performSelector:@selector(fileURL)];
					if (url) {
						NSString *path = [url path];
						if (![openDocuments containsObject:path]) {
							[openDocuments addObject:path];
						}
					}
				}
			}
		}

		if ([openDocuments count] > 0) {
			[[NSUserDefaults standardUserDefaults] setObject:openDocuments forKey:@"ChocolatModifier_SavedWindows"];
			[[NSUserDefaults standardUserDefaults] synchronize];
		} else {
			[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"ChocolatModifier_SavedWindows"];
		}
	}

	ZKOrig(void, sender);
}

@end

@implementation NSObject (ChocolatModifier_ReopenWindows)
+ (void)load {
	ZKSwizzle(ChocolatModifier_NSUserDefaults, NSUserDefaults);
	ZKSwizzle(ChocolatModifier_CHApp, CHApp);
	ZKSwizzle(ChocolatModifier_CHApplicationController_ReopenWindows, CHApplicationController);
}
@end
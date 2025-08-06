/*
 *
 * Removes support for tabs.
 * 
 * Tabs mostly don't make sense in the context of how Chocolat works, and their presence initially confused me
 * about the expected workflow. Furthermore, they don't work well! For example, as far as I can tell there's no way to move a tab to a
 * seperate window.
 * 
 * The original developers reportedly discussed removing tabs from the app. Let's go ahead and actually do it.
 *  
 */

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "ZKSwizzle/ZKSwizzle.h"
#define EMPTY_SWIZZLE_INTERFACE(CLASS_NAME, SUPERCLASS) @interface CLASS_NAME : SUPERCLASS @end

// Swizzle CHApplicationController to remove menu items
EMPTY_SWIZZLE_INTERFACE(ChocolatModifier_CHApplicationController_RemoveTabs, NSObject);
@implementation ChocolatModifier_CHApplicationController_RemoveTabs

// Helper method to remove menu items by action selector
- (void)removeMenuItemsWithActions:(NSArray *)actions fromMenu:(NSMenu *)menu {
	NSMutableArray *itemsToRemove = [NSMutableArray array];
	
	for (NSMenuItem *item in [menu itemArray]) {
		NSString *actionString = NSStringFromSelector([item action]);
		if (actionString) {
			for (NSString *action in actions) {
				if ([actionString isEqualToString:action]) {
					[itemsToRemove addObject:item];
					break;
				}
			}
		}
	}
	
	for (NSMenuItem *item in itemsToRemove) {
		[menu removeItem:item];
	}
}

- (void)cleanupSeparatorsInMenu:(NSMenu *)menu {
	NSArray *items = [[menu itemArray] copy];
	NSMenuItem *previousItem = nil;
	
	for (NSMenuItem *item in items) {
		if ([item isSeparatorItem] && (!previousItem || [previousItem isSeparatorItem])) {
			// Remove duplicate separator or separator at beginning
			[menu removeItem:item];
		} else {
			previousItem = item;
		}
	}
	
	// Remove separator at end if exists
	if ([[menu itemArray] count] > 0 && [[[menu itemArray] lastObject] isSeparatorItem]) {
		[menu removeItem:[[menu itemArray] lastObject]];
	}
}

- (void)awakeFromNib {
	// Call original implementation
	ZKOrig(void);
	
	// Delay menu modification to ensure menus are fully loaded
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		
		// Get the main menu
		NSMenu *mainMenu = [NSApp mainMenu];
		
		// Remove from File menu
		NSMenuItem *fileMenuItem = [mainMenu itemWithTitle:@"File"];
		if (fileMenuItem && [fileMenuItem hasSubmenu]) {
			NSMenu *fileMenu = [fileMenuItem submenu];
			[self removeMenuItemsWithActions:@[
				@"newWorkspace:",
				@"newUntitledDocumentTab:"
			] fromMenu:fileMenu];
		}
		
		// Remove from Window menu
		NSMenuItem *windowMenuItem = [mainMenu itemWithTitle:@"Window"];
		if (windowMenuItem && [windowMenuItem hasSubmenu]) {
			NSMenu *windowMenu = [windowMenuItem submenu];
			[self removeMenuItemsWithActions:@[
				@"selectPreviousTab:",
				@"selectNextTab:",
				@"previousTab:",
				@"nextTab:",
				@"moveTabToNewWindow:",
				@"mergeAllWindows:"
			] fromMenu:windowMenu];
			
			// Remove any "Move Tab to..." items by checking their action patterns
			NSMutableArray *moveTabItems = [NSMutableArray array];
			for (NSMenuItem *item in [windowMenu itemArray]) {
				NSString *actionString = NSStringFromSelector([item action]);
				if (actionString && [actionString rangeOfString:@"moveTabTo"].location != NSNotFound) {
					[moveTabItems addObject:item];
				}
			}
			for (NSMenuItem *item in moveTabItems) {
						[windowMenu removeItem:item];
			}
			
			// Clean up any double separators that might result
			[self cleanupSeparatorsInMenu:windowMenu];
		}
	});
}

- (void)newUntitledDocumentTab:(id)sender {
	// Open in new window instead of tab
	[[NSDocumentController sharedDocumentController] newDocument:sender];
}

- (id)newUntitledTabForDocument:(id)document existingWindowController:(id)windowController {
	// Check if the window controller already has a tab
	id tabView = [windowController valueForKey:@"tabView"];
	NSInteger tabCount = tabView ? [tabView numberOfTabViewItems] : 0;
	
	if (tabCount == 0) {
		return ZKOrig(id, document, windowController);
	} else {
		// Force new window by passing nil
		return ZKOrig(id, document, nil);
	}
}

@end

@interface splendidBarController : NSObject
-(void)closeButtonForItem:item;
@end

@interface CHSplendidListItem_Document : NSObject
@property (weak) id document;
@end

// Swizzle CHClosingController to fix Cmd+W behavior
@interface ChocolatModifier_CHClosingController : NSObject
- (BOOL)splitDocumentStillOpen:(id)context;
- (void)closeSplitInContext:(id)context;
@end

@implementation ChocolatModifier_CHClosingController

- (BOOL)splitDocumentStillOpen:(id)context {
	// Call original implementation
	return ZKOrig(BOOL, context);
}

- (void)closeSplitInContext:(id)context {
	if ([[[NSDocumentController sharedDocumentController] documents] count] > 1) {
		id splitController = [context valueForKey:@"splitController"];
		id viewDocument = [splitController valueForKey:@"viewDocument"];
		id splendidBarController = [context valueForKey:@"splendidBarController"];
		
		Class itemClass = NSClassFromString(@"CHSplendidListItem_Document");
		id item = [[itemClass alloc] init];
		[item setDocument:viewDocument];
		
		[splendidBarController closeButtonForItem: item];
	} else {
		ZKOrig(void, context);
	}
}

@end

// Swizzle CHTabController to disable additional tab creation
EMPTY_SWIZZLE_INTERFACE(ChocolatModifier_CHTabController, NSWindowController);
@implementation ChocolatModifier_CHTabController

- (void)createNewTab {
	
	// Check if this is the first tab - if so, allow it
	id tabBar = [self valueForKey:@"tabBar"];
	id tabView = [tabBar valueForKey:@"tabView"];
	NSInteger tabCount = [tabView numberOfTabViewItems];
	
	if (tabCount == 0) {
		// Allow the first tab
		ZKOrig(void);
	} else {
		// For additional tabs, open a new window
		NSDocumentController *docController = [NSDocumentController sharedDocumentController];
		[docController newDocument:nil];
	}
}

- (void)moveSplitViewsToTabs:(id)sender {
	// Get all split controllers
	NSArray *splits = [self valueForKey:@"splitControllers"];
	if ([splits count] <= 1) return;
	
	// Keep the first split in current window, move others to new windows
	for (int i = 1; i < [splits count]; i++) {
		id splitController = [splits objectAtIndex:i];
		id document = [splitController valueForKey:@"viewDocument"];
		if (document) {
			// Open document in new window
			NSDocumentController *docController = [NSDocumentController sharedDocumentController];
			[docController openDocument:nil];
		}
	}
	
	// Don't call original since we're handling it differently
}

@end

// Swizzle CHWindowController to force single tab mode
EMPTY_SWIZZLE_INTERFACE(ChocolatModifier_CHWindowController, NSWindowController);
@implementation ChocolatModifier_CHWindowController

- (BOOL)shouldBeNoTabView {
	// Check if we have more than one tab
	id tabView = [self valueForKey:@"tabView"];
	NSInteger tabCount = [tabView numberOfTabViewItems];
	
	// Hide tab bar if we have 0 or 1 tabs
	if (tabCount <= 1) {
		return YES;
	}
	
	// Otherwise use original behavior
	return ZKOrig(BOOL);
}

- (void)addTab:(id)tabController {
	
	// Check current tab count
	id tabView = [self valueForKey:@"tabView"];
	NSInteger tabCount = [tabView numberOfTabViewItems];
	
	if (tabCount == 0) {
		// Allow the first tab
		ZKOrig(void, tabController);
	} else {
		// For additional tabs, open document in a new window
		if ([tabController respondsToSelector:@selector(splitControllers)]) {
			NSArray *splits = [tabController valueForKey:@"splitControllers"];
			if ([splits count] > 0) {
				id splitController = [splits objectAtIndex:0];
				id document = [splitController valueForKey:@"viewDocument"];
				if (document) {
					// Create new window for this document
					id appController = [[NSApplication sharedApplication] delegate];
					if ([appController respondsToSelector:@selector(newUntitledTabForDocument:existingWindowController:)]) {
						// Force new window by passing nil
						objc_msgSend(appController, @selector(newUntitledTabForDocument:existingWindowController:), document, nil);
					} else {
						// Fallback
						NSDocumentController *docController = [NSDocumentController sharedDocumentController];
						[docController openDocument:nil];
					}
				}
			}
		}
	}
}

- (void)showTabBar {
	// Only show tab bar if we have more than one tab
	id tabView = [self valueForKey:@"tabView"];
	NSInteger tabCount = [tabView numberOfTabViewItems];
	
	if (tabCount > 1) {
		ZKOrig(void);
	}
}

@end

// Swizzle directory/file items to redirect tab operations
EMPTY_SWIZZLE_INTERFACE(ChocolatModifier_CHSplendidListItem_Directory, NSObject);
@implementation ChocolatModifier_CHSplendidListItem_Directory

- (void)openInNewTab:(id)sender {
	// Don't call original - we're replacing the functionality
	// Try to call openInNewWindow if available
	SEL openInNewWindowSelector = @selector(openInNewWindow:);
	if ([self respondsToSelector:openInNewWindowSelector]) {
		objc_msgSend(self, openInNewWindowSelector, sender);
	} else {
		// Fallback: open in new document window
		NSDocumentController *docController = [NSDocumentController sharedDocumentController];
		[docController openDocument:sender];
	}
}

@end

// Swizzle CHSplendidList_DirectoryListing to remove "Open in New Tab" from context menu
EMPTY_SWIZZLE_INTERFACE(ChocolatModifier_CHSplendidList_DirectoryListing, NSObject);
@implementation ChocolatModifier_CHSplendidList_DirectoryListing

- (NSMenu *)contextMenuForOutline:(id)outline {
	// Get the original context menu
	NSMenu *menu = ZKOrig(NSMenu *, outline);
	
	if (menu) {
		// Remove "Open in New Tab" menu item
		NSMenuItem *openInNewTabItem = nil;
		
		for (NSMenuItem *item in [menu itemArray]) {
			if ([[item title] isEqualToString:@"Open in New Tab"] ||
			    (item.action && NSStringFromSelector(item.action) && 
			     [NSStringFromSelector(item.action) isEqualToString:@"openInNewTab:"])) {
				openInNewTabItem = item;
				break;
			}
		}
		
		if (openInNewTabItem) {
			[menu removeItem:openInNewTabItem];
		}
	}
	
	return menu;
}

@end

@implementation NSObject (ChocolatModifier_RemoveTabs)
+ (void)load {
	ZKSwizzle(ChocolatModifier_CHApplicationController_RemoveTabs, CHApplicationController);
	ZKSwizzle(ChocolatModifier_CHClosingController, CHClosingController);
	ZKSwizzle(ChocolatModifier_CHTabController, CHTabController);
	ZKSwizzle(ChocolatModifier_CHWindowController, CHWindowController);
	ZKSwizzle(ChocolatModifier_CHSplendidListItem_Directory, CHSplendidListItem_Directory);
	ZKSwizzle(ChocolatModifier_CHSplendidList_DirectoryListing, CHSplendidList_DirectoryListing);
}
@end
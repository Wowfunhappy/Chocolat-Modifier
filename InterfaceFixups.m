/*
 * This file makes changes to Chocolat's UI. Each change was made for one of the following reasons:
 * 1. In the wrong place per Apple guidelines
 * 2. Option doesn't make sense now that the app is dead
 * 		Example: check for update
 * 3. Option doesn't make sense in ancient OS X.
 * 		Example: Web Preview, Documentation. (Because WebKit is too old to load anything.)
 * 
 * In addition, splits were removed (outside of one specific scenario where they work well) because they are buggy.
 * Splits are a nice enough feature, but not nice enough to spend time fixing.
 * Just open the file in a separate window instead.
 * 
 */


#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "ZKSwizzle/ZKSwizzle.h"
#define EMPTY_SWIZZLE_INTERFACE(CLASS_NAME, SUPERCLASS) @interface CLASS_NAME : SUPERCLASS @end

// -- Move Scale menu from Window to View and reorganize View menu

EMPTY_SWIZZLE_INTERFACE(ChocolatModifier_CHApplicationController_MenuFixups, NSObject);
@implementation ChocolatModifier_CHApplicationController_MenuFixups

- (void)awakeFromNib {
	// Call original implementation
	ZKOrig(void);
	
	// Delay menu modification to ensure menus are fully loaded
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		
		// Get the main menu
		NSMenu *mainMenu = [NSApp mainMenu];
		
		// Remove items from Chocolat menu
		NSMenuItem *chocolatMenuItem = [mainMenu itemAtIndex:0];
		NSMenu *chocolatMenu = [chocolatMenuItem submenu];
		
		NSMutableArray *itemsToRemove = [NSMutableArray array];
		for (NSMenuItem *item in [chocolatMenu itemArray]) {
			SEL action = [item action];
			if (action == @selector(openKeyBindings:) ||
			    action == @selector(deactivate:) ||
			    action == @selector(checkForUpdates:)) {
				[itemsToRemove addObject:item];
			}
		}
		
		for (NSMenuItem *item in itemsToRemove) {
			[chocolatMenu removeItem:item];
		}
		
		// Find Window, View and Go menus
		NSMenuItem *windowMenuItem = [mainMenu itemWithTitle:@"Window"];
		NSMenuItem *viewMenuItem = [mainMenu itemWithTitle:@"View"];
		NSMenuItem *goMenuItem = [mainMenu itemWithTitle:@"Go"];
		
		NSMenu *windowMenu = [windowMenuItem submenu];
		NSMenu *viewMenu = [viewMenuItem submenu];
		NSMenu *goMenu = [goMenuItem submenu];
		
		// Find and remove Scale submenu from Window menu
		NSMenuItem *scaleMenuItem = nil;
		for (NSMenuItem *item in [windowMenu itemArray]) {
			if ([[item title] isEqualToString:@"Scale"]) {
				scaleMenuItem = item;
				break;
			}
		}
		
		NSInteger scaleIndex = [windowMenu indexOfItem:scaleMenuItem];
		[windowMenu removeItem:scaleMenuItem];
		
		// Remove separator that was below Scale
		[windowMenu removeItemAtIndex:scaleIndex];
		
		[viewMenu insertItem:scaleMenuItem atIndex:10];
		
		// Remove Documentation and Web Preview from View menu
		NSMutableArray *viewItemsToRemove = [NSMutableArray array];
		for (NSMenuItem *item in [viewMenu itemArray]) {
			SEL action = [item action];
			if (action == @selector(toggleDocumentationSplit:) ||
			    action == @selector(toggleWebPreviewSplit:)) {
				[viewItemsToRemove addObject:item];
			}
		}
		
		for (NSMenuItem *item in viewItemsToRemove) {
			[viewMenu removeItem:item];
		}
		
		// Find and move Enter/Exit Full Screen to bottom
		NSMenuItem *fullScreenItem = nil;
		for (NSMenuItem *item in [viewMenu itemArray]) {
			NSString *title = [item title];
			if ([title rangeOfString:@"Full Screen"].location != NSNotFound) {
				fullScreenItem = item;
				break;
			}
		}
		
		[viewMenu removeItem:fullScreenItem];
		
		// Add separator and full screen at bottom
		[viewMenu addItem:[NSMenuItem separatorItem]];
		[viewMenu addItem:fullScreenItem];
		
		// Remove Jump to Documentation, Next Split, and Previous Split from Go menu
		NSMutableArray *goItemsToRemove = [NSMutableArray array];
		for (NSMenuItem *item in [goMenu itemArray]) {
			SEL action = [item action];
			if (action == @selector(jumpToDocumentation:) ||
			    action == @selector(makeLeftSplitActive:) ||
			    action == @selector(makeRightSplitActive:)) {
				[goItemsToRemove addObject:item];
			}
		}
		
		for (NSMenuItem *item in goItemsToRemove) {
			[goMenu removeItem:item];
		}
		
		// Remove the second to last item (duplicate separator)
		[goMenu removeItemAtIndex:[[goMenu itemArray] count] - 3];
		
		// Remove Split menu items from File menu and rename "Close Window" to "Close"
		NSMenuItem *fileMenuItem = [mainMenu itemWithTitle:@"File"];
		NSMenu *fileMenu = [fileMenuItem submenu];
		
		// Remove split menu items
		NSMutableArray *fileItemsToRemove = [NSMutableArray array];
		for (NSMenuItem *item in [fileMenu itemArray]) {
			SEL action = [item action];
			if (action == @selector(newSplitView:)) {
				[fileItemsToRemove addObject:item];
			}
		}
		
		for (NSMenuItem *item in fileItemsToRemove) {
			[fileMenu removeItem:item];
		}
		
		[fileMenu insertItem:[NSMenuItem separatorItem] atIndex:18];

		NSMenuItem *openInNewWindowItem = [[NSMenuItem alloc] initWithTitle:@"Open in New Window" action:@selector(openInNewWindow:) keyEquivalent:@""];
		[openInNewWindowItem setTarget:self];
		[fileMenu insertItem:openInNewWindowItem atIndex:22];

		// Fix Help menu
		NSMenuItem *helpMenuItem = [mainMenu itemWithTitle:@"Help"];
		NSMenu *helpMenu = [helpMenuItem submenu];
		
		// Remove "Chocolat Website" and "Report Bug..." items
		NSMutableArray *helpItemsToRemove = [NSMutableArray array];
		NSMenuItem *chocolatHelpItem = nil;
		
		for (NSMenuItem *item in [helpMenu itemArray]) {
			SEL action = [item action];
			if (action == @selector(visitWebsite:) ||
			    action == @selector(reportBug:)) {
				[helpItemsToRemove addObject:item];
			} else if (action == @selector(showHelp:)) {
				chocolatHelpItem = item;
			}
		}
		
		for (NSMenuItem *item in helpItemsToRemove) {
			[helpMenu removeItem:item];
		}
		
		// Remove separator that was between the items
		for (NSMenuItem *item in [[helpMenu itemArray] copy]) {
			if ([item isSeparatorItem]) {
				[helpMenu removeItem:item];
				break;
			}
		}
		
		// Make Chocolat Help show default OS X help message
		[chocolatHelpItem setAction:@selector(showHelp:)];
		[chocolatHelpItem setTarget:nil];
	});
}

- (void)openInNewWindow:(id)sender {
	// Get the current document
	NSDocumentController *documentController = [NSDocumentController sharedDocumentController];
	NSDocument *currentDocument = [documentController currentDocument];
	if (!currentDocument) {
		return;
	}
	
	// Get the file URL
	NSURL *fileURL = [currentDocument fileURL];
	if (!fileURL) {
		return;
	}
	
	// Open the document without displaying (to get the document object)
	NSError *error = nil;
	SEL superOpenSelector = @selector(super_openDocumentWithContentsOfURL:display:error:);
	
	if ([documentController respondsToSelector:superOpenSelector]) {
		// Use NSInvocation to call the method
		NSMethodSignature *signature = [documentController methodSignatureForSelector:superOpenSelector];
		NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
		[invocation setTarget:documentController];
		[invocation setSelector:superOpenSelector];
		[invocation setArgument:&fileURL atIndex:2];
		BOOL displayFlag = NO;
		[invocation setArgument:&displayFlag atIndex:3];
		[invocation setArgument:&error atIndex:4];
		[invocation invoke];
		
		// Get the return value (the document)
		id document = nil;
		[invocation getReturnValue:&document];
		
		if (document) {
			// Clear existing window controller
			SEL setExistingWindowControllerSelector = @selector(setExistingWindowController:);
			if ([document respondsToSelector:setExistingWindowControllerSelector]) {
				[document performSelector:setExistingWindowControllerSelector withObject:nil];
			}
			
			// Create new window controllers
			SEL makeWindowControllersSelector = @selector(makeWindowControllersForceHideSplendidBar:);
			if ([document respondsToSelector:makeWindowControllersSelector]) {
				NSMethodSignature *makeWindowSig = [document methodSignatureForSelector:makeWindowControllersSelector];
				NSInvocation *makeWindowInvocation = [NSInvocation invocationWithMethodSignature:makeWindowSig];
				[makeWindowInvocation setTarget:document];
				[makeWindowInvocation setSelector:makeWindowControllersSelector];
				BOOL forceHide = YES;
				[makeWindowInvocation setArgument:&forceHide atIndex:2];
				[makeWindowInvocation invoke];
			}
		}
	}
}

@end

// -- Prevent CHApplicationController from overriding our menu title changes

EMPTY_SWIZZLE_INTERFACE(ChocolatModifier_CHApplicationController_ValidateMenuItem, NSObject);
@implementation ChocolatModifier_CHApplicationController_ValidateMenuItem

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	// Call original implementation first
	BOOL result = ZKOrig(BOOL, menuItem);
	
	// If this is a "Close Window" item that was reset, change it back to "Close"
	if ([[menuItem title] isEqualToString:@"Close Window"]) {
		[menuItem setTitle:@"Close"];
	}
	
	return result;
}

@end

// -- Hide the close split button in the status bar

EMPTY_SWIZZLE_INTERFACE(ChocolatModifier_CHEditorButtonBarFilenameComponent_HideSplitButton, NSView);
@implementation ChocolatModifier_CHEditorButtonBarFilenameComponent_HideSplitButton

- (id)initWithFrame:(CGRect)frame {
	// Call original implementation
	id result = ZKOrig(id, frame);
	
	// Hide the close button
	[[self valueForKey:@"closeButton"] setHidden:YES];
	
	return result;
}

@end

// -- Remove Register and Updates tabs from Preferences window

EMPTY_SWIZZLE_INTERFACE(ChocolatModifier_CHPreferencesController_RemoveTabs, NSObject);
@implementation ChocolatModifier_CHPreferencesController_RemoveTabs

- (void)windowDidLoad {
	// Call original implementation
	ZKOrig(void);
	
	// Remove the Register and Updates toolbar items
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		NSWindow *window = [(NSWindowController *)self window];
		NSToolbar *toolbar = [window toolbar];
		
		// Items to remove by their actual identifiers
		NSArray *itemsToRemove = @[@"register", @"600228E4-4C41-4BEB-9415-88816C0E0339"];
		
		NSArray *currentItems = [toolbar items];
		for (NSInteger i = [currentItems count] - 1; i >= 0; i--) {
			NSToolbarItem *item = [currentItems objectAtIndex:i];
			if ([itemsToRemove containsObject:[item itemIdentifier]]) {
				[toolbar removeItemAtIndex:i];
			}
		}
	});
}

@end

@implementation NSObject (ChocolatModifier_MenuFixups)
+ (void)load {
	ZKSwizzle(ChocolatModifier_CHApplicationController_MenuFixups, CHApplicationController);
	ZKSwizzle(ChocolatModifier_CHApplicationController_ValidateMenuItem, CHApplicationController);
	ZKSwizzle(ChocolatModifier_CHEditorButtonBarFilenameComponent_HideSplitButton, CHEditorButtonBarFilenameComponent);
	ZKSwizzle(ChocolatModifier_CHPreferencesController_RemoveTabs, CHPreferencesController);
}
@end
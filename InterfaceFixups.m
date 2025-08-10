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
		
		// Rename menu items
		for (NSMenuItem *menuItem in [mainMenu itemArray]) {
			NSMenu *submenu = [menuItem submenu];
			if (submenu) {
				for (NSMenuItem *item in [submenu itemArray]) {
					if ([[item title] isEqualToString:@"Reveal in Terminal"]) {
						[item setTitle:@"Open in Terminal"];
					}
				}
			}
		}
		
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
		
		if (scaleMenuItem) {
			NSInteger scaleIndex = [windowMenu indexOfItem:scaleMenuItem];
			[windowMenu removeItem:scaleMenuItem];
			
			// Remove separator that was below Scale if it exists
			if (scaleIndex < [[windowMenu itemArray] count]) {
				[windowMenu removeItemAtIndex:scaleIndex];
			}
			
			// Insert at a safe position in view menu
			NSInteger viewInsertIndex = MIN(10, [[viewMenu itemArray] count]);
			[viewMenu insertItem:scaleMenuItem atIndex:viewInsertIndex];
		}
		
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
		
		if (fullScreenItem) {
			[viewMenu removeItem:fullScreenItem];
			
			// Add separator and full screen at bottom
			[viewMenu addItem:[NSMenuItem separatorItem]];
			[viewMenu addItem:fullScreenItem];
		}
		
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
		
		// Remove the second to last item (duplicate separator) if menu has enough items
		if ([[goMenu itemArray] count] >= 3) {
			[goMenu removeItemAtIndex:[[goMenu itemArray] count] - 3];
		}
		
		// Reorganize Actions and Language menus
		NSMenuItem *actionsMenuItem = [mainMenu itemWithTitle:@"Actions"];
		NSMenuItem *textMenuItem = [mainMenu itemWithTitle:@"Text"];
		
		if (actionsMenuItem) {
			// Rename current "Actions" menu to "Language"
			[actionsMenuItem setTitle:@"Language"];
			NSMenu *languageMenu = [actionsMenuItem submenu];
			[languageMenu setTitle:@"Language"];
			
			// Find and move "Choose Language..." from Text menu to top of Language menu
			if (textMenuItem) {
				NSMenu *textMenu = [textMenuItem submenu];
				NSMenuItem *chooseLanguageItem = nil;
				for (NSMenuItem *item in [textMenu itemArray]) {
					if ([item action] == @selector(chooseLanguage:)) {
						chooseLanguageItem = item;
						break;
					}
				}
				if (chooseLanguageItem) {
					[textMenu removeItem:chooseLanguageItem];
					[languageMenu insertItem:chooseLanguageItem atIndex:0];
					[languageMenu insertItem:[NSMenuItem separatorItem] atIndex:1];
				}
				
				// Remove the first item (leading separator) from Text menu
				if ([[textMenu itemArray] count] > 0) {
					[textMenu removeItemAtIndex:0];
				}
			}
			
			// Create new Actions menu
			NSMenuItem *newActionsMenuItem = [[NSMenuItem alloc] initWithTitle:@"Action" action:nil keyEquivalent:@""];
			NSMenu *newActionsMenu = [[NSMenu alloc] initWithTitle:@"Action"];
			[newActionsMenuItem setSubmenu:newActionsMenu];
			
			// Find position of Language menu and insert new Actions menu after it
			NSInteger languageIndex = [mainMenu indexOfItem:actionsMenuItem];
			[mainMenu insertItem:newActionsMenuItem atIndex:languageIndex + 1];
			
			// Move Run, REPL, Build, Debug, and Check from Language menu to new Actions menu
			NSArray *actionsToMove = @[@"Run", @"REPL", @"Build", @"Debug", @"Check"];
			NSMutableArray *itemsToMove = [NSMutableArray array];
			NSMutableArray *separatorsToMove = [NSMutableArray array];
			
			for (NSMenuItem *item in [languageMenu itemArray]) {
				if ([actionsToMove containsObject:[item title]]) {
					[itemsToMove addObject:item];
				}
			}
			
			// Move the items to new Actions menu
			for (NSMenuItem *item in itemsToMove) {
				[languageMenu removeItem:item];
				[newActionsMenu addItem:item];
			}
			
			// Remove Install Mixins from Language menu
			NSMutableArray *languageItemsToRemove = [NSMutableArray array];
			for (NSMenuItem *item in [languageMenu itemArray]) {
				if ([item action] == @selector(openMixinInstaller:)) {
					[languageItemsToRemove addObject:item];
				}
			}
			for (NSMenuItem *item in languageItemsToRemove) {
				[languageMenu removeItem:item];
			}
			
			// Remove consecutive seperator Language menu
			[languageMenu removeItemAtIndex:6];
		}
		
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
		
		// Insert separator at safe position
		NSInteger fileSeparatorIndex = MIN(18, [[fileMenu itemArray] count]);
		[fileMenu insertItem:[NSMenuItem separatorItem] atIndex:fileSeparatorIndex];

		NSMenuItem *openInNewWindowItem = [[NSMenuItem alloc] initWithTitle:@"Open in New Window" action:@selector(openInNewWindow:) keyEquivalent:@""];
		[openInNewWindowItem setTarget:self];
		NSInteger fileItemIndex = MIN(22, [[fileMenu itemArray] count]);
		[fileMenu insertItem:openInNewWindowItem atIndex:fileItemIndex];

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

// -- Skip the Install Extras dialog and go directly to Install from File

@interface NSObject (CHInstallExtrasController_Methods)
- (void)installFromFile:(id)sender;
@end

EMPTY_SWIZZLE_INTERFACE(ChocolatModifier_CHInstallExtrasController_DirectInstall, NSObject);
@implementation ChocolatModifier_CHInstallExtrasController_DirectInstall

- (void)showWindow:(id)sender {
	// Skip showing the window and go directly to installFromFile
	[self installFromFile:sender];
}

@end

@implementation NSObject (ChocolatModifier_MenuFixups)
+ (void)load {
	ZKSwizzle(ChocolatModifier_CHApplicationController_MenuFixups, CHApplicationController);
	ZKSwizzle(ChocolatModifier_CHApplicationController_ValidateMenuItem, CHApplicationController);
	ZKSwizzle(ChocolatModifier_CHEditorButtonBarFilenameComponent_HideSplitButton, CHEditorButtonBarFilenameComponent);
	ZKSwizzle(ChocolatModifier_CHPreferencesController_RemoveTabs, CHPreferencesController);
	ZKSwizzle(ChocolatModifier_CHInstallExtrasController_DirectInstall, CHInstallExtrasController);
	
	// Disable Chocolat's crash reporting since the original developers are gone.
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"KOLastChecked"];
	[[NSUserDefaults standardUserDefaults] synchronize];
}
@end
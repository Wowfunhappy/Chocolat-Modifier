/*
 * Fix:
 * If you try to close an unsaved document, Chocolat would correctly warn you that you haven't saved.
 * However, clicking cancel in this dialog still remove the file from your active documents.
 * 
 */

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "ZKSwizzle/ZKSwizzle.h"
#define EMPTY_SWIZZLE_INTERFACE(CLASS_NAME, SUPERCLASS) @interface CLASS_NAME : SUPERCLASS @end

EMPTY_SWIZZLE_INTERFACE(ChocolatModifier_CHSplendidBarController_CloseFix, NSObject);
@implementation ChocolatModifier_CHSplendidBarController_CloseFix

- (void)closeButtonForItem:(id)item {
	id document = [item valueForKey:@"document"];
	id tabController = [self valueForKey:@"tabController"];
	
	if (!document || !tabController) {
		ZKOrig(void, item);
		return;
	}
	
	// Check if autosaving is enabled and document is dirty
	BOOL autoSaveEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"CHSaveOnDefocus"];
	if (autoSaveEnabled && [document isDocumentEdited]) {
		// Save the document automatically
		[document performSelector:@selector(saveDocument:) withObject:nil];
		
		// Remove the document from the tab
		[tabController performSelector:@selector(removeTabDocument:) withObject:document];
		[self performSelector:@selector(lineUpNextSelection)];
		return;
	}
	
	// Set window to not close when document closes
	id windowController = [tabController valueForKey:@"windowController"];
	[windowController performSelector:@selector(setDoNotCloseWindowOnClose:) withObject:@(YES)];
	
	// Create completion block that defers document removal
	__weak typeof(self) weakSelf = self;
	void (^completionBlock)(BOOL) = ^(BOOL shouldClose) {
		if (shouldClose) {
			[tabController performSelector:@selector(removeTabDocument:) withObject:document];
			[weakSelf performSelector:@selector(lineUpNextSelection)];
		} else {
			[weakSelf performSelector:@selector(setUpRoots)];
		}
	};
	
	// Check if document can close
	NSMethodSignature *sig = [document methodSignatureForSelector:@selector(canCloseDocumentWithDelegate:shouldCloseSelector:contextInfo:completionBlock:)];
	NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
	[inv setTarget:document];
	[inv setSelector:@selector(canCloseDocumentWithDelegate:shouldCloseSelector:contextInfo:completionBlock:)];
	id delegate = self;
	[inv setArgument:&delegate atIndex:2];
	SEL callback = @selector(documentItemCloseButton:shouldClose:contextInfo:);
	[inv setArgument:&callback atIndex:3];
	id nil_context = nil;
	[inv setArgument:&nil_context atIndex:4];
	void (^blockCopy)(BOOL) = [completionBlock copy];
	[inv setArgument:&blockCopy atIndex:5];
	[inv invoke];
}

@end

@implementation NSObject (ChocolatModifier_CloseFix)
+ (void)load {
	ZKSwizzle(ChocolatModifier_CHSplendidBarController_CloseFix, CHSplendidBarController);
}
@end
/*
 * 
 * Tell OS X that we support autosaving when it's enabled in Chocolat's preferences ("save on window defocus").
 * This enables OS X's revision history.
 * 
 */

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "ZKSwizzle/ZKSwizzle.h"
#define EMPTY_SWIZZLE_INTERFACE(CLASS_NAME, SUPERCLASS) @interface CLASS_NAME : SUPERCLASS @end

EMPTY_SWIZZLE_INTERFACE(ChocolatModifier_CHSingleFileDocument, NSDocument);
@implementation ChocolatModifier_CHSingleFileDocument

+ (BOOL)autosavesInPlace {
    // Check if we're being called from within a close operation
    // by examining the call stack for CHClosingContext
    NSArray *callStack = [NSThread callStackSymbols];
    for (NSString *symbol in callStack) {
        if ([symbol rangeOfString:@"CHClosingContext"].location != NSNotFound) {
            // If we're in a closing context, return NO to avoid the freeze
            return NO;
        }
    }
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"CHSaveOnDefocus"];
}

+ (BOOL)autosavesDrafts {
    return NO;
}

- (void)presentedItemDidChange {
	//Chocolat handles this natively.
	return;
}

// Hook the autosave completion to clear the dirty state
- (void)autosaveWithImplicitCancellability:(BOOL)autosaveElsewhere completionHandler:(void (^)(NSError *))completionHandler {
	// Check if we have the CHSaveOnDefocus preference enabled
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CHSaveOnDefocus"]) {
		// Don't autosave if the document hasn't been saved yet
		if (![self fileURL]) {
			if (completionHandler) {
				completionHandler(nil);
			}
			return;
		}
		
		// Create our own completion handler that clears the dirty state
		void (^wrappedCompletionHandler)(NSError *) = ^(NSError *error) {
			if (!error) {
				// Clear the document's edited state on successful autosave
				dispatch_async(dispatch_get_main_queue(), ^{
					[self updateChangeCount:NSChangeCleared];
				});
			}

			if (completionHandler) {
				completionHandler(error);
			}
		};
		ZKOrig(void, autosaveElsewhere, wrappedCompletionHandler);
	} else {
		ZKOrig(void, autosaveElsewhere, completionHandler);
	}
}

// Override validateMenuItem to disable duplicate for unsaved documents
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if ([menuItem action] == @selector(duplicateDocument:)) {
		// Only enable duplicate for saved documents
		return [self fileURL] != nil;
	}
	return ZKOrig(BOOL, menuItem);
}

// Hook saveDocument to clear dirty state after saving
- (void)saveDocument:(id)sender {
	ZKOrig(void, sender);
	
	// Clear the dirty indicator after a successful save
	dispatch_async(dispatch_get_main_queue(), ^{
		if ([self fileURL]) {
			[self updateChangeCount:NSChangeCleared];
		}
	});
}

// Override duplicateDocument to provide a proper implementation
- (void)duplicateDocument:(id)sender {
	// Get the current document's file URL
	NSURL *fileURL = [self fileURL];
	
	
	// Generate a new filename for the duplicate
	NSString *filename = [[fileURL lastPathComponent] stringByDeletingPathExtension];
	NSString *extension = [fileURL pathExtension];
	NSString *directory = [[fileURL path] stringByDeletingLastPathComponent];
	
	// Find a unique name by appending " copy" or " copy 2", etc.
	NSString *newFilename = [filename stringByAppendingString:@" copy"];
	NSString *newPath = [[directory stringByAppendingPathComponent:newFilename] stringByAppendingPathExtension:extension];
	int copyNumber = 2;
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	while ([fileManager fileExistsAtPath:newPath]) {
		newFilename = [NSString stringWithFormat:@"%@ copy %d", filename, copyNumber];
		newPath = [[directory stringByAppendingPathComponent:newFilename] stringByAppendingPathExtension:extension];
		copyNumber++;
	}
	
	// Copy the file
	[fileManager copyItemAtPath:[fileURL path] toPath:newPath error:nil];
	
	// Open the duplicated document
	NSDocumentController *documentController = [NSDocumentController sharedDocumentController];
	NSURL *newURL = [NSURL fileURLWithPath:newPath];
	
	// Open the new document
	[documentController openDocumentWithContentsOfURL:newURL display:YES completionHandler:nil];
}

@end

EMPTY_SWIZZLE_INTERFACE(ChocolatModifier_CHDocument, NSDocument);
@implementation ChocolatModifier_CHDocument

// Override validateMenuItem to disable duplicate for unsaved documents
- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	if ([menuItem action] == @selector(duplicateDocument:)) {
		// Only enable duplicate for saved documents
		return [self fileURL] != nil;
	}
	return ZKOrig(BOOL, menuItem);
}

// Override duplicateDocument for CHDocument as well
- (void)duplicateDocument:(id)sender {
	// Get the current document's file URL
	NSURL *fileURL = [self fileURL];
	
	
	// Generate a new filename for the duplicate
	NSString *filename = [[fileURL lastPathComponent] stringByDeletingPathExtension];
	NSString *extension = [fileURL pathExtension];
	NSString *directory = [[fileURL path] stringByDeletingLastPathComponent];
	
	// Find a unique name by appending " copy" or " copy 2", etc.
	NSString *newFilename = [filename stringByAppendingString:@" copy"];
	NSString *newPath = [[directory stringByAppendingPathComponent:newFilename] stringByAppendingPathExtension:extension];
	int copyNumber = 2;
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	while ([fileManager fileExistsAtPath:newPath]) {
		newFilename = [NSString stringWithFormat:@"%@ copy %d", filename, copyNumber];
		newPath = [[directory stringByAppendingPathComponent:newFilename] stringByAppendingPathExtension:extension];
		copyNumber++;
	}
	
	// Copy the file
	[fileManager copyItemAtPath:[fileURL path] toPath:newPath error:nil];
	
	// Open the duplicated document
	NSDocumentController *documentController = [NSDocumentController sharedDocumentController];
	NSURL *newURL = [NSURL fileURLWithPath:newPath];
	
	// Open the new document
	[documentController openDocumentWithContentsOfURL:newURL display:YES completionHandler:nil];
}

@end

@implementation NSObject (ChocolatModifier_Autosave)
+ (void)load {
	// Set default preference for CHSaveOnDefocus to true if not already set
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	if ([defaults objectForKey:@"CHSaveOnDefocus"] == nil) {
		[defaults setBool:YES forKey:@"CHSaveOnDefocus"];
	}
	
	ZKSwizzle(ChocolatModifier_CHSingleFileDocument, CHSingleFileDocument);
	ZKSwizzle(ChocolatModifier_CHDocument, CHDocument);
}
@end
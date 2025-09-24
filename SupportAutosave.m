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
#import <sys/stat.h>
#import "ZKSwizzle/ZKSwizzle.h"
#define EMPTY_SWIZZLE_INTERFACE(CLASS_NAME, SUPERCLASS) @interface CLASS_NAME : SUPERCLASS @end

EMPTY_SWIZZLE_INTERFACE(ChocolatModifier_CHSingleFileDocument, NSDocument);
@implementation ChocolatModifier_CHSingleFileDocument

+ (BOOL)autosavesInPlace {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"CHSaveOnDefocus"];
}

- (BOOL)hasUnautosavedChanges {
	return NO;
}

- (void)presentedItemDidChange {
	//Chocolat handles this natively.
	return;
}

- (void)relinquishPresentedItemToWriter:(void (^)(void (^reacquirer)(void)))writer {
	// Prevent deadlock by executing the writer block immediately without coordination
	// This is safe because Chocolat handles file change detection natively
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CHSaveOnDefocus"]) {
		writer(^{
			// Reacquirer - no-op since we handle changes ourselves
		});
	} else {
		ZKOrig(void, writer);
	}
}

- (NSFileCoordinator *)_fileCoordinator:(NSFileCoordinator *)fc coordinateReadingContentsAndWritingItemAtURL:(NSURL *)url byAccessor:(void (^)(NSURL *))accessor {
	// Skip file coordination for autosave to prevent deadlock
	// This allows document versioning to work while avoiding the coordination deadlock
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"CHSaveOnDefocus"]) {
		// Call the accessor directly without coordination
		accessor(url);
		return fc;
	}
	return ZKOrig(NSFileCoordinator *, fc, url, accessor);
}

- (BOOL)revertToContentsOfURL:(NSURL *)url ofType:(NSString *)typeName error:(NSError **)outError {
	// Call original implementation
	BOOL result = ZKOrig(BOOL, url, typeName, outError);

	// If revert succeeded and autosave is enabled, update file modification date
	// This prevents "modified by another application" errors after external changes
	if (result && [[NSUserDefaults standardUserDefaults] boolForKey:@"CHSaveOnDefocus"]) {
		// Get the actual file modification date from disk
		NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[url path] error:nil];
		NSDate *modDate = [fileAttributes fileModificationDate];
		if (modDate) {
			[self setFileModificationDate:modDate];
		}
	}

	return result;
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
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
	// Check if we can write to the directory
	BOOL canWriteToDirectory = [fileManager isWritableFileAtPath:directory];
	
	if (canWriteToDirectory) {
		// Directory is writable, save the duplicate there
		// Find a unique name by appending " copy" or " copy 2", etc.
		NSString *newFilename = [filename stringByAppendingString:@" copy"];
		NSString *newPath = [[directory stringByAppendingPathComponent:newFilename] stringByAppendingPathExtension:extension];
		int copyNumber = 2;
		
		while ([fileManager fileExistsAtPath:newPath]) {
			newFilename = [NSString stringWithFormat:@"%@ copy %d", filename, copyNumber];
			newPath = [[directory stringByAppendingPathComponent:newFilename] stringByAppendingPathExtension:extension];
			copyNumber++;
		}
		
		// Copy the file
		NSError *copyError = nil;
		BOOL success = [fileManager copyItemAtPath:[fileURL path] toPath:newPath error:&copyError];
		
		if (!success) {
			return;
		}
		
		// Open the duplicated document
		NSDocumentController *documentController = [NSDocumentController sharedDocumentController];
		NSURL *newURL = [NSURL fileURLWithPath:newPath];
		[documentController openDocumentWithContentsOfURL:newURL display:YES completionHandler:nil];
		
	} else {
		// Directory is not writable, create an unsaved duplicate using temp file
		NSString *newDisplayName = [[filename stringByAppendingString:@" copy"] stringByAppendingPathExtension:extension];
		
		// Create a unique temp directory
		NSString *tempDir = NSTemporaryDirectory();
		NSString *uniqueDir = [NSString stringWithFormat:@"ChocolatDuplicate_%d_%d", (int)[[NSDate date] timeIntervalSince1970], arc4random()];
		NSString *tempSubDir = [tempDir stringByAppendingPathComponent:uniqueDir];
		[fileManager createDirectoryAtPath:tempSubDir withIntermediateDirectories:YES attributes:nil error:nil];
		
		// Create temp file in the unique directory
		NSString *tempFilename = [newDisplayName length] > 0 ? newDisplayName : @"Untitled";
		NSString *tempPath = [tempSubDir stringByAppendingPathComponent:tempFilename];
		NSURL *tempURL = [NSURL fileURLWithPath:tempPath];
		
		// Copy the file to temp location
		NSError *copyError = nil;
		BOOL success = [fileManager copyItemAtURL:fileURL toURL:tempURL error:&copyError];
		
		if (!success) {
			// Clean up and return silently
			[fileManager removeItemAtPath:tempSubDir error:nil];
			return;
		}
		
		// Open the temp file as a new document
		NSDocumentController *documentController = [NSDocumentController sharedDocumentController];
		[documentController openDocumentWithContentsOfURL:tempURL display:YES completionHandler:^(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *error) {
			// Clean up temp files immediately
			[fileManager removeItemAtURL:tempURL error:nil];
			[fileManager removeItemAtPath:tempSubDir error:nil];
			
			if (!document || error) {
				return;
			}
			
			// Make document untitled
			[document setFileURL:nil];
			[document setFileType:[self fileType]];
			[document setDisplayName:newDisplayName];
			[document updateChangeCount:NSChangeDone];
		}];
	}
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
	
	NSFileManager *fileManager = [NSFileManager defaultManager];
	
	// Check if we can write to the directory
	BOOL canWriteToDirectory = [fileManager isWritableFileAtPath:directory];
	
	if (canWriteToDirectory) {
		// Directory is writable, save the duplicate there
		// Find a unique name by appending " copy" or " copy 2", etc.
		NSString *newFilename = [filename stringByAppendingString:@" copy"];
		NSString *newPath = [[directory stringByAppendingPathComponent:newFilename] stringByAppendingPathExtension:extension];
		int copyNumber = 2;
		
		while ([fileManager fileExistsAtPath:newPath]) {
			newFilename = [NSString stringWithFormat:@"%@ copy %d", filename, copyNumber];
			newPath = [[directory stringByAppendingPathComponent:newFilename] stringByAppendingPathExtension:extension];
			copyNumber++;
		}
		
		// Copy the file
		NSError *copyError = nil;
		BOOL success = [fileManager copyItemAtPath:[fileURL path] toPath:newPath error:&copyError];
		
		if (!success) {
			return;
		}
		
		// Open the duplicated document
		NSDocumentController *documentController = [NSDocumentController sharedDocumentController];
		NSURL *newURL = [NSURL fileURLWithPath:newPath];
		[documentController openDocumentWithContentsOfURL:newURL display:YES completionHandler:nil];
		
	} else {
		// Directory is not writable, create an unsaved duplicate using temp file
		NSString *newDisplayName = [[filename stringByAppendingString:@" copy"] stringByAppendingPathExtension:extension];
		
		// Create a unique temp directory
		NSString *tempDir = NSTemporaryDirectory();
		NSString *uniqueDir = [NSString stringWithFormat:@"ChocolatDuplicate_%d_%d", (int)[[NSDate date] timeIntervalSince1970], arc4random()];
		NSString *tempSubDir = [tempDir stringByAppendingPathComponent:uniqueDir];
		[fileManager createDirectoryAtPath:tempSubDir withIntermediateDirectories:YES attributes:nil error:nil];
		
		// Create temp file in the unique directory
		NSString *tempFilename = [newDisplayName length] > 0 ? newDisplayName : @"Untitled";
		NSString *tempPath = [tempSubDir stringByAppendingPathComponent:tempFilename];
		NSURL *tempURL = [NSURL fileURLWithPath:tempPath];
		
		// Copy the file to temp location
		NSError *copyError = nil;
		BOOL success = [fileManager copyItemAtURL:fileURL toURL:tempURL error:&copyError];
		
		if (!success) {
			// Clean up and return silently
			[fileManager removeItemAtPath:tempSubDir error:nil];
			return;
		}
		
		// Open the temp file as a new document
		NSDocumentController *documentController = [NSDocumentController sharedDocumentController];
		[documentController openDocumentWithContentsOfURL:tempURL display:YES completionHandler:^(NSDocument *document, BOOL documentWasAlreadyOpen, NSError *error) {
			// Clean up temp files immediately
			[fileManager removeItemAtURL:tempURL error:nil];
			[fileManager removeItemAtPath:tempSubDir error:nil];
			
			if (!document || error) {
				return;
			}
			
			// Make document untitled
			[document setFileURL:nil];
			[document setFileType:[self fileType]];
			[document setDisplayName:newDisplayName];
			[document updateChangeCount:NSChangeDone];
		}];
	}
}

@end

EMPTY_SWIZZLE_INTERFACE(ChocolatModifier_CHWindowController_Autosave, NSWindowController);
@implementation ChocolatModifier_CHWindowController_Autosave

// Override windowTitleForDocumentDisplayName to filter out temp paths
- (NSString *)windowTitleForDocumentDisplayName:(NSString *)displayName {
	// Get the original implementation result
	NSString *title = ZKOrig(NSString *, displayName);
	
	// The original implementation formats as "displayName — projectName"
	// Check if the title contains temp directory patterns
	if ([title rangeOfString:@"ChocolatDuplicate_"].location != NSNotFound ||
	    [title rangeOfString:@"/var/folders/"].location != NSNotFound ||
	    [title rangeOfString:@"/tmp/"].location != NSNotFound ||
	    [title rangeOfString:@"TemporaryItems"].location != NSNotFound) {
		// If it contains temp paths, just return the display name without the project part
		return displayName;
	}
	
	return title;
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
	ZKSwizzle(ChocolatModifier_CHWindowController_Autosave, CHWindowController);
}
@end
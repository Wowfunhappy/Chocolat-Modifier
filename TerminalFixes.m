/*
 * 
 * Allows specifying directives at the top of a file to set Chocolat's actions (run, repl, build, debug, check).
 * These take precedence over Chocolat's default actions for a language.
 * I felt this was missing coming from CodeRunner.
 * 
 * Example program with directives for build and run:
 
// @build: clang "$CHOC_FILE" -o "$CHOC_FILENAME_NOEXT" -framework AppKit
// @run: clang "$CHOC_FILE" -o "$CHOC_FILENAME_NOEXT" -framework AppKit && "./$CHOC_FILENAME_NOEXT"

#import <AppKit/AppKit.h>

int main(int argc, const char * argv[]) {
	@autoreleasepool {
		NSLog(@"Hello, World!");
	}
	return 0;
}
 
 * In addition, a shabang line will also take precedence over Chocolat's default run action.
 * (However, a run directive within the file takes precedence over a shabang line.)
 * 
 * Also disables Action menu items when there's no script, directive, or shebang available.
 * 
 */



#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "ZKSwizzle/ZKSwizzle.h"

@interface CHSingleFileDocument : NSDocument
- (NSString *)stringValue;
- (void)setTerminalTabDescription:(NSString *)description;
- (NSString *)terminalTabDescription;
- (id)cachedLanguage;
@end

@interface CHLanguage : NSObject
@property(retain) NSMutableArray *fileExtensions;
@property(retain) NSMutableArray *detectors;
@end

@interface CHBuildController : NSObject
+ (NSString *)getFullPathForScript:(NSString *)scriptName document:(id)document;
- (id)terminalTabForDescription:(NSString *)description app:(id)terminal;
- (NSString *)descriptionForActiveTab:(id)terminal;
- (NSString *)terminalRunScript:(NSString *)scriptPath;
@end

@interface CHTemporaryFile : NSObject
- (instancetype)init;
- (void)setUnlinkOnFinalize:(BOOL)unlink;
- (NSString *)path;
@end

@interface AppleTerminalTab : NSObject
@property (assign) BOOL busy;
@property (assign) BOOL selected;
@end

@interface SBApplication : NSObject
+ (id)applicationWithBundleIdentifier:(NSString *)bundleIdentifier;
- (void)activate;
- (AppleTerminalTab *)doScript:(NSString *)script in:(AppleTerminalTab *)tab;
@end



@interface RunChanges : NSObject
@end

@interface MenuValidation_CHBuildController : NSObject
@end

static IMP originalRunScriptNamed = NULL;

// Helper function to check if a line is a comment or directive
static BOOL isCommentOrDirectiveLine(NSString *line) {
	NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	if ([trimmed length] == 0) return YES; // Empty line
	
	// Check for @directive at start of line (with no comment prefix)
	if ([trimmed hasPrefix:@"@"]) {
		return YES;
	}
	
	// Check for common comment patterns
	if (
		[trimmed hasPrefix:@"#"]		||	// Shell, Python, Ruby, etc.
		[trimmed hasPrefix:@"//"]	||	// C++, Java, JavaScript, etc.
		[trimmed hasPrefix:@"/*"]	||	// C block comment start
		[trimmed hasPrefix:@"*"]		||	// Continuation of block comment
		[trimmed hasPrefix:@"<!--"]	||	// HTML/XML comments
		[trimmed hasPrefix:@"--"]	||	// SQL, Lua, Haskell
		[trimmed hasPrefix:@";;"]	||	// Scheme, Lisp, Clojure
		[trimmed hasPrefix:@"%"]		||	// MATLAB,
		[trimmed hasPrefix:@"%"]		||	// MATLAB, LaTeX, Prolog
		[trimmed hasPrefix:@"'"]		||	// Visual Basic, VBScript
		[trimmed hasPrefix:@"!"]		||	// Fortran
		[trimmed hasPrefix:@"REM "]	||	// BASIC, batch files
		[trimmed hasPrefix:@"rem "]		// BASIC, batch files (lowercase)
	) {
		return YES;
	}
	
	return NO;
}

// Helper function to extract command from @action: directive
static NSString* extractActionCommand(NSString *content, NSString *actionName) {
	if (!content || !actionName) return nil;
	
	// Split content into lines
	NSArray *lines = [content componentsSeparatedByString:@"\n"];
	NSUInteger lineCount = [lines count];
	
	// Create case-insensitive regex pattern for @action: directive
	// Pattern: optional whitespace, optional 0-3 chars, then @action:, then optional space, then command
	// The (.+?) captures the command non-greedily to stop before --> in HTML comments
	NSString *pattern = [NSString stringWithFormat:@"^\\s*(?:.{0,3}|<!--)?@%@:\\s*(.+?)(?:-->)?\\s*$", actionName];
	NSError *error = nil;
	NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
																			options:NSRegularExpressionCaseInsensitive
																			 error:&error];
	
	
	BOOL passedShebang = NO;
	
	for (NSUInteger i = 0; i < lineCount && i < 10; i++) { // Still limit to first 10 lines as safety
		NSString *line = lines[i];
		
		// Skip shebang line
		if (i == 0 && [line hasPrefix:@"#!"]) {
			passedShebang = YES;
			continue;
		}
		
		// If we find a non-comment line after shebang/start, stop looking
		if ((i > 0 || passedShebang) && !isCommentOrDirectiveLine(line)) {
			break;
		}
		
		NSTextCheckingResult *match = [regex firstMatchInString:line options:0 range:NSMakeRange(0, [line length])];
		
		if (match && match.numberOfRanges > 1) {
			NSRange commandRange = [match rangeAtIndex:1];
			NSString *command = [[line substringWithRange:commandRange] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			return command;
		}
	}
	
	return nil;
}

// Helper function to check if an action is available (has script, directive, or shebang)
static BOOL isActionAvailable(NSString *scriptName, NSString *actionName, CHSingleFileDocument *document) {
	if (!document) return NO;
	
	// Check if there's a native script for this action
	Class buildControllerClass = NSClassFromString(@"CHBuildController");
	NSString *scriptPath = [buildControllerClass getFullPathForScript:scriptName document:document];
	
	// Check if the script actually exists
	if (scriptPath && [scriptPath length] > 0) {
		NSFileManager *fm = [NSFileManager defaultManager];
		if ([fm fileExistsAtPath:scriptPath]) {
			return YES;
		}
	}
	
	// No native script - check for directives or shebang
	NSString *content = [document stringValue];
	if (!content) return NO;
	
	// Check for directive
	if (extractActionCommand(content, actionName)) {
		return YES;
	}
	
	// Check for shebang (only for run action)
	if ([actionName isEqualToString:@"run"] && [content hasPrefix:@"#!"]) {
		return YES;
	}
	
	return NO;
}

static void swizzled_runScriptNamed(id self, SEL _cmd, NSString *scriptName) {
	// Map script names to action names
	NSString *actionName = nil;
	if ([scriptName isEqualToString:@"run.sh"]) {
		actionName = @"run";
	} else if ([scriptName isEqualToString:@"build.sh"]) {
		actionName = @"build";
	} else if ([scriptName isEqualToString:@"debug.sh"]) {
		actionName = @"debug";
	} else if ([scriptName isEqualToString:@"check.sh"]) {
		actionName = @"check";
	} else if ([scriptName isEqualToString:@"repl.sh"]) {
		actionName = @"repl";
	}
	
	NSDocumentController *docController = [NSDocumentController sharedDocumentController];
	CHSingleFileDocument *document = (CHSingleFileDocument *)[docController currentDocument];
	
	if (document && actionName) {
		NSString *content = [document stringValue];
		NSString *directiveCommand = nil;
		NSString *finalCommand = nil;
		
		// First, check for @action: directive
		if (content) {
			directiveCommand = extractActionCommand(content, actionName);
		}
		
		// If we found a directive, use it
		if (directiveCommand) {
			finalCommand = directiveCommand;
		}
		// Otherwise, for run.sh only, check for shebang
		else if ([scriptName isEqualToString:@"run.sh"] && content && [content hasPrefix:@"#!"]) {
			// Extract shebang line
			NSRange firstLineRange = [content rangeOfString:@"\n"];
			NSString *shebangLine = firstLineRange.location != NSNotFound ? 
				[content substringToIndex:firstLineRange.location] : content;
			
			NSString *shebang = [[shebangLine substringFromIndex:2] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			
			// For shebang, we'll need a file path - either real or temporary
			// This will be handled later when we create the temp file
			finalCommand = shebang;
		}
		
		// If we have a command to execute
		if (finalCommand) {
			// Save document if needed
			NSURL *fileURL = [document fileURL];
			if (fileURL && [document isDocumentEdited]) {
				[document saveDocument:nil];
			}
			
			// Create a temporary script file
			Class tempFileClass = NSClassFromString(@"CHTemporaryFile");
			CHTemporaryFile *tempFile = [[tempFileClass alloc] init];
			NSString *tempPath = [tempFile path];
			// For unsaved files, create a temporary file for the content if needed
			NSString *tempContentPath = nil;
			if (!fileURL && content) {
				// Create another temporary file for the document content
				CHTemporaryFile *tempContentFile = [[tempFileClass alloc] init];
				tempContentPath = [tempContentFile path];
				
				// Determine file extension from the language using detectors (same as Chocolat's save panel)
				NSString *fileExt = nil;
				CHLanguage *language = [document cachedLanguage];
				
				if (language) {
					// Get detectors array from language (this is how Chocolat does it)
					NSArray *detectors = nil;
					@try {
						detectors = [language detectors];
					}
					@catch (NSException *e) {
					}
					
					// Iterate through detectors looking for one with an extension
					if (detectors) {
						for (id detector in detectors) {
							@try {
								NSString *ext = [detector valueForKey:@"extension"];
								if (ext && [ext length] > 0) {
									fileExt = ext;
									break;
								}
							}
							@catch (NSException *e) {
							}
						}
					}
				}
				
				// Fallback to window title if no language extension found
				if (!fileExt || [fileExt length] == 0) {
					NSString *displayName = [document displayName];
					fileExt = [displayName pathExtension];
				}
				
				// Final fallback to txt
				if (!fileExt || [fileExt length] == 0) {
					fileExt = @"txt";
				}
				
				// Create a better temporary filename
				NSString *betterTempPath = [[tempContentPath stringByDeletingPathExtension] 
											stringByAppendingPathExtension:fileExt];
				[[NSFileManager defaultManager] moveItemAtPath:tempContentPath 
														toPath:betterTempPath 
														error:nil];
				tempContentPath = betterTempPath;
				
				// Write the document content to the temporary file
				[content writeToFile:tempContentPath 
							atomically:YES 
							encoding:NSUTF8StringEncoding 
								error:nil];
			}
			
			// Set up environment variables
			NSString *setupEnv = @"";
			NSString *filePath = fileURL ? [fileURL path] : tempContentPath;
			
			if (filePath) {
				// Set CHOC_FILE and related variables
				NSString *fileName = [filePath lastPathComponent];
				NSString *fileDir = [filePath stringByDeletingLastPathComponent];
				NSString *fileNameNoExt = [fileName stringByDeletingPathExtension];
				NSString *fileExt = [filePath pathExtension];
				
				setupEnv = [NSString stringWithFormat:
					@"# Set Chocolat variables\n"
					@"export CHOC_FILE='%@'\n"
					@"export CHOC_FILENAME='%@'\n"
					@"export CHOC_FILENAME_NOEXT='%@'\n"
					@"export CHOC_FILE_DIR='%@'\n"
					@"export CHOC_EXT='%@'\n\n",
					[filePath stringByReplacingOccurrencesOfString:@"'" withString:@"'\"'\"'"],
					[fileName stringByReplacingOccurrencesOfString:@"'" withString:@"'\"'\"'"],
					[fileNameNoExt stringByReplacingOccurrencesOfString:@"'" withString:@"'\"'\"'"],
					[fileDir stringByReplacingOccurrencesOfString:@"'" withString:@"'\"'\"'"],
					[fileExt stringByReplacingOccurrencesOfString:@"'" withString:@"'\"'\"'"]
				];
			}
			
			// Build the final script content
			NSString *actualCommand = finalCommand;
			
			// If this is a shebang command (for run.sh) and we have a file path, append it
			if ([scriptName isEqualToString:@"run.sh"] && 
				!directiveCommand &&	// Only for shebang, not directives
				content && [content hasPrefix:@"#!"] &&
				filePath) {
				actualCommand = [NSString stringWithFormat:@"%@ '%@'", 
					finalCommand,
					[filePath stringByReplacingOccurrencesOfString:@"'" withString:@"'\"'\"'"]
				];
			}
			
			// Add cd to file directory if we have a file path (like Chocolat's built-in scripts do)
			NSString *cdCommand = @"";
			if (filePath) {
				NSString *fileDir = [filePath stringByDeletingLastPathComponent];
				cdCommand = [NSString stringWithFormat:@"cd '%@'\n", 
					[fileDir stringByReplacingOccurrencesOfString:@"'" withString:@"'\"'\"'"]];
			}
			
			NSString *scriptContent = [NSString stringWithFormat:@"#!/bin/bash\n%@%@%@\n", setupEnv, cdCommand, actualCommand];
			NSError *writeError = nil;
			[scriptContent writeToFile:tempPath atomically:YES encoding:NSUTF8StringEncoding error:&writeError];
			
			// Make the script executable
			[[NSFileManager defaultManager] setAttributes:@{NSFilePosixPermissions: @(0755)} 
												ofItemAtPath:tempPath 
													 error:nil];
			
			SEL terminalRunScriptSelector = @selector(terminalRunScript:);
			NSString *originalCommand = ((NSString* (*)(id, SEL, NSString*))objc_msgSend)(self, terminalRunScriptSelector, tempPath);
			
			// Replace the problematic clear command with a proper one
			// The original uses "clear; " which causes newline issues
			// Replace with "clear && printf '\e[3J'; " which properly clears including scrollback
			NSString *terminalCommand = [originalCommand stringByReplacingOccurrencesOfString:@"clear; " 
																					withString:@"clear && printf '\\e[3J'; "];
			
			// Also remove the bell-style setting if present
			terminalCommand = [terminalCommand stringByReplacingOccurrencesOfString:@"set bell-style none; " 
																		   withString:@""];
			
			// Run in Terminal
			SBApplication *terminal = [SBApplication applicationWithBundleIdentifier:@"com.apple.Terminal"];
			[terminal activate];
			
			AppleTerminalTab *tab = nil;
			NSString *tabDescription = [document terminalTabDescription];
			if (tabDescription) {
				SEL selector = @selector(terminalTabForDescription:app:);
				tab = ((id (*)(id, SEL, id, id))objc_msgSend)(self, selector, tabDescription, terminal);
				if ([tab busy]) tab = nil;
			}
			
			// Unlike the original app, always specify a tab.
			// Ensures that if the user creates a tab, the command won't run again.
			AppleTerminalTab *newTab = nil;
			if (!tab) {
				// Create an empty tab first to prevent command from becoming a default
				tab = [terminal doScript:@"" in:nil];
				// Small delay to let the tab initialize
				[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
				
				// Add cd to project directory if available, otherwise file directory
				NSString *projectDir = nil;
				SEL rootDirSelector = @selector(rootDirectory);
				if ([document respondsToSelector:rootDirSelector]) {
					projectDir = ((NSString* (*)(id, SEL))objc_msgSend)(document, rootDirSelector);
				}
				if (projectDir) {
					NSString *cdCommand = [NSString stringWithFormat:@"cd '%@'; history -d $(history 1 | awk '{print $1}')", 
						[projectDir stringByReplacingOccurrencesOfString:@"'" withString:@"'\"'\"'"]];
					[terminal doScript:cdCommand in:tab];
				} else if (filePath) {
					NSString *fileDir = [filePath stringByDeletingLastPathComponent];
					NSString *cdCommand = [NSString stringWithFormat:@"cd '%@'; history -d $(history 1 | awk '{print $1}')", 
						[fileDir stringByReplacingOccurrencesOfString:@"'" withString:@"'\"'\"'"]];
					[terminal doScript:cdCommand in:tab];
				}
				
			}
			// Now run the actual command in the specific tab
			// Delete the last history entry after running the command
			NSString *historyFreeCommand = [NSString stringWithFormat:
				@"%@ history -d $(history 1 | awk '{print $1}')", 
				terminalCommand];
			newTab = [terminal doScript:historyFreeCommand in:tab];
			[newTab setSelected:YES];
			
			SEL descSelector = @selector(descriptionForActiveTab:);
			NSString *newTabDescription = ((id (*)(id, SEL, id))objc_msgSend)(self, descSelector, terminal);
			[document setTerminalTabDescription:newTabDescription];
			
			return;
		}
	}
	
	if (originalRunScriptNamed) {
		// Unchanged from the original app except we want to always specify a tab.
		
		NSDocumentController *docController2 = [NSDocumentController sharedDocumentController];
		CHSingleFileDocument *document2 = (CHSingleFileDocument *)[docController2 currentDocument];
		
		Class buildControllerClass = [self class];
		NSString *scriptPath = [buildControllerClass getFullPathForScript:scriptName document:document2];
		
		if (!scriptPath || [scriptPath length] == 0) {
			// Fall back if we can't get the script path
			((void (*)(id, SEL, NSString *))originalRunScriptNamed)(self, _cmd, scriptName);
			return;
		}
		
		// Get the terminal command
		SEL terminalRunScriptSelector = @selector(terminalRunScript:);
		NSString *terminalCommand = ((NSString* (*)(id, SEL, NSString*))objc_msgSend)(self, terminalRunScriptSelector, scriptPath);
		
		if (!terminalCommand || [terminalCommand length] == 0) {
			((void (*)(id, SEL, NSString *))originalRunScriptNamed)(self, _cmd, scriptName);
			return;
		}
		
		// Run in Terminal with our fix
		SBApplication *terminal = [SBApplication applicationWithBundleIdentifier:@"com.apple.Terminal"];
		[terminal activate];
		
		AppleTerminalTab *tab = nil;
		NSString *tabDescription = [document2 terminalTabDescription];
		if (tabDescription) {
			SEL selector = @selector(terminalTabForDescription:app:);
			tab = ((id (*)(id, SEL, id, id))objc_msgSend)(self, selector, tabDescription, terminal);
			if ([tab busy]) tab = nil;
		}
		
		// FIX: Always specify a tab
		AppleTerminalTab *newTab = nil;
		if (!tab) {
			tab = [terminal doScript:@"" in:nil];
			[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
		}
		// Run command and delete from history
		NSString *historyFreeCommand = [NSString stringWithFormat:
			@"%@ history -d $(history 1 | awk '{print $1}')", 
			terminalCommand];
		newTab = [terminal doScript:historyFreeCommand in:tab];
		[newTab setSelected:YES];
		
		SEL descSelector = @selector(descriptionForActiveTab:);
		NSString *newTabDescription = ((id (*)(id, SEL, id))objc_msgSend)(self, descSelector, terminal);
		[document2 setTerminalTabDescription:newTabDescription];
	}
}


@implementation RunChanges

+ (void)load {
	// Hook the runScriptNamed method after a delay (needs the class to be loaded)
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0), dispatch_get_main_queue(), ^{
		Class buildController = NSClassFromString(@"CHBuildController");
		Method method = class_getInstanceMethod(buildController, @selector(runScriptNamed:));
		originalRunScriptNamed = method_getImplementation(method);
		method_setImplementation(method, (IMP)swizzled_runScriptNamed);
	});
}

@end

@implementation MenuValidation_CHBuildController

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	SEL action = [menuItem action];
	NSString *scriptName = nil;
	NSString *actionName = nil;
	
	if (action == @selector(run:)) {
		scriptName = @"run.sh";
		actionName = @"run";
	} else if (action == @selector(build:)) {
		scriptName = @"build.sh";
		actionName = @"build";
	} else if (action == @selector(debug:)) {
		scriptName = @"debug.sh";
		actionName = @"debug";
	} else if (action == @selector(check:)) {
		scriptName = @"check.sh";
		actionName = @"check";
	} else if (action == @selector(repl:)) {
		scriptName = @"repl.sh";
		actionName = @"repl";
	}
	
	// If it's not an action we care about, return YES
	if (!scriptName) {
		return YES;
	}
	
	// Get the current document
	NSDocumentController *docController = [NSDocumentController sharedDocumentController];
	CHSingleFileDocument *document = (CHSingleFileDocument *)[docController currentDocument];
	
	// Check if action is available
	BOOL shouldEnable = isActionAvailable(scriptName, actionName, document);
	return shouldEnable;
}

@end

__attribute__((constructor))
static void initialize_menu_validation() {
	// Hook CHBuildController to implement validateMenuItem for Actions menu items
	ZKSwizzle(MenuValidation_CHBuildController, CHBuildController);
}
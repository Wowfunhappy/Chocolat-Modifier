#import <Cocoa/Cocoa.h>
#import <objc/runtime.h>
#import "ZKSwizzle/ZKSwizzle.h"

@interface CHShellScriptEvaluator : NSObject
+ (id)evaluateShellScriptRevised:(id)arg1 language:(id)arg2 environment:(id)arg3 stdinString:(id)arg4 prependBashInit:(BOOL)arg5 exitStatusOut:(int *)arg6;
@end

@interface FixActions_CHShellScriptEvaluator : NSObject
@end

@implementation FixActions_CHShellScriptEvaluator

+ (id)evaluateShellScriptRevised:(id)script language:(id)language environment:(id)environment stdinString:(id)stdinString prependBashInit:(BOOL)prependBashInit exitStatusOut:(int *)exitStatusOut {
    NSMutableDictionary *newEnvironment = [environment mutableCopy] ?: [NSMutableDictionary dictionary];
    
    // Fix Chocolat bug: If TM_BUNDLE_SUPPORT is set, add its bin directory to PATH for TextMate compatibility
    NSString *bundleSupport = [newEnvironment objectForKey:@"TM_BUNDLE_SUPPORT"];
    if (bundleSupport) {
        NSString *binPath = [bundleSupport stringByAppendingPathComponent:@"bin"];
        NSFileManager *fm = [NSFileManager defaultManager];
        BOOL isDirectory = NO;
        
        if ([fm fileExistsAtPath:binPath isDirectory:&isDirectory] && isDirectory) {
            NSString *currentPath = [newEnvironment objectForKey:@"PATH"] ?: @"/usr/bin:/bin:/usr/local/bin";
            NSString *newPath = [NSString stringWithFormat:@"%@:%@", binPath, currentPath];
            [newEnvironment setObject:newPath forKey:@"PATH"];
        }
    }
    
    return ZKOrig(id, script, language, newEnvironment, stdinString, prependBashInit, exitStatusOut);
}

@end

__attribute__((constructor))
static void initialize() {
    ZKSwizzle(FixActions_CHShellScriptEvaluator, CHShellScriptEvaluator);
}
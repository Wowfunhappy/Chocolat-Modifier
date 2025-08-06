/*
 * I would never ever do this if Chocolat was still available for purchase or under active development!!!
 * 
 * Most of Chocolat's official website is down. The pages that do exist have an expired SSL certificate.
 * The Stripe purchase form errors: "This integration surface is unsupported for purchasable key tokenization."
 * On Chocolat's issue tracker, multiple users requested an update years ago, to no reply.
 * 
 * Clearly, this app has been abandoned.....
 * 
 */

#import <objc/runtime.h>
#import <objc/message.h>
#import <Cocoa/Cocoa.h>
#import "ZKSwizzle/ZKSwizzle.h"
#define EMPTY_SWIZZLE_INTERFACE(CLASS_NAME, SUPERCLASS) @interface CLASS_NAME : SUPERCLASS @end


EMPTY_SWIZZLE_INTERFACE(ChocolatModifier_IV2Controller, NSObject);
@implementation ChocolatModifier_IV2Controller

- (id)nagString {
    return nil;
}

@end


@implementation NSObject (ChocolatModifier_Misc)
+ (void)load {	
	ZKSwizzle(ChocolatModifier_IV2Controller, IV2Controller);
	
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"cxsd"];
	[[NSUserDefaults standardUserDefaults] synchronize];
}
@end
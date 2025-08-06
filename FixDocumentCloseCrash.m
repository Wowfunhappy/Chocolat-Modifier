/* Original crash looked like this:


Application Specific Information:
objc_msgSend() selector name: undoManager


Thread 0 Crashed:: Dispatch queue: com.apple.main-thread
0   libobjc.A.dylib               	0x00007fff93177097 objc_msgSend + 23
1   com.apple.AppKit              	0x00007fff96480e5b -[NSWindow _getUndoManager:] + 345
2   com.apple.AppKit              	0x00007fff9653efcf -[NSTextView(NSPrivate) _setFieldEditorUndoManager:] + 396
3   com.apple.AppKit              	0x00007fff9653b6ef _NSEditTextCellWithOptions + 2130
4   com.apple.AppKit              	0x00007fff9653a953 -[NSTextFieldCell _selectOrEdit:inView:target:editor:event:start:end:] + 506
5   com.apple.AppKit              	0x00007fff9657117c -[NSSearchFieldCell _selectOrEdit:inView:target:editor:event:start:end:] + 163
6   com.apple.AppKit              	0x00007fff9653a4e3 -[NSCell selectWithFrame:inView:editor:delegate:start:length:] + 59
7   com.apple.AppKit              	0x00007fff96539fab -[NSTextField selectText:] + 230
8   com.apple.AppKit              	0x00007fff96539d92 -[NSTextField becomeFirstResponder] + 158
9   com.apple.AppKit              	0x00007fff96430287 -[NSWindow makeFirstResponder:] + 734
10  com.chocolatapp.Chocolat      	0x0000000106138409 -[CHDocumentWindow makeFirstResponder:] + 94
11  com.chocolatapp.Chocolat      	0x0000000106369efc -[CHTartanView tartanMakeFirstResponderIfNeeded] + 175
12  com.apple.Foundation          	0x00007fff8e4522d7 __NSFireDelayedPerform + 333
13  com.apple.CoreFoundation      	0x00007fff9452e3e4 __CFRUNLOOP_IS_CALLING_OUT_TO_A_TIMER_CALLBACK_FUNCTION__ + 20
14  com.apple.CoreFoundation      	0x00007fff9452df1f __CFRunLoopDoTimer + 1151
15  com.apple.CoreFoundation      	0x00007fff9459f5aa __CFRunLoopDoTimers + 298
16  com.apple.CoreFoundation      	0x00007fff944e96a5 __CFRunLoopRun + 1525
17  com.apple.CoreFoundation      	0x00007fff944e8e75 CFRunLoopRunSpecific + 309
18  com.apple.HIToolbox           	0x00007fff95537a0d RunCurrentEventLoopInMode + 226
19  com.apple.HIToolbox           	0x00007fff955377b7 ReceiveNextEventCommon + 479
20  com.apple.HIToolbox           	0x00007fff955375bc _BlockUntilNextEventMatchingListInModeWithFilter + 65
21  com.apple.AppKit              	0x00007fff962f024e _DPSNextEvent + 1434
22  com.apple.AppKit              	0x00007fff962ef89b -[NSApplication nextEventMatchingMask:untilDate:inMode:dequeue:] + 122
23  com.apple.AppKit              	0x00007fff962e399c -[NSApplication run] + 553
24  com.apple.AppKit              	0x00007fff962ce783 NSApplicationMain + 940
25  com.chocolatapp.Chocolat      	0x00000001061ae27c main + 282
26  libdyld.dylib                 	0x00007fff896fa5fd start + 1


*/

#import <objc/runtime.h>
#import <Cocoa/Cocoa.h>

// Keep track of documents being closed to prevent use-after-free crashes
static NSMutableSet *closingDocuments = nil;

@implementation NSObject (FixDocumentCloseCrash)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        closingDocuments = [[NSMutableSet alloc] init];
        
        // Track when documents are closing
        Class documentClass = NSClassFromString(@"CHDocument");
        Method close = class_getInstanceMethod(documentClass, @selector(close));
        IMP originalClose = method_getImplementation(close);
        method_setImplementation(close, imp_implementationWithBlock(^(id self) {
            [closingDocuments addObject:self];
            ((void (*)(id, SEL))originalClose)(self, @selector(close));
        }));
        
        // Prevent CHSplitController from accessing closing documents
        Class splitControllerClass = NSClassFromString(@"CHSplitController");
        // Override document getter
        Method documentMethod = class_getInstanceMethod(splitControllerClass, @selector(document));
        IMP originalDocument = method_getImplementation(documentMethod);
        method_setImplementation(documentMethod, imp_implementationWithBlock(^id(id self) {
            id doc = ((id (*)(id, SEL))originalDocument)(self, @selector(document));
            return (doc && [closingDocuments containsObject:doc]) ? nil : doc;
        }));
        
        // Override document setter
        Method setDocument = class_getInstanceMethod(splitControllerClass, @selector(setDocument:));
        IMP originalSetDocument = method_getImplementation(setDocument);
        method_setImplementation(setDocument, imp_implementationWithBlock(^(id self, id document) {
            if (document && [closingDocuments containsObject:document]) {
                document = nil;
            }
            ((void (*)(id, SEL, id))originalSetDocument)(self, @selector(setDocument:), document);
        }));
    });
}

@end
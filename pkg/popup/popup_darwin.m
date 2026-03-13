#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

extern void goHotKeyCallback(void);

// MARK: - Global Hotkey (Cmd+Shift+V)

static OSStatus hotKeyHandler(EventHandlerCallRef nextHandler, EventRef event, void *userData) {
    goHotKeyCallback();
    return noErr;
}

void RegisterGlobalHotKey(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        EventTypeSpec eventType = {kEventClassKeyboard, kEventHotKeyPressed};
        InstallApplicationEventHandler(&hotKeyHandler, 1, &eventType, NULL, NULL);

        EventHotKeyID hotKeyID = {'gclp', 1};
        EventHotKeyRef hotKeyRef;
        // Virtual key code 9 = V, cmdKey | shiftKey = Cmd+Shift
        RegisterEventHotKey(9, cmdKey | shiftKey, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef);
    });
}

// MARK: - Simulate Paste (Cmd+V)
// Requires Accessibility permissions in System Settings > Privacy & Security.

void SimulatePaste(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(100 * NSEC_PER_MSEC)),
                   dispatch_get_main_queue(), ^{
        CGEventRef keyDown = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)9, true);
        CGEventSetFlags(keyDown, kCGEventFlagMaskCommand);
        CGEventPost(kCGHIDEventTap, keyDown);
        CFRelease(keyDown);

        CGEventRef keyUp = CGEventCreateKeyboardEvent(NULL, (CGKeyCode)9, false);
        CGEventSetFlags(keyUp, kCGEventFlagMaskCommand);
        CGEventPost(kCGHIDEventTap, keyUp);
        CFRelease(keyUp);
    });
}

// MARK: - Popup Menu

@interface PopupMenuTarget : NSObject
@property (assign) int selectedIndex;
@end

@implementation PopupMenuTarget
- (void)menuItemClicked:(NSMenuItem *)sender {
    self.selectedIndex = (int)[sender tag];
}
@end

int ShowPopupMenuAtCursor(const char **titles, int count) {
    __block int result = -1;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            NSRunningApplication *previousApp =
                [[NSWorkspace sharedWorkspace] frontmostApplication];

            [NSApp activateIgnoringOtherApps:YES];

            PopupMenuTarget *target = [[PopupMenuTarget alloc] init];
            target.selectedIndex = -1;

            NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
            [menu setAutoenablesItems:NO];

            // Header
            NSMenuItem *titleItem = [[NSMenuItem alloc] initWithTitle:@"Clipboard History"
                                                               action:NULL
                                                        keyEquivalent:@""];
            NSFont *boldFont = [NSFont boldSystemFontOfSize:13];
            NSDictionary *attrs = @{NSFontAttributeName: boldFont};
            NSAttributedString *attrTitle = [[NSAttributedString alloc]
                initWithString:@"Clipboard History" attributes:attrs];
            [titleItem setAttributedTitle:attrTitle];
            [titleItem setEnabled:NO];
            [menu addItem:titleItem];
            [menu addItem:[NSMenuItem separatorItem]];

            if (count == 0) {
                NSMenuItem *emptyItem = [[NSMenuItem alloc] initWithTitle:@"(no items)"
                                                                   action:NULL
                                                            keyEquivalent:@""];
                [emptyItem setEnabled:NO];
                [menu addItem:emptyItem];
            } else {
                for (int i = 0; i < count; i++) {
                    NSString *text = [NSString stringWithUTF8String:titles[i]];
                    NSString *title = [NSString stringWithFormat:@"%d.  %@", i + 1, text];
                    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title
                                                                 action:@selector(menuItemClicked:)
                                                          keyEquivalent:@""];
                    [item setTarget:target];
                    [item setTag:i];
                    [item setEnabled:YES];

                    if (i < 9) {
                        [item setKeyEquivalent:[NSString stringWithFormat:@"%d", i + 1]];
                        [item setKeyEquivalentModifierMask:0];
                    }

                    [menu addItem:item];
                }
            }

            NSPoint mouseLoc = [NSEvent mouseLocation];
            [menu popUpMenuPositioningItem:nil atLocation:mouseLoc inView:nil];

            result = target.selectedIndex;

            // Return focus to the previously active application
            [previousApp activateWithOptions:NSApplicationActivateIgnoringOtherApps];
        }
        dispatch_semaphore_signal(sem);
    });

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    return result;
}

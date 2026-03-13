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

// MARK: - Search field that auto-focuses when placed inside an NSMenu

@interface MenuSearchField : NSSearchField
@end

@implementation MenuSearchField
- (BOOL)acceptsFirstResponder {
    return YES;
}
- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) {
        // Schedule focus in NSEventTrackingRunLoopMode so it fires during
        // the blocking popUpMenuPositioningItem: tracking loop.
        NSArray *modes = @[NSEventTrackingRunLoopMode, NSDefaultRunLoopMode];
        [self.window performSelector:@selector(makeFirstResponder:)
                          withObject:self
                          afterDelay:0.0
                             inModes:modes];
    }
}
@end

// MARK: - Delegate that fuzzy-filters menu items as the user types

@interface PopupSearchDelegate : NSObject <NSSearchFieldDelegate>
@property (retain) NSMenu *menu;
@property (retain) NSMutableArray<NSMenuItem *> *clipItems;
@property (retain) NSArray<NSString *> *searchTexts;
@property (assign) PopupMenuTarget *target;
@property (retain) NSMenuItem *noMatchItem;
@end

@implementation PopupSearchDelegate

- (void)controlTextDidChange:(NSNotification *)notification {
    NSSearchField *field = [notification object];
    NSString *query = [field stringValue];

    int visibleCount = 0;
    for (NSUInteger i = 0; i < self.clipItems.count; i++) {
        NSMenuItem *item = self.clipItems[i];
        NSString *text = self.searchTexts[i];

        if (query.length == 0) {
            [item setHidden:NO];
            visibleCount++;
        } else {
            BOOL matches = [self fuzzyMatch:query inString:text];
            [item setHidden:!matches];
            if (matches) visibleCount++;
        }
    }

    [self.noMatchItem setHidden:(visibleCount > 0 || self.clipItems.count == 0)];
}

- (BOOL)control:(NSControl *)control
        textView:(NSTextView *)textView
doCommandBySelector:(SEL)commandSelector {
    if (commandSelector == @selector(insertNewline:)) {
        // Enter: select the first visible item
        for (NSMenuItem *item in self.clipItems) {
            if (!item.isHidden && item.isEnabled) {
                self.target.selectedIndex = (int)item.tag;
                [self.menu cancelTracking];
                return YES;
            }
        }
        return YES;
    }
    if (commandSelector == @selector(cancelOperation:)) {
        [self.menu cancelTracking];
        return YES;
    }
    return NO;
}

// Returns YES if every character in query appears (in order) in str,
// performing a case-insensitive comparison.
- (BOOL)fuzzyMatch:(NSString *)query inString:(NSString *)str {
    NSString *lq = [query lowercaseString];
    NSString *ls = [str lowercaseString];

    NSUInteger si = 0;
    for (NSUInteger qi = 0; qi < lq.length; qi++) {
        unichar c = [lq characterAtIndex:qi];
        BOOL found = NO;
        while (si < ls.length) {
            if ([ls characterAtIndex:si] == c) {
                si++;
                found = YES;
                break;
            }
            si++;
        }
        if (!found) return NO;
    }
    return YES;
}

@end

// MARK: - Show popup

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

            // Search field replaces the old "Clipboard History" header
            MenuSearchField *searchField = [[MenuSearchField alloc]
                initWithFrame:NSMakeRect(10, 4, 380, 24)];
            [searchField setPlaceholderString:@"Search clipboard history\u2026"];
            [searchField setBezelStyle:NSTextFieldRoundedBezel];
            [searchField setFont:[NSFont systemFontOfSize:13]];
            [searchField setFocusRingType:NSFocusRingTypeNone];

            NSView *searchContainer = [[NSView alloc]
                initWithFrame:NSMakeRect(0, 0, 400, 32)];
            [searchContainer addSubview:searchField];

            NSMenuItem *searchMenuItem = [[NSMenuItem alloc]
                initWithTitle:@"" action:NULL keyEquivalent:@""];
            [searchMenuItem setView:searchContainer];
            [searchMenuItem setEnabled:YES];
            [menu addItem:searchMenuItem];
            [menu addItem:[NSMenuItem separatorItem]];

            // Search delegate
            PopupSearchDelegate *searchDelegate = [[PopupSearchDelegate alloc] init];
            searchDelegate.menu = menu;
            searchDelegate.target = target;
            searchDelegate.clipItems = [NSMutableArray array];
            NSMutableArray *texts = [NSMutableArray array];

            // "No matches" placeholder (hidden until a search yields zero results)
            NSMenuItem *noMatchItem = [[NSMenuItem alloc]
                initWithTitle:@"No matches" action:NULL keyEquivalent:@""];
            [noMatchItem setEnabled:NO];
            [noMatchItem setHidden:YES];
            [menu addItem:noMatchItem];
            searchDelegate.noMatchItem = noMatchItem;

            if (count == 0) {
                NSMenuItem *emptyItem = [[NSMenuItem alloc]
                    initWithTitle:@"(no items)" action:NULL keyEquivalent:@""];
                [emptyItem setEnabled:NO];
                [menu addItem:emptyItem];
            } else {
                for (int i = 0; i < count; i++) {
                    NSString *text = [NSString stringWithUTF8String:titles[i]];
                    NSMenuItem *item = [[NSMenuItem alloc]
                        initWithTitle:text
                               action:@selector(menuItemClicked:)
                        keyEquivalent:@""];
                    [item setTarget:target];
                    [item setTag:i];
                    [item setEnabled:YES];

                    // Cmd+1…9 shortcuts (Cmd modifier avoids conflict with the
                    // search field, which captures bare keystrokes).
                    if (i < 9) {
                        [item setKeyEquivalent:
                            [NSString stringWithFormat:@"%d", i + 1]];
                        [item setKeyEquivalentModifierMask:
                            NSEventModifierFlagCommand];
                    }

                    [menu addItem:item];
                    [searchDelegate.clipItems addObject:item];
                    [texts addObject:text];
                }
            }

            searchDelegate.searchTexts = texts;
            [searchField setDelegate:searchDelegate];

            // Keep the delegate alive during menu tracking (NSSearchField's
            // delegate property is weak, so store a strong ref here).
            [searchMenuItem setRepresentedObject:searchDelegate];

            NSPoint mouseLoc = [NSEvent mouseLocation];
            [menu popUpMenuPositioningItem:nil atLocation:mouseLoc inView:nil];

            result = target.selectedIndex;

            // Return focus to the previously active application
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            [previousApp activateWithOptions:NSApplicationActivateIgnoringOtherApps];
#pragma clang diagnostic pop
        }
        dispatch_semaphore_signal(sem);
    });

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    return result;
}

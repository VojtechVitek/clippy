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
        RegisterEventHotKey(9, cmdKey | shiftKey, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef);
    });
}

// MARK: - Accessibility check

void EnsureAccessibility(void) {
    NSDictionary *opts = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
    Boolean trusted = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts);
    NSLog(@"[clippy] Accessibility trusted: %s", trusted ? "YES" : "NO");
}

// MARK: - Simulate Paste (Cmd+V)

void SimulatePaste(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(200 * NSEC_PER_MSEC)),
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

// MARK: - Delegate that fuzzy-filters menu items as the user types

@interface PopupSearchDelegate : NSObject <NSSearchFieldDelegate>
@property (retain) NSMenu *menu;
@property (retain) NSMutableArray<NSMenuItem *> *clipItems;
@property (retain) NSArray<NSString *> *searchTexts;
@property (assign) PopupMenuTarget *target;
@property (retain) NSMenuItem *noMatchItem;
@end

// MARK: - Search field: auto-focuses and handles Cmd+key during menu tracking
//
// Local NSEvent monitors do NOT fire during NSMenu tracking (Apple docs).
// Instead we override performKeyEquivalent: which IS called on custom views
// inside menu items during tracking.

@interface MenuSearchField : NSSearchField
@property (assign) PopupSearchDelegate *searchDelegate;
@end

@implementation MenuSearchField

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) {
        NSArray *modes = @[NSEventTrackingRunLoopMode, NSDefaultRunLoopMode];
        [self.window performSelector:@selector(makeFirstResponder:)
                          withObject:self
                          afterDelay:0.0
                             inModes:modes];
    }
}

- (BOOL)performKeyEquivalent:(NSEvent *)event {
    if (!(event.modifierFlags & NSEventModifierFlagCommand))
        return NO;

    NSString *chars = [event charactersIgnoringModifiers];
    if (chars.length != 1) return NO;
    unichar c = [chars characterAtIndex:0];

    // Cmd+A/C/V/X → forward to the field editor for text editing
    SEL action = NULL;
    if (c == 'a')      action = @selector(selectAll:);
    else if (c == 'c') action = @selector(copy:);
    else if (c == 'v') action = @selector(paste:);
    else if (c == 'x') action = @selector(cut:);

    if (action) {
        NSText *editor = [self currentEditor];
        if (!editor && self.window) {
            NSResponder *fr = [self.window firstResponder];
            if ([fr isKindOfClass:[NSText class]])
                editor = (NSText *)fr;
        }
        if (editor) {
            [editor performSelector:action withObject:nil];
            return YES;
        }
        return NO;
    }

    // Cmd+1..9 → select the corresponding clipboard item
    if (c >= '1' && c <= '9' && self.searchDelegate) {
        int idx = c - '1';
        if (idx < (int)[self.searchDelegate.clipItems count]) {
            NSMenuItem *item = [self.searchDelegate.clipItems objectAtIndex:idx];
            if (!item.isHidden && item.isEnabled) {
                self.searchDelegate.target.selectedIndex = (int)item.tag;
                [self.searchDelegate.menu cancelTracking];
                return YES;
            }
        }
        return YES;
    }

    // Let the menu handle anything else
    return NO;
}

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

            // Search field
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

            NSMenuItem *noMatchItem = [[NSMenuItem alloc]
                initWithTitle:@"No matches" action:NULL keyEquivalent:@""];
            [noMatchItem setEnabled:NO];
            [noMatchItem setHidden:YES];
            [menu addItem:noMatchItem];
            searchDelegate.noMatchItem = noMatchItem;

            // Wire up search field ↔ delegate
            [searchField setDelegate:searchDelegate];
            [searchField setSearchDelegate:searchDelegate];
            [searchMenuItem setRepresentedObject:searchDelegate];

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

            NSPoint mouseLoc = [NSEvent mouseLocation];
            [menu popUpMenuPositioningItem:nil atLocation:mouseLoc inView:nil];

            result = target.selectedIndex;

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

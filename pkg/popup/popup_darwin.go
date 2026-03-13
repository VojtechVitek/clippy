package popup

/*
#cgo LDFLAGS: -framework Carbon -framework Cocoa

#include <stdlib.h>

extern void RegisterGlobalHotKey(void);
extern int ShowPopupMenuAtCursor(const char **titles, int count);
extern void SimulatePaste(void);
*/
import "C"

import (
	"sync/atomic"
	"unsafe"
)

var (
	hotkeyCh     = make(chan struct{}, 1)
	popupShowing atomic.Bool
)

//export goHotKeyCallback
func goHotKeyCallback() {
	select {
	case hotkeyCh <- struct{}{}:
	default:
	}
}

// RegisterHotkey registers Cmd+Shift+V as a global hotkey and returns a
// channel that receives a signal each time it is pressed. Must be called
// after the application event loop is running (e.g. from systray's onReady).
func RegisterHotkey() <-chan struct{} {
	C.RegisterGlobalHotKey()
	return hotkeyCh
}

// Item represents a clipboard entry shown in the popup menu.
type Item struct {
	Title string
	Value string
}

// ShowPopup displays a native popup menu at the current cursor position.
// Returns the index of the selected item, or -1 if dismissed without selection.
func ShowPopup(items []Item) int {
	if !popupShowing.CompareAndSwap(false, true) {
		return -1
	}
	defer popupShowing.Store(false)

	cTitles := make([]*C.char, len(items))
	for i, item := range items {
		cTitles[i] = C.CString(item.Title)
	}
	defer func() {
		for _, s := range cTitles {
			C.free(unsafe.Pointer(s))
		}
	}()

	var titlesPtr **C.char
	if len(items) > 0 {
		titlesPtr = &cTitles[0]
	}

	return int(C.ShowPopupMenuAtCursor(titlesPtr, C.int(len(items))))
}

// Paste simulates Cmd+V in the previously focused application.
// Requires Accessibility permissions (System Settings > Privacy & Security).
// If not granted, the clipboard value is still set—the user just has to
// press Cmd+V manually.
func Paste() {
	C.SimulatePaste()
}

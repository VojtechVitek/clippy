package systray

import (
	"log"
	"strings"
	"time"

	"github.com/VojtechVitek/clippy/clip"
	"github.com/VojtechVitek/clippy/icon"
	"github.com/VojtechVitek/clippy/pkg/popup"
	"github.com/getlantern/systray"
)

var clipboardInstance *clipboard

type subMenu string

const (
	obfuscateMenu subMenu = "obfuscate"
	deleteMenu    subMenu = "delete"
)

func initInstance() {
	clipboardInstance = &clipboard{
		menuItemToVal:  make(map[*systray.MenuItem]string),
		valExistsMap:   make(map[string]bool),
		obfuscatedVals: make(map[string]bool),
		truncateLength: 20,
		pwShowLength:   4,
	}
}

// Run starts the system tray app
func Run() {
	initInstance()
	systray.Run(onReady, func() {})
}

func onReady() {
	systray.SetTemplateIcon(icon.Data, icon.Data)
	systray.SetTooltip("Clipboard")
	mQuit := systray.AddMenuItem("Quit", "Quit the app")
	mClear := systray.AddMenuItem("Clear", "Clear all entries")
	systray.AddSeparator()

	go func() {
		<-mQuit.ClickedCh
		systray.Quit()
	}()
	initializeClipBoard()
	for {
		select {
		case <-mClear.ClickedCh:
			clearSlots(clipboardInstance.menuItemArray)
		}
	}
}

func initializeClipBoard() {
	addSlots(100, clipboardInstance)

	changes := make(chan string, 10)
	stopCh := make(chan struct{})
	go clip.Monitor(time.Millisecond*500, stopCh, changes)
	go monitorClipboard(clipboardInstance, stopCh, changes)

	// Cmd+Shift+V global hotkey → popup clipboard history at cursor
	hotkeyTriggered := popup.RegisterHotkey()
	go func() {
		for range hotkeyTriggered {
			items := clipboardInstance.getPopupItems()
			if selected := popup.ShowPopup(items); selected >= 0 && selected < len(items) {
				clip.WriteAll(items[selected].Value)
				popup.Paste()
			}
		}
	}()
}

func clearSlots(menuItemArray []menuItem) {
	clipboardInstance.mutex.Lock()
	defer clipboardInstance.mutex.Unlock()

	for _, menuItem := range menuItemArray {
		deleteMenuItem(clipboardInstance, menuItem)
	}
	clipboardInstance.nextMenuItemIndex = 0
}

func changeActiveSlots(changeSlotNumTo int, clipboardInstance *clipboard) {
	clipboardInstance.mutex.Lock()
	defer clipboardInstance.mutex.Unlock()

	existingSlots := clipboardInstance.activeSlots
	clipboardInstance.activeSlots = changeSlotNumTo
	if changeSlotNumTo == existingSlots {
		return
	}
	if changeSlotNumTo > existingSlots { //enable
		for i := existingSlots; i < changeSlotNumTo; i++ {
			menuItem := clipboardInstance.menuItemArray[i].instance
			menuItem.Enable()
			menuItem.Show()
		}
		for index, menuItem := range clipboardInstance.menuItemArray {
			if _, exists := clipboardInstance.menuItemToVal[menuItem.instance]; !exists && !menuItem.instance.Disabled() {
				clipboardInstance.nextMenuItemIndex = index
				break
			}
		}
	} else { //disable
		for i := changeSlotNumTo; i < existingSlots; i++ {
			menuItem := clipboardInstance.menuItemArray[i]
			menuItem.instance.Disable()
			menuItem.instance.Hide()
			deleteMenuItem(clipboardInstance, menuItem)
		}
		if clipboardInstance.nextMenuItemIndex >= changeSlotNumTo {
			clipboardInstance.nextMenuItemIndex = 0
		}
	}

}

func addSlots(numSlots int, clipboardInstance *clipboard) {
	clipboardInstance.mutex.Lock()
	defer clipboardInstance.mutex.Unlock()

	for i := 0; i < numSlots; i++ {
		menuItemInstance := systray.AddMenuItem("", "")
		menuItemInstance.Hide()
		mi := menuItem{
			instance:     menuItemInstance,
			subMenuItems: make(map[subMenu]*systray.MenuItem),
		}

		subMenuObfuscate := menuItemInstance.AddSubMenuItem("Obfuscate Password", "")
		subMenuObfuscate.Hide()
		subMenuObfuscate.Disable()
		mi.subMenuItems[obfuscateMenu] = subMenuObfuscate

		subMenuDelete := menuItemInstance.AddSubMenuItem("Delete", "")
		subMenuDelete.Hide()
		subMenuDelete.Disable()
		mi.subMenuItems[deleteMenu] = subMenuDelete

		clipboardInstance.menuItemArray = append(clipboardInstance.menuItemArray, mi)
		go func() {
			for {
				select {
				case <-menuItemInstance.ClickedCh:
					if valToWrite, exists := clipboardInstance.menuItemToVal[menuItemInstance]; exists {
						clip.WriteAll(valToWrite)
					}
				case <-subMenuObfuscate.ClickedCh:
					clipboardInstance.mutex.Lock()
					if subMenuObfuscate.Checked() {
						val := clipboardInstance.menuItemToVal[menuItemInstance]
						menuItemInstance.SetTitle(truncateVal(clipboardInstance, val))
						subMenuObfuscate.Uncheck()
						delete(clipboardInstance.obfuscatedVals, val)
					} else {
						obfuscateVal(clipboardInstance, mi)
					}
					clipboardInstance.mutex.Unlock()
				case <-subMenuDelete.ClickedCh:
					clipboardInstance.mutex.Lock()
					deleteMenuItem(clipboardInstance, mi)
					clipboardInstance.mutex.Unlock()
				}
			}
		}()
	}
	clipboardInstance.activeSlots = clipboardInstance.activeSlots + numSlots
}

func monitorClipboard(clipboardInstance *clipboard, stopCh chan struct{}, changes chan string) {
	for {
		select {
		case <-stopCh:
			return
		default:
			change, ok := <-changes
			if ok {
				clipboardInstance.mutex.Lock()
				val := strings.TrimSpace(change)
				if val != "" {
					if clipboardInstance.valExistsMap[val] {
						// Duplicate: just move to front of the recent list
						clipboardInstance.pushRecent(val)
					} else {
						// New value: allocate a systray slot and track it
					for {
						menuItem := clipboardInstance.menuItemArray[clipboardInstance.nextMenuItemIndex]
						if !menuItem.instance.Disabled() {
							deleteMenuItem(clipboardInstance, menuItem)
							acceptVal(clipboardInstance, menuItem, val)
							clipboardInstance.nextMenuItemIndex = (clipboardInstance.nextMenuItemIndex + 1) % clipboardInstance.activeSlots
							break
						} else {
							clipboardInstance.nextMenuItemIndex = (clipboardInstance.nextMenuItemIndex + 1) % clipboardInstance.activeSlots
						}
					}
						clipboardInstance.pushRecent(val)
					}
				}
				clipboardInstance.mutex.Unlock()
			} else {
				log.Printf("channel has been closed. exiting..")
			}
		}
	}
}

package systray

import (
	"strconv"
	"strings"
	"sync"

	"github.com/getlantern/systray"
	"github.com/prashantgupta24/go-clip/pkg/popup"
)

const popupTruncateLength = 60

type clipboard struct {
	menuItemArray     []menuItem
	nextMenuItemIndex int
	menuItemToVal     map[*systray.MenuItem]string
	valExistsMap      map[string]bool
	activeSlots       int
	truncateLength    int
	pwShowLength      int
	mutex             sync.RWMutex
}

type menuItem struct {
	instance     *systray.MenuItem
	subMenuItems map[subMenu]*systray.MenuItem
}

func (c *clipboard) getPopupItems() []popup.Item {
	c.mutex.RLock()
	defer c.mutex.RUnlock()

	var items []popup.Item
	for _, mi := range c.menuItemArray {
		if val, exists := c.menuItemToVal[mi.instance]; exists {
			title := strings.ReplaceAll(val, "\n", " ")
			title = strings.ReplaceAll(title, "\r", "")
			if len(title) > popupTruncateLength {
				title = title[:popupTruncateLength] + "... (" + strconv.Itoa(len(val)) + " chars)"
			}
			items = append(items, popup.Item{
				Title: title,
				Value: val,
			})
		}
	}
	return items
}

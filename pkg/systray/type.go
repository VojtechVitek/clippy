package systray

import (
	"strconv"
	"strings"
	"sync"
	"unicode/utf8"

	"github.com/VojtechVitek/clippy/pkg/popup"
	"github.com/getlantern/systray"
)

const popupTruncateLength = 60

type clipboard struct {
	menuItemArray     []menuItem
	nextMenuItemIndex int
	menuItemToVal     map[*systray.MenuItem]string
	valExistsMap      map[string]bool
	obfuscatedVals    map[string]bool
	recentValues      []string // most-recent-first ordering for the popup
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

	items := make([]popup.Item, 0, len(c.recentValues))
	for _, val := range c.recentValues {
		var title string
		if c.obfuscatedVals[val] {
			title = c.obfuscateTitle(val)
		} else {
			title = strings.ReplaceAll(val, "\n", " ")
			title = strings.ReplaceAll(title, "\r", "")
			if len(title) > popupTruncateLength {
				title = truncateUTF8BytesMax(title, popupTruncateLength) + "... (" + strconv.Itoa(len(val)) + " chars)"
			}
		}
		// NSMenuItem / NSString require valid UTF-8; byte truncation can split runes.
		title = strings.ToValidUTF8(title, "\uFFFD")
		items = append(items, popup.Item{
			Title: title,
			Value: val,
		})
	}
	return items
}

// truncateUTF8BytesMax returns s truncated to at most maxBytes bytes without
// splitting a UTF-8 codepoint.
func truncateUTF8BytesMax(s string, maxBytes int) string {
	if len(s) <= maxBytes {
		return s
	}
	s = s[:maxBytes]
	for len(s) > 0 && !utf8.ValidString(s) {
		s = s[:len(s)-1]
	}
	return s
}

func (c *clipboard) obfuscateTitle(val string) string {
	var b strings.Builder
	show := min(len(val), c.pwShowLength)
	b.WriteString(val[:show])
	for i := show; i < min(len(val), popupTruncateLength); i++ {
		b.WriteByte('*')
	}
	return b.String()
}

// pushRecent moves val to the front of recentValues, removing any existing
// occurrence first. Must be called with c.mutex held.
func (c *clipboard) pushRecent(val string) {
	for i, v := range c.recentValues {
		if v == val {
			c.recentValues = append(c.recentValues[:i], c.recentValues[i+1:]...)
			break
		}
	}
	c.recentValues = append([]string{val}, c.recentValues...)
}

// removeRecent removes val from recentValues. Must be called with c.mutex held.
func (c *clipboard) removeRecent(val string) {
	for i, v := range c.recentValues {
		if v == val {
			c.recentValues = append(c.recentValues[:i], c.recentValues[i+1:]...)
			return
		}
	}
}

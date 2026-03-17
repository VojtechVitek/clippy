package systray

import (
	"reflect"
	"strconv"
	"strings"
)

func obfuscateVal(clipboardInstance *clipboard, menuItem menuItem) {
	val := clipboardInstance.menuItemToVal[menuItem.instance]
	var newTitle strings.Builder
	newTitle.WriteString(val[:min(len(val), clipboardInstance.pwShowLength)])

	for i := clipboardInstance.pwShowLength; i < min(len(val), clipboardInstance.truncateLength); i++ {
		newTitle.WriteString("*")
	}
	menuItem.instance.SetTitle(newTitle.String())
	menuItem.instance.SetTooltip(newTitle.String())
	menuItem.subMenuItems[obfuscateMenu].Check()
	clipboardInstance.obfuscatedVals[val] = true
}

func acceptVal(clipboardInstance *clipboard, menuItem menuItem, val string) {
	valTrunc := truncateVal(clipboardInstance, val)

	menuItem.instance.SetTitle(valTrunc)
	menuItem.instance.SetTooltip(val)
	menuItem.instance.Show()

	clipboardInstance.valExistsMap[val] = true
	clipboardInstance.menuItemToVal[menuItem.instance] = val

	for _, subMenuItem := range menuItem.subMenuItems {
		subMenuItem.Show()
		subMenuItem.Enable()
	}
}

func deleteMenuItem(clipboardInstance *clipboard, menuItem menuItem) {
	menuItem.instance.SetTitle("")
	menuItem.instance.SetTooltip("")
	menuItem.instance.Hide()

	if val, exists := clipboardInstance.menuItemToVal[menuItem.instance]; exists {
		clipboardInstance.removeRecent(val)
		delete(clipboardInstance.valExistsMap, val)
		delete(clipboardInstance.obfuscatedVals, val)
	}
	delete(clipboardInstance.menuItemToVal, menuItem.instance)

	for _, subMenu := range menuItem.subMenuItems {
		subMenu.Hide()
		subMenu.Disable()
		subMenu.Uncheck()
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func truncateVal(clipboardInstance *clipboard, val string) string {
	valTrunc := val
	if len(val) > clipboardInstance.truncateLength {
		valTrunc = val[:clipboardInstance.truncateLength] + "... (" + strconv.Itoa(len(val)) + " chars)"
	}
	return valTrunc
}

func getTitle(menuItem menuItem) string {
	title := ""
	menuItemReflect := reflect.ValueOf(menuItem.instance).Elem()

	for i := 0; i < menuItemReflect.NumField(); i++ {
		fieldName := menuItemReflect.Type().Field(i).Name
		if fieldName == "title" {
			title = menuItemReflect.Field(i).String()
		}
	}
	return title
}

func getToolTip(menuItem menuItem) string {
	toolTip := ""
	menuItemReflect := reflect.ValueOf(menuItem.instance).Elem()

	for i := 0; i < menuItemReflect.NumField(); i++ {
		fieldName := menuItemReflect.Type().Field(i).Name
		if fieldName == "tooltip" {
			toolTip = menuItemReflect.Field(i).String()
		}
	}
	return toolTip
}

import QtQuick
import qs.Common
import qs.Widgets

Column {
    id: settingsRoot

    property var pluginService: null
    property string pluginId: ""

    spacing: Theme.spacingL
    width: parent?.width ?? 400

    StyledText {
        text: "Fancy Workspace Switcher"
        font.pixelSize: Theme.fontSizeXLarge
        color: Theme.surfaceText
        font.weight: Font.Bold
    }

    StyledText {
        text: "Hover over any workspace pip to see the windows open on that workspace. Click a window to switch to it."
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.surfaceTextMedium
        wrapMode: Text.WordWrap
        width: parent.width
    }

    StyledText {
        text: "This widget uses the same workspace and appearance settings as the built-in workspace switcher (Settings → DankBar → Workspace)."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceTextMedium
        wrapMode: Text.WordWrap
        width: parent.width
    }
}

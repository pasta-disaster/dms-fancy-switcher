import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "fancySwitcher"

    StyledText {
        text: "Fancy Workspace Switcher"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        text: "Enhanced workspace switcher with hover-to-preview window popups. Click a window in the popup to jump straight to it."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        width: parent.width
        wrapMode: Text.WordWrap
    }

    StyledRect {
        width: parent.width
        height: 1
        color: Theme.surfaceVariant
    }

    StyledText {
        text: "Display Options"
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.DemiBold
        color: Theme.surfaceText
    }

    ToggleSetting {
        settingKey: "showOccupiedWorkspacesOnly"
        label: "Show Occupied Workspaces Only"
        description: "Only render pips for workspaces that have active windows"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "showWorkspaceIndex"
        label: "Show Workspace Numbers"
        description: "Render workspace index numbers on the pips"
        defaultValue: false
    }

    ToggleSetting {
        settingKey: "showWorkspaceName"
        label: "Show Workspace Names"
        description: "Render workspace names on the pips"
        defaultValue: false
    }
}

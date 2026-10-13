import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.I3
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: pip

    property var workspaceData: null
    property int workspaceIndex: 0
    property bool isActive: false
    property bool isPlaceholder: false
    property bool isVerticalBar: false
    property real pipWidgetHeight: 30
    property real pipBarThickness: 48
    property var barConfig: null
    property var currentWorkspaceId: null
    property var dwlActiveTagsList: []
    property bool useExtWorkspace: false
    property var switcherRoot: null

    function opt(key) {
        if (switcherRoot && typeof switcherRoot.opt === "function")
            return switcherRoot.opt(key);
        return SettingsData.widgetOption("workspaceSwitcher", null, key);
    }

    signal pipClicked(var data)
    signal pipRightClicked()
    signal hoverEntered(var data, int idx)
    signal hoverExited()

    readonly property bool isHovered: pipMouseArea.containsMouse
    readonly property bool isUrgent: {
        if (useExtWorkspace) return workspaceData?.urgent ?? false;
        if (CompositorService.isHyprland) return workspaceData?.urgent ?? false;
        if (CompositorService.isDwl) return workspaceData?.state === 2;
        return false;
    }
    readonly property bool isOccupied: {
        if (CompositorService.isHyprland)
            return Array.from(Hyprland.toplevels?.values || []).some(tl => tl.workspace?.id === workspaceData?.id);
        if (CompositorService.isNiri)
            return NiriService.windows?.some(win => win.workspace_id === workspaceData?.id) ?? false;
        if (CompositorService.isDwl)
            return (workspaceData?.clients ?? 0) > 0;
        return false;
    }

    readonly property color unfocusedColor: {
        switch (opt("workspaceUnfocusedColorMode")) {
        case "s":   return Theme.surface;
        case "sc":  return Theme.surfaceContainer;
        case "sch": return Theme.surfaceContainerHigh;
        default:    return Theme.surfaceTextAlpha;
        }
    }
    readonly property color activeColor: {
        switch (opt("workspaceColorMode")) {
        case "s":    return Theme.surface;
        case "sc":   return Theme.surfaceContainer;
        case "sch":  return Theme.surfaceContainerHigh;
        case "none": return unfocusedColor;
        default:     return Theme.primary;
        }
    }
    readonly property color urgentColor: {
        switch (opt("workspaceUrgentColorMode")) {
        case "primary":   return Theme.primary;
        case "secondary": return Theme.secondary;
        case "s":         return Theme.surface;
        case "sc":        return Theme.surfaceContainer;
        default:          return Theme.error;
        }
    }
    readonly property color occupiedColor: {
        switch (opt("workspaceOccupiedColorMode")) {
        case "sec":  return Theme.secondary;
        case "s":    return Theme.surface;
        case "sc":   return Theme.surfaceContainer;
        case "sch":  return Theme.surfaceContainerHigh;
        case "schh": return Theme.surfaceContainerHighest;
        default:     return unfocusedColor;
        }
    }

    readonly property real baseSize: isActive
        ? Math.max(pipWidgetHeight * 1.05, pipWidgetHeight * 0.8)
        : Math.max(pipWidgetHeight * 0.7, pipWidgetHeight * 0.6)

    readonly property bool hasLabel: labelText.visible && labelText.text !== ""
    readonly property real labelPadding: Theme.spacingM
    readonly property real crossBase: hasLabel
        ? Math.max(pipWidgetHeight * 0.75, labelText.implicitHeight + Theme.spacingXS * 2)
        : (pipWidgetHeight * 0.5)

    readonly property real visualWidth: {
        if (isVerticalBar)
            return hasLabel ? Math.max(crossBase, labelText.implicitWidth + Theme.spacingXS * 2) : crossBase;
        if (hasLabel) {
            return Math.max(baseSize, labelText.implicitWidth + labelPadding * 2);
        }
        return baseSize;
    }
    readonly property real visualHeight: isVerticalBar
        ? (hasLabel ? Math.max(baseSize, labelText.implicitHeight + labelPadding * 2) : baseSize)
        : crossBase

    width:  isVerticalBar ? pipBarThickness : visualWidth
    height: isVerticalBar ? visualHeight : pipBarThickness

    Behavior on width {
        NumberAnimation { duration: Theme.mediumDuration; easing.type: Theme.emphasizedEasing }
    }
    Behavior on height {
        NumberAnimation { duration: Theme.mediumDuration; easing.type: Theme.emphasizedEasing }
    }

    Rectangle {
        id: pipRect
        width: pip.visualWidth
        height: pip.visualHeight
        x: isVerticalBar ? (pipBarThickness - width) / 2 : (parent.width - width) / 2
        y: isVerticalBar ? (parent.height - height) / 2 : (pipBarThickness - height) / 2
        radius: Theme.cornerRadius
        color: isActive ? activeColor
             : isUrgent ? urgentColor
             : isPlaceholder ? Theme.surfaceTextLight
             : isHovered ? Theme.withAlpha(unfocusedColor, 0.7)
             : isOccupied ? occupiedColor
             : unfocusedColor

        border.width: isUrgent ? 2 : 0
        border.color: isUrgent ? urgentColor : "transparent"

        Behavior on color {
            ColorAnimation { duration: Theme.mediumDuration; easing.type: Theme.emphasizedEasing }
        }
        Behavior on width {
            NumberAnimation { duration: Theme.mediumDuration; easing.type: Theme.emphasizedEasing }
        }
        Behavior on height {
            NumberAnimation { duration: Theme.mediumDuration; easing.type: Theme.emphasizedEasing }
        }

        // Workspace label
        StyledText {
            id: labelText
            anchors.centerIn: parent
            text: _getLabel()
            font.pixelSize: Theme.barTextSize(pipBarThickness, barConfig?.fontScale, barConfig?.maximizeWidgetText)
            font.weight: (isActive && !isPlaceholder) ? Font.DemiBold : Font.Normal
            color: (isActive || isUrgent)
                ? Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.95)
                : isPlaceholder ? Theme.surfaceTextAlpha
                : Theme.surfaceTextMedium
            visible: !!(opt("showWorkspaceIndex") || opt("showWorkspaceName")) && text !== ""
        }
    }

    MouseArea {
        id: pipMouseArea
        anchors.fill: parent
        hoverEnabled: !isPlaceholder
        cursorShape: isPlaceholder ? Qt.ArrowCursor : Qt.PointingHandCursor
        enabled: !isPlaceholder
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        onClicked: mouse => {
            if (mouse.button === Qt.LeftButton)
                pip.pipClicked(workspaceData);
            else if (mouse.button === Qt.RightButton)
                pip.pipRightClicked();
        }
        onContainsMouseChanged: {
            if (containsMouse && !isPlaceholder) {
                pip.hoverEntered(workspaceData, workspaceIndex);
            } else {
                pip.hoverExited();
            }
        }
    }

    function _getIndexNumber() {
        if (useExtWorkspace) return workspaceIndex + 1;
        if (CompositorService.isNiri)
            return (workspaceData?.idx !== undefined && workspaceData?.idx !== -1)
                ? workspaceData.idx : (workspaceIndex + 1);
        if (CompositorService.isHyprland)
            return (workspaceData?.id !== undefined && workspaceData?.id !== -1)
                ? workspaceData.id : (workspaceIndex + 1);
        if (CompositorService.isDwl)
            return (workspaceData?.tag !== undefined && workspaceData?.tag !== -1)
                ? (workspaceData.tag + 1) : (workspaceIndex + 1);
        if (CompositorService.isSway || CompositorService.isScroll || CompositorService.isMiracle)
            return (workspaceData?.num !== undefined && workspaceData?.num !== -1)
                ? workspaceData.num : (workspaceIndex + 1);
        return workspaceIndex + 1;
    }

    function _getWorkspaceName() {
        if (!workspaceData) return "";
        let rawName = workspaceData.name;
        if (!rawName || typeof rawName !== "string") return "";
        rawName = rawName.trim();
        return rawName;
    }

    function _getLabel() {
        if (isPlaceholder) return "";

        const showName = !!opt("showWorkspaceName");
        const showIndex = !!opt("showWorkspaceIndex");

        let wsName = showName ? _getWorkspaceName() : "";
        if (wsName && isVerticalBar) {
            wsName = wsName.charAt(0).toUpperCase();
        }

        const idxNum = _getIndexNumber();

        if (wsName && wsName !== "") {
            if (showIndex) {
                return `${idxNum}: ${wsName}`;
            }
            return wsName;
        }

        if (showIndex) {
            return String(idxNum);
        }

        if (showName) {
            return String(idxNum);
        }

        return "";
    }
}

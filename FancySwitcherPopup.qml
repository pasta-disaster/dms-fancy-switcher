import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.I3
import qs.Common
import qs.Services
import qs.Widgets

PanelWindow {
    id: popup

    WlrLayershell.namespace: "dms:fancyswitcher"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
        top: true
        left: true
    }

    color: "transparent"
    visible: false

    property var workspaceData: null
    property string screenName: ""
    property bool useExtWorkspace: false
    property bool isVerticalBar: false
    property real barThickness: 48
    property var barConfig: null
    property var parentScreen: null
    property var switcherRoot: null
    property var targetPipItem: null

    signal windowActivated(var windowId)

    // ── Popup state ────────────────────────────────────────────────────
    property var windowList: []

    // Surface position on screen (set via margins)
    property real surfaceX: 0
    property real surfaceY: 0

    screen: parentScreen

    function show() {
        hideTimer.stop();
        // Hide briefly to force Wayland surface reposition when
        // switching between pips while already visible.
        if (visible) {
            visible = false;
        }
        _refreshWindowList();
        _updateGeometry();
        visible = true;
    }

    function hide() {
        visible = false;
    }

    function scheduleHide() {
        hideTimer.restart();
    }

    Timer {
        id: hideTimer
        interval: 400
        onTriggered: {
            if (!surfaceHoverArea.containsMouse)
                popup.hide();
        }
    }

    // Pending focus — stored at popup level so it survives delegate teardown
    property var _pendingFocusWindowId: null

    Timer {
        id: focusTimer
        interval: 80
        onTriggered: {
            if (popup._pendingFocusWindowId !== null) {
                popup.windowActivated(popup._pendingFocusWindowId);
                popup._pendingFocusWindowId = null;
            }
        }
    }

    onWorkspaceDataChanged: {
        if (visible)
            _refreshWindowList();
    }

    // ── Sizing ─────────────────────────────────────────────────────────
    readonly property real popupWidth: 280
    readonly property real popupItemHeight: 36
    readonly property real popupPadding: Theme.spacingM
    readonly property real popupContentHeight: {
        if (windowList.length === 0) return emptyHeight;
        return Math.min(
            windowList.length * popupItemHeight + popupPadding * 2,
            maxPopupHeight
        );
    }
    readonly property real emptyHeight: 48
    readonly property real maxPopupHeight: 400

    implicitWidth: popupWidth
    implicitHeight: popupContentHeight

    margins {
        left: Math.round(popup.surfaceX)
        top: Math.round(popup.surfaceY)
    }

    // ── Geometry ───────────────────────────────────────────────────────
    // The surface covers ONLY the popup content area. The gap between
    // the bar pip and the popup is handled by the hide timer (400ms).
    // This avoids blocking hover events on adjacent pips.
    function _updateGeometry() {
        if (!targetPipItem || !parentScreen) return;

        const globalPos = targetPipItem.mapToGlobal(0, 0);
        const sx = parentScreen.x || 0;
        const sy = parentScreen.y || 0;
        const pipX = globalPos.x - sx;
        const pipY = globalPos.y - sy;
        const pipW = targetPipItem.width;
        const pipH = targetPipItem.height;
        const screenW = parentScreen.width;
        const screenH = parentScreen.height;
        const gap = Theme.spacingS;

        let popX, popY;

        if (isVerticalBar) {
            const barEdge = barConfig?.position ?? 2;
            if (barEdge === 3) {
                popX = pipX - popupWidth - gap;
            } else {
                popX = pipX + pipW + gap;
            }
            popY = pipY;
        } else {
            popX = pipX + (pipW / 2) - (popupWidth / 2);
            const barEdge = barConfig?.position ?? 0;
            if (barEdge === 1) {
                popY = pipY - popupContentHeight - gap;
            } else {
                popY = pipY + pipH + gap;
            }
        }

        // Clamp to screen
        popX = Math.max(gap, Math.min(screenW - popupWidth - gap, popX));
        popY = Math.max(gap, Math.min(screenH - popupContentHeight - gap, popY));

        surfaceX = popX;
        surfaceY = popY;
    }

    // ── Hover tracking ─────────────────────────────────────────────────
    // This MouseArea covers the entire surface (popup + gap + pip overlap).
    // acceptedButtons: Qt.NoButton means it tracks hover without consuming
    // clicks, so child MouseAreas still work for click + per-item hover.
    MouseArea {
        id: surfaceHoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton

        onContainsMouseChanged: {
            if (containsMouse)
                hideTimer.stop();
            else
                popup.scheduleHide();
        }

        // ── Visual popup content ───────────────────────────────────────
        Rectangle {
            id: backgroundRect
            anchors.fill: parent
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceContainerHigh,
                                   Theme.popupTransparency ?? 0.95)
            border.color: BlurService.enabled
                ? (BlurService.borderColor ?? Theme.outlineMedium)
                : Theme.outlineMedium
            border.width: BlurService.enabled
                ? (BlurService.borderWidth ?? 1)
                : 1

            Column {
                id: windowColumn
                anchors.fill: parent
                anchors.margins: popup.popupPadding
                spacing: 2
                visible: popup.windowList.length > 0

                Repeater {
                    model: ScriptModel { values: popup.windowList }

                    delegate: Rectangle {
                        id: windowItem
                        width: windowColumn.width
                        height: popup.popupItemHeight
                        radius: Theme.cornerRadius * 0.6
                        color: windowItemMouse.containsMouse
                            ? Theme.withAlpha(Theme.primary, 0.15)
                            : (modelData.isFocused
                                ? Theme.withAlpha(Theme.primary, 0.08)
                                : "transparent")

                        Behavior on color {
                            ColorAnimation { duration: 100 }
                        }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: Theme.spacingS
                            anchors.rightMargin: Theme.spacingS
                            spacing: Theme.spacingS

                            IconImage {
                                id: winIcon
                                width: 20
                                height: 20
                                source: modelData.icon || ""
                                anchors.verticalCenter: parent.verticalCenter
                                visible: status === Image.Ready
                            }

                            Rectangle {
                                width: 20
                                height: 20
                                radius: 4
                                color: Theme.surfaceContainer
                                anchors.verticalCenter: parent.verticalCenter
                                visible: !winIcon.visible

                                StyledText {
                                    anchors.centerIn: parent
                                    text: (modelData.appName || "?")
                                          .charAt(0).toUpperCase()
                                    font.pixelSize: 11
                                    color: Theme.primary
                                    font.weight: Font.Bold
                                }
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 20 - Theme.spacingS * 2
                                       - parent.anchors.leftMargin
                                       - parent.anchors.rightMargin
                                text: modelData.title || modelData.appName
                                font.pixelSize: Theme.fontSizeSmall
                                color: modelData.isFocused
                                       ? Theme.primary : Theme.surfaceText
                                font.weight: modelData.isFocused
                                             ? Font.Medium : Font.Normal
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                        }

                        MouseArea {
                            id: windowItemMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                popup._pendingFocusWindowId = modelData.windowId;
                                if (switcherRoot)
                                    switcherRoot._switchToWorkspaceByModelData(
                                        popup.workspaceData);
                                popup.hide();
                                focusTimer.restart();
                            }
                        }
                    }
                }
            }

            // Empty state
            StyledText {
                anchors.centerIn: parent
                visible: popup.windowList.length === 0
                text: "No windows"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceTextMedium
            }
        }
    }

    // ── Window list refresh ────────────────────────────────────────────
    function _refreshWindowList() {
        if (!workspaceData) { windowList = []; return; }

        const targetId = _getWorkspaceId(workspaceData);
        if (targetId === null || targetId === undefined) {
            windowList = []; return;
        }

        const wins = CompositorService.isNiri
            ? (NiriService.windows || [])
            : CompositorService.sortedToplevels;

        const result = [];
        for (let i = 0; i < wins.length; i++) {
            const w = wins[i];
            if (!w) continue;

            const winWs = _getWindowWorkspaceId(w);
            if (winWs === null || winWs === undefined || winWs !== targetId)
                continue;

            const appId = w.app_id || w.appId || w.class
                          || w.windowClass || "unknown";
            const moddedId = Paths.moddedAppId(appId);
            const desktopEntry = DesktopEntries.heuristicLookup(moddedId);
            const icon = Paths.getAppIcon(moddedId, desktopEntry);
            const appName = Paths.getAppName(moddedId, desktopEntry);

            result.push({
                "windowId": w.address || w.id,
                "appId": appId,
                "appName": appName || appId,
                "title": w.title || appName || appId,
                "icon": icon,
                "isFocused": !!(w.activated || w.is_focused)
            });
        }
        windowList = result;
    }

    function _getWorkspaceId(wsData) {
        if (!wsData) return null;
        if (useExtWorkspace) return wsData.id || wsData.name;
        if (CompositorService.isNiri) return wsData.id;
        if (CompositorService.isHyprland) return wsData.id;
        if (CompositorService.isDwl) return wsData.tag;
        if (CompositorService.isSway || CompositorService.isScroll
            || CompositorService.isMiracle) return wsData.num;
        return null;
    }

    function _getWindowWorkspaceId(w) {
        if (CompositorService.isNiri) return w.workspace_id;
        if (CompositorService.isSway || CompositorService.isScroll
            || CompositorService.isMiracle) return w.workspace?.num;
        if (CompositorService.isHyprland) {
            const hyprTls = Array.from(Hyprland.toplevels?.values || []);
            const ht = hyprTls.find(ht => ht.wayland === w);
            return ht?.workspace?.id;
        }
        return null;
    }

    // ── Live-update connections ─────────────────────────────────────────
    Connections {
        target: CompositorService
        function onSortedToplevelsChanged() {
            if (popup.visible) popup._refreshWindowList();
        }
    }
    Connections {
        target: NiriService
        enabled: CompositorService.isNiri
        function onWindowsChanged() {
            if (popup.visible) popup._refreshWindowList();
        }
    }
}

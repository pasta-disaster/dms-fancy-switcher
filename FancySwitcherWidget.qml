import QtQuick
import Quickshell
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.I3
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root

    property bool isVertical: axis?.isVertical ?? false
    property var axis: null
    property real widgetThickness: 30
    property real barThickness: 48
    property var barConfig: null
    property var blurBarWindow: null
    property var hyprlandOverviewLoader: null
    property var parentScreen: null

    // Plugin service properties (injected by WidgetHost)
    property var pluginService: null
    property string pluginId: ""
    property string variantId: ""
    property var variantData: null

    function opt(key) {
        // 1. Plugin service config (e.g. from plugin_settings.json via FancySwitcherSettings)
        if (pluginService && pluginId) {
            const val = pluginService.loadPluginData(pluginId, key, undefined);
            if (val !== undefined && val !== null)
                return val;
        }

        // 2. Bar widget config for fancySwitcher (variantData or barWidgetEntry)
        const myEntry = variantData || SettingsData.barWidgetEntry(root.barConfig, "fancySwitcher");
        if (myEntry && myEntry[key] !== undefined && myEntry[key] !== null)
            return myEntry[key];

        // 3. Built-in workspaceSwitcher widget entry on this bar (Settings -> DankBar -> Workspace)
        const wsEntry = SettingsData.barWidgetEntry(root.barConfig, "workspaceSwitcher");
        if (wsEntry && wsEntry[key] !== undefined && wsEntry[key] !== null)
            return wsEntry[key];

        // 4. Any workspaceSwitcher entry across all bars in SettingsData
        if (SettingsData.barConfigs) {
            for (let i = 0; i < SettingsData.barConfigs.length; i++) {
                const otherWs = SettingsData.barWidgetEntry(SettingsData.barConfigs[i], "workspaceSwitcher");
                if (otherWs && otherWs[key] !== undefined && otherWs[key] !== null)
                    return otherWs[key];
            }
        }

        // 5. Explicit defaults for fancySwitcher
        if (key === "showWorkspaceIndex" || key === "showWorkspaceName")
            return false;
        if (key === "showOccupiedWorkspacesOnly")
            return true;

        // 6. Default from DMS BarWidgetDefaults
        return SettingsData.widgetOption("workspaceSwitcher", null, key);
    }

    // Derived from parentScreen — WidgetHost does not inject screenName
    // for plugin widgets, unlike the built-in WorkspaceSwitcher.
    readonly property string screenName: parentScreen ? parentScreen.name : ""

    readonly property real dpr: parentScreen ? CompositorService.getScreenScale(parentScreen) : 1
    readonly property real padding: (root.barConfig?.removeWidgetPadding ?? false)
                                    ? 0
                                    : Theme.snap((root.barConfig?.widgetPadding ?? 12)
                                                 * (widgetThickness / 30), dpr)

    readonly property bool useExtWorkspace: DMSService.forceExtWorkspace
        || (!CompositorService.isNiri && !CompositorService.isHyprland
            && !CompositorService.isDwl && !CompositorService.isSway
            && !CompositorService.isScroll && !CompositorService.isMiracle
            && ExtWorkspaceService.extWorkspaceAvailable)

    // Always show workspaces for THIS monitor, never follow focus.
    // The built-in switcher respects SettingsData.workspaceFollowFocus,
    // but this plugin is designed for per-monitor workspace navigation.
    readonly property string effectiveScreenName: root.screenName

    property var currentWorkspace: {
        if (useExtWorkspace)
            return _getExtWorkspaceActive();
        switch (CompositorService.compositor) {
        case "niri":    return _getNiriActive();
        case "hyprland": return _getHyprlandActive();
        case "dwl":
            const tags = _getDwlActiveTags();
            return tags.length > 0 ? tags[0] : -1;
        case "sway":
        case "scroll":
        case "miracle": return _getSwayActive();
        default: return 1;
        }
    }

    property var dwlActiveTags: CompositorService.isDwl ? _getDwlActiveTags() : []

    property var workspaceList: {
        let baseList;
        if (useExtWorkspace) {
            baseList = _getExtWorkspaceList();
        } else {
            switch (CompositorService.compositor) {
            case "niri":    baseList = _getNiriWorkspaces(); break;
            case "hyprland": baseList = _getHyprlandWorkspaces(); break;
            case "dwl":     baseList = _getDwlTags(); break;
            case "sway":
            case "scroll":
            case "miracle": baseList = _getSwayWorkspaces(); break;
            default: return [1];
            }
        }
        return root.opt("showWorkspacePadding") ? _padWorkspaces(baseList) : baseList;
    }

    readonly property bool hasNativeWorkspaceSupport:
        CompositorService.isNiri || CompositorService.isHyprland
        || CompositorService.isDwl || CompositorService.isSway
        || CompositorService.isScroll || CompositorService.isMiracle

    readonly property bool hasWorkspaces: _getRealWorkspaces().length > 0
    readonly property bool shouldShow: hasNativeWorkspaceSupport
                                       || (useExtWorkspace && hasWorkspaces)

    readonly property real visualWidth: isVertical
        ? widgetThickness
        : (workspaceRow.implicitWidth + padding * 2)
    readonly property real visualHeight: isVertical
        ? (workspaceRow.implicitHeight + padding * 2)
        : widgetThickness

    width:  shouldShow ? (isVertical ? barThickness : visualWidth) : 0
    height: shouldShow ? (isVertical ? visualHeight : barThickness) : 0
    visible: shouldShow

    // ── Hover popup state ──────────────────────────────────────────────
    property int hoveredWorkspaceIndex: -1
    property var hoveredWorkspaceData: null

    // ── Background ─────────────────────────────────────────────────────
    Item {
        id: visualBackground
        width: root.visualWidth
        height: root.visualHeight
        anchors.centerIn: parent

        Rectangle {
            anchors.fill: parent
            radius: (barConfig?.noBackground ?? false) ? 0 : Theme.cornerRadius
            color: {
                if (barConfig?.noBackground ?? false)
                    return "transparent";
                const baseColor = Theme.widgetBaseBackgroundColor;
                const transparency = (root.barConfig && root.barConfig.widgetTransparency !== undefined)
                    ? root.barConfig.widgetTransparency : 1.0;
                if (Theme.widgetBackgroundHasAlpha)
                    return Qt.rgba(baseColor.r, baseColor.g, baseColor.b, baseColor.a * transparency);
                return Theme.withAlpha(baseColor, transparency);
            }
        }
    }

    // ── Scroll handling (edge area) ────────────────────────────────────
    MouseArea {
        id: edgeMouseArea
        z: -1
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        property real touchpadAccumulator: 0
        property real mouseAccumulator: 0
        property bool scrollInProgress: false

        Timer {
            id: scrollCooldown
            interval: 100
            onTriggered: parent.scrollInProgress = false
        }

        onClicked: mouse => {
            const rootPos = edgeMouseArea.mapToItem(root, mouse.x, mouse.y);
            if (mouse.button === Qt.LeftButton) {
                const idx = _findClosestWorkspaceIndex(rootPos.x, rootPos.y);
                if (idx >= 0) _switchToWorkspaceByModelData(root.workspaceList[idx]);
            } else if (mouse.button === Qt.RightButton) {
                if (CompositorService.isNiri) NiriService.toggleOverview();
                else if (CompositorService.isHyprland && root.hyprlandOverviewLoader?.item)
                    root.hyprlandOverviewLoader.item.overviewOpen = !root.hyprlandOverviewLoader.item.overviewOpen;
            }
        }

        onWheel: wheel => {
            if (Math.abs(wheel.angleDelta.x) > Math.abs(wheel.angleDelta.y)) {
                wheel.accepted = false;
                return;
            }
            if (scrollInProgress) return;
            const delta = wheel.angleDelta.y;
            const isTouchpad = wheel.pixelDelta && wheel.pixelDelta.y !== 0;
            const reverse = root.opt("reverseScrolling") ? -1 : 1;

            if (isTouchpad) {
                touchpadAccumulator += delta;
                if (Math.abs(touchpadAccumulator) < 500) return;
                _switchWorkspace(touchpadAccumulator * reverse < 0 ? 1 : -1);
                scrollInProgress = true;
                scrollCooldown.restart();
                touchpadAccumulator = 0;
            } else {
                mouseAccumulator += delta;
                if (Math.abs(mouseAccumulator) < 120) return;
                _switchWorkspace(mouseAccumulator * reverse < 0 ? 1 : -1);
                scrollInProgress = true;
                scrollCooldown.restart();
                mouseAccumulator = 0;
            }
        }
    }

    // ── Workspace pips ─────────────────────────────────────────────────
    Flow {
        id: workspaceRow
        x: isVertical ? visualBackground.x : (parent.width - implicitWidth) / 2
        y: isVertical ? (parent.height - implicitHeight) / 2 : (parent.height - implicitHeight) / 2
        spacing: Theme.spacingS
        flow: isVertical ? Flow.TopToBottom : Flow.LeftToRight

        Repeater {
            id: workspaceRepeater
            model: ScriptModel { values: root.workspaceList }

            delegate: FancySwitcherPip {
                workspaceData: modelData
                workspaceIndex: index
                switcherRoot: root
                isActive: _isWorkspaceActive(modelData)
                isPlaceholder: _isPlaceholder(modelData)
                isVerticalBar: root.isVertical
                pipWidgetHeight: root.widgetThickness
                pipBarThickness: root.barThickness
                barConfig: root.barConfig
                currentWorkspaceId: root.currentWorkspace
                dwlActiveTagsList: root.dwlActiveTags
                useExtWorkspace: root.useExtWorkspace

                onPipClicked: data => root._switchToWorkspaceByModelData(data)
                onPipRightClicked: {
                    if (CompositorService.isNiri) NiriService.toggleOverview();
                    else if (CompositorService.isHyprland && root.hyprlandOverviewLoader?.item)
                        root.hyprlandOverviewLoader.item.overviewOpen =
                            !root.hyprlandOverviewLoader.item.overviewOpen;
                }
                onHoverEntered: (data, idx) => {
                    root.hoveredWorkspaceIndex = idx;
                    root.hoveredWorkspaceData = data;
                    hoverPopupLoader.active = true;
                    if (hoverPopupLoader.item) {
                        hoverPopupLoader.item.targetPipItem = workspaceRepeater.itemAt(idx);
                        hoverPopupLoader.item.show();
                    }
                }
                onHoverExited: {
                    if (hoverPopupLoader.item)
                        hoverPopupLoader.item.scheduleHide();
                }
            }
        }
    }

    // ── Hover popup (lazy-loaded PanelWindow) ──────────────────────────
    Loader {
        id: hoverPopupLoader
        active: false

        sourceComponent: FancySwitcherPopup {
            id: hoverPopup
            workspaceData: root.hoveredWorkspaceData
            screenName: root.effectiveScreenName
            useExtWorkspace: root.useExtWorkspace
            isVerticalBar: root.isVertical
            barThickness: root.barThickness
            barConfig: root.barConfig
            parentScreen: root.parentScreen
            switcherRoot: root

            onWindowActivated: (windowId) => {
                _focusWindowById(windowId);
            }


        }
    }

    // ── Blur registration ──────────────────────────────────────────────
    property bool _blurRegistered: false
    readonly property bool _shouldBlur: BlurService.enabled && blurBarWindow
        && blurBarWindow.registerBlurWidget
        && !(barConfig?.noBackground ?? false)
        && root.visible && root.width > 0

    on_ShouldBlurChanged: _updateBlurRegistration()

    function _updateBlurRegistration() {
        if (_shouldBlur && !_blurRegistered) {
            blurBarWindow.registerBlurWidget(visualBackground);
            _blurRegistered = true;
        } else if (!_shouldBlur && _blurRegistered) {
            if (blurBarWindow && blurBarWindow.unregisterBlurWidget)
                blurBarWindow.unregisterBlurWidget(visualBackground);
            _blurRegistered = false;
        }
    }

    Component.onCompleted: {
        if (useExtWorkspace && !DMSService.activeSubscriptions.includes("extworkspace"))
            DMSService.addSubscription("extworkspace");
        _updateBlurRegistration();
    }

    Component.onDestruction: {
        if (_blurRegistered && blurBarWindow && blurBarWindow.unregisterBlurWidget)
            blurBarWindow.unregisterBlurWidget(visualBackground);
    }

    // ══════════════════════════════════════════════════════════════════
    // Compositor-abstracted helpers (mirroring WorkspaceSwitcher.qml)
    // ══════════════════════════════════════════════════════════════════

    function _isWorkspaceActive(modelData) {
        if (useExtWorkspace)
            return (modelData?.id || modelData?.name) === currentWorkspace;
        if (CompositorService.isNiri)
            return !!(modelData && modelData.id === currentWorkspace);
        if (CompositorService.isHyprland)
            return !!(modelData && modelData.id === currentWorkspace);
        if (CompositorService.isDwl)
            return !!(modelData && dwlActiveTags.includes(modelData.tag));
        if (CompositorService.isSway || CompositorService.isScroll || CompositorService.isMiracle)
            return !!(modelData && modelData.num === currentWorkspace);
        return modelData === currentWorkspace;
    }

    function _isPlaceholder(modelData) {
        if (useExtWorkspace) return !!(modelData && modelData.hidden);
        if (CompositorService.isNiri) return !!(modelData && (modelData.id === -1 || modelData.idx === -1));
        if (CompositorService.isHyprland) return !!(modelData && modelData.id === -1);
        if (CompositorService.isDwl) return !!(modelData && modelData.tag === -1);
        if (CompositorService.isSway || CompositorService.isScroll || CompositorService.isMiracle)
            return !!(modelData && modelData.num === -1);
        return modelData === -1;
    }

    function _switchToWorkspaceByModelData(data) {
        if (!data) return;
        if (root.useExtWorkspace && (data.id || data.name)) {
            ExtWorkspaceService.activateWorkspace(data.id || data.name, data.groupID || "");
            return;
        }
        switch (CompositorService.compositor) {
        case "niri":
            if (data.id !== undefined && data.id !== -1)
                NiriService.switchToWorkspace(data.id);
            else if (data.idx !== undefined && data.idx !== -1)
                NiriService.switchToWorkspace(data.idx);
            break;
        case "hyprland":
            if (data.id) Hyprland.dispatch(`workspace ${data.id}`); break;
        case "dwl":
            if (data.tag !== undefined) DwlService.switchToTag(root.screenName, data.tag); break;
        case "sway": case "scroll": case "miracle":
            if (data.num) try { I3.dispatch(`workspace number ${data.num}`); } catch(_) {} break;
        }
    }

    function _focusWindowById(windowId) {
        if (!windowId) return;
        if (CompositorService.isHyprland) {
            Hyprland.dispatch(`focuswindow address:${windowId}`);
        } else if (CompositorService.isNiri) {
            NiriService.focusWindow(windowId);
        } else if (CompositorService.isSway || CompositorService.isScroll || CompositorService.isMiracle) {
            try { I3.dispatch(`[con_id=${windowId}] focus`); } catch(_) {}
        }
    }

    function _switchWorkspace(direction) {
        const realWorkspaces = _getRealWorkspaces();
        if (realWorkspaces.length < 2) return;

        let currentIndex = -1;
        if (useExtWorkspace) {
            currentIndex = realWorkspaces.findIndex(ws => (ws.id || ws.name) === currentWorkspace);
        } else if (CompositorService.isNiri) {
            currentIndex = realWorkspaces.findIndex(ws => ws && ws.id === currentWorkspace);
        } else if (CompositorService.isHyprland) {
            currentIndex = realWorkspaces.findIndex(ws => ws.id === currentWorkspace);
        } else if (CompositorService.isDwl) {
            currentIndex = realWorkspaces.findIndex(ws => ws.tag === currentWorkspace);
        } else if (CompositorService.isSway || CompositorService.isScroll || CompositorService.isMiracle) {
            currentIndex = realWorkspaces.findIndex(ws => ws.num === currentWorkspace);
        }

        const validIndex = currentIndex === -1 ? 0 : currentIndex;
        const nextIndex = direction > 0
            ? Math.min(validIndex + 1, realWorkspaces.length - 1)
            : Math.max(validIndex - 1, 0);
        if (nextIndex === validIndex) return;
        _switchToWorkspaceByModelData(realWorkspaces[nextIndex]);
    }

    function _getRealWorkspaces() {
        return root.workspaceList.filter(ws => {
            if (useExtWorkspace) return ws && (ws.id !== "" || ws.name !== "") && !ws.hidden;
            if (CompositorService.isNiri) return ws && ws.idx !== -1;
            if (CompositorService.isHyprland) return ws && ws.id !== -1;
            if (CompositorService.isDwl) return ws && ws.tag !== -1;
            if (CompositorService.isSway || CompositorService.isScroll || CompositorService.isMiracle)
                return ws && ws.num !== -1;
            return ws !== -1;
        });
    }

    function _findClosestWorkspaceIndex(localX, localY) {
        if (workspaceRepeater.count === 0) return -1;
        let closestIdx = -1, closestDist = Infinity;
        for (let i = 0; i < workspaceRepeater.count; i++) {
            const item = workspaceRepeater.itemAt(i);
            if (!item) continue;
            const center = item.mapToItem(root, item.width / 2, item.height / 2);
            const dist = isVertical ? Math.abs(localY - center.y) : Math.abs(localX - center.x);
            if (dist < closestDist) { closestDist = dist; closestIdx = i; }
        }
        return closestIdx;
    }

    function _padWorkspaces(list) {
        const padded = list.slice();
        let placeholder;
        if (useExtWorkspace) placeholder = {"id":"","name":"","active":false,"hidden":true};
        else if (CompositorService.isNiri) placeholder = {"id":-1,"idx":-1,"name":""};
        else if (CompositorService.isHyprland) placeholder = {"id":-1,"name":""};
        else if (CompositorService.isDwl) placeholder = {"tag":-1};
        else if (CompositorService.isSway || CompositorService.isScroll || CompositorService.isMiracle)
            placeholder = {"num":-1};
        else placeholder = -1;
        const minCount = root.opt("workspacePaddingCount") || 3;
        while (padded.length < minCount) padded.push(placeholder);
        return padded;
    }

    // ── Compositor-specific workspace getters ──────────────────────────
    function _getSwayWorkspaces() {
        const workspaces = I3.workspaces?.values || [];
        if (workspaces.length === 0) return [{"num":1}];
        function mapWs(ws) {
            return {"num":ws.number,"name":ws.name,"focused":ws.focused,
                    "active":ws.active,"urgent":ws.urgent,"monitor":ws.monitor};
        }
        if (!root.screenName)
            return workspaces.slice().sort((a,b) => a.num - b.num).map(mapWs);
        const filtered = workspaces.filter(ws => ws.monitor?.name === root.screenName);
        return filtered.length > 0 ? filtered.sort((a,b) => a.num - b.num).map(mapWs) : [{"num":1}];
    }

    function _getSwayActive() {
        if (!root.screenName) {
            const ws = I3.workspaces?.values?.find(ws => ws.focused === true);
            return ws ? ws.num : 1;
        }
        const ws = I3.workspaces?.values?.find(ws => ws.monitor?.name === root.screenName && ws.focused === true);
        return ws ? ws.num : 1;
    }

    function _getHyprlandWorkspaces() {
        const workspaces = Hyprland.workspaces?.values || [];
        if (workspaces.length === 0) return [{"id":1,"name":"1"}];
        let filtered = workspaces.filter(ws => ws.id > -1);
        if (filtered.length === 0) return [{"id":1,"name":"1"}];
        if (!root.screenName) {
            filtered = filtered.slice().sort((a,b) => a.id - b.id);
        } else {
            const monWs = filtered.filter(ws => ws.monitor?.name === root.screenName);
            filtered = monWs.length > 0 ? monWs.sort((a,b) => a.id - b.id) : [{"id":1,"name":"1"}];
        }
        if (!root.opt("showOccupiedWorkspacesOnly")) return filtered;
        const hyprTls = Array.from(Hyprland.toplevels?.values || []);
        const activeId = root.currentWorkspace;
        return filtered.filter(ws => ws.id === activeId || hyprTls.some(tl => tl.workspace?.id === ws.id));
    }

    function _getHyprlandActive() {
        if (!root.screenName)
            return Hyprland.focusedWorkspace?.id || 1;
        const mon = Hyprland.monitors?.values?.find(m => m.name === root.screenName);
        return mon?.activeWorkspace?.id || 1;
    }

    function _getNiriWorkspaces() {
        if (NiriService.allWorkspaces.length === 0)
            return [{"id":1,"idx":0,"name":""},{"id":2,"idx":1,"name":""}];
        const fallback = [{"id":1,"idx":0,"name":""},{"id":2,"idx":1,"name":""}];
        let workspaces;
        if (!root.screenName) {
            const cur = NiriService.getCurrentOutputWorkspaces();
            workspaces = cur.length > 0 ? cur : fallback;
        } else {
            const disp = NiriService.allWorkspaces.filter(ws => ws.output === root.screenName);
            workspaces = disp.length > 0 ? disp : fallback;
        }
        workspaces = workspaces.slice().sort((a,b) => a.idx - b.idx);
        if (!root.opt("showOccupiedWorkspacesOnly")) return workspaces;
        return workspaces.filter(ws => ws.is_active || (NiriService.windows?.some(win => win.workspace_id === ws.id) ?? false));
    }

    function _getNiriActive() {
        if (NiriService.allWorkspaces.length === 0) return 1;
        if (!root.screenName)
            return NiriService.getCurrentWorkspaceNumber();
        const ws = NiriService.allWorkspaces.find(ws => ws.output === root.screenName && ws.is_active);
        return ws ? ws.id : 1;
    }

    function _getDwlTags() {
        if (!DwlService.dwlAvailable) return [];
        const output = DwlService.getOutputState(root.effectiveScreenName);
        if (!output || !output.tags || output.tags.length === 0) return [];
        if (root.opt("dwlShowAllTags"))
            return output.tags.map(t => ({"tag":t.tag,"state":t.state,"clients":t.clients,"focused":t.focused}));
        return DwlService.getVisibleTags(root.effectiveScreenName).map(tagIndex => {
            const td = output.tags.find(t => t.tag === tagIndex);
            return {"tag":tagIndex,"state":td?.state??0,"clients":td?.clients??0,"focused":td?.focused??false};
        });
    }

    function _getDwlActiveTags() {
        if (!DwlService.dwlAvailable) return [];
        return DwlService.getActiveTags(root.effectiveScreenName);
    }

    function _getExtWorkspaceList() {
        const groups = ExtWorkspaceService.groups;
        if (!ExtWorkspaceService.extWorkspaceAvailable || groups.length === 0)
            return [{"id":"1","name":"1","active":false}];
        const group = groups.find(g => g.outputs && g.outputs.includes(root.screenName));
        if (!group || !group.workspaces)
            return [{"id":"1","name":"1","active":false}];
        let visible = group.workspaces.filter(ws => !ws.hidden);
        const hasCoords = visible.some(ws => ws.coordinates && ws.coordinates.length > 0);
        if (hasCoords) {
            visible = visible.sort((a,b) => {
                const ca = a.coordinates || [0,0], cb = b.coordinates || [0,0];
                if (ca[0] !== cb[0]) return ca[0] - cb[0];
                return ca[1] - cb[1];
            });
        }
        visible = visible.map(ws => ({
            id: ws.id, name: ws.name, coordinates: ws.coordinates,
            state: ws.state, active: ws.active, urgent: ws.urgent,
            hidden: ws.hidden, groupID: group.id
        }));
        return visible.length > 0 ? visible : [{"id":"1","name":"1","active":false}];
    }

    function _getExtWorkspaceActive() {
        if (!ExtWorkspaceService.extWorkspaceAvailable) return 1;
        const ws = ExtWorkspaceService.getActiveWorkspaceForOutput(root.screenName);
        return ws ? (ws.id || ws.name || "1") : "1";
    }
}

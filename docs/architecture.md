# Architecture & Design

## Overview

Fancy Workspace Switcher is a DMS bar widget plugin (`type: "widget"`) that extends the default workspace switcher with hover-activated window preview popups.

## Component Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│  DankBar (host)                                                 │
│    WidgetHost loads FancySwitcherWidget via plugin.json          │
│    Injects: axis, screenName, barThickness, barConfig, etc.     │
└─────────┬───────────────────────────────────────────────────────┘
          │
          ▼
┌─────────────────────────────────────────────────────────────────┐
│  FancySwitcherWidget.qml                                        │
│  ─────────────────────────                                      │
│  Responsibilities:                                              │
│  • Determines workspace list via compositor-specific logic      │
│  • Manages scroll-to-switch, click-to-switch                    │
│  • Tracks hover state (hoveredWorkspaceIndex/Data)              │
│  • Contains Flow of FancySwitcherPip delegates                  │
│  • Hosts lazy-loaded FancySwitcherPopup (PanelWindow overlay)    │
│                                                                 │
│  ┌─────────────────────┐    ┌─────────────────────┐             │
│  │ FancySwitcherPip (N) │    │ FancySwitcherPopup  │             │
│  │ ─────────────────── │    │ ──────────────────── │             │
│  │ • Visual pip rect   │───▶│ • Window enumeration │             │
│  │ • Hover detection   │    │ • Icon resolution    │             │
│  │ • Click signals     │    │ • Focus-on-click     │             │
│  │ • Label rendering   │    │ • Auto-hide timer    │             │
│  └─────────────────────┘    └─────────────────────┘             │
└─────────────────────────────────────────────────────────────────┘
```

## Data Flow

1. **Workspace detection**: The widget queries compositor-specific APIs (Hyprland, Niri, Sway/I3, DWL, ext-workspace) to build `workspaceList` and identify `currentWorkspace`
2. **Pip rendering**: Each workspace in the list creates a `FancySwitcherPip` delegate with active/urgent/occupied visual states
3. **Hover trigger**: When the mouse enters a pip, `hoverEntered` fires → widget sets `hoveredWorkspaceData` → popup's `show()` is called
4. **Window enumeration**: The popup queries `CompositorService.sortedToplevels` (or `NiriService.windows`) and filters by the hovered workspace's ID
5. **Icon resolution**: Each window's `app_id` is resolved through `Paths.moddedAppId()` → `DesktopEntries.heuristicLookup()` → `Paths.getAppIcon()`
6. **Focus action**: Clicking a window item first switches to the workspace via `_switchToWorkspaceByModelData`, then dispatches a compositor-specific focus command

## Compositor Abstraction

All compositor differences are encapsulated in helper functions prefixed with `_get*` and `_is*`:

| Compositor | Workspace ID field | Window→WS mapping |
|---|---|---|
| Hyprland | `ws.id` | `Hyprland.toplevels → tl.workspace.id` |
| Niri | `ws.id` (internal), `ws.idx` (display) | `w.workspace_id` |
| Sway/Scroll/Miracle | `ws.num` | `w.workspace.num` |
| DWL | `ws.tag` | Tag-based client count |
| ext-workspace | `ws.id` or `ws.name` | N/A (protocol-level) |

## Popup Lifecycle

```
Mouse enters pip
  → hoverEntered signal
  → popup.show()
  → _refreshWindowList()
  → popup becomes visible

Mouse leaves pip
  → hoverExited signal  
  → popup.scheduleHide() (300ms timer)
  
  If mouse enters popup within 300ms:
    → timer cancelled, popup stays open
  
  If mouse leaves popup:
    → scheduleHide() again → popup hides after 300ms

Click on window item:
  → switch workspace + focus window
  → popup.hide() immediately
```

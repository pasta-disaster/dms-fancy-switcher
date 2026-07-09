# Fancy Workspace Switcher

A DankMaterialShell (DMS) plugin that enhances the workspace switcher widget on the Dank Bar with hover-to-preview window popups.

## Features

- **Workspace pips** — Shows the same workspace pips as the built-in switcher, with click-to-switch and scroll-to-navigate
- **Hover popup** — Hovering over any workspace pip reveals a popup listing all windows open on that workspace
- **Click to focus** — Click any window in the popup to switch to that workspace and focus the window
- **Live updates** — The popup dynamically updates as windows are opened, closed, or moved
- **Multi-compositor support** — Works with Hyprland, Niri, Sway, Scroll, Miracle WM, DWL, and ext-workspace protocol

## Installation

1. Copy/symlink this directory to the DMS plugins folder:

   ```bash
   ln -s /path/to/fancy-switcher ~/.config/DankMaterialShell/plugins/fancySwitcher
   ```

2. In DMS Settings → Plugins, enable **Fancy Workspace Switcher**

3. In DMS Settings → DankBar → Widget Layout, add the `fancySwitcher` widget to your bar (and optionally remove the built-in `workspaceSwitcher`)

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  FancySwitcherWidget.qml                                     │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Flow (workspaceRow)                                   │  │
│  │  ┌──────┐ ┌──────┐ ┌──────┐                           │  │
│  │  │ Pip1 │ │ Pip2 │ │ Pip3 │  ← FancySwitcherPip.qml   │  │
│  │  └──┬───┘ └──┬───┘ └──────┘                           │  │
│  │     │        │                                         │  │
│  │     │  hover │                                         │  │
│  │     ▼        ▼                                         │  │
│  │  ┌────────────────────┐                                │  │
│  │  │ FancySwitcherPopup │  ← Window list popup           │  │
│  │  │ ┌────────────────┐ │                                │  │
│  │  │ │ 🌐 Firefox     │ │                                │  │
│  │  │ │ 📁 Files       │ │                                │  │
│  │  │ │ 💻 Terminal    │ │                                │  │
│  │  │ └────────────────┘ │                                │  │
│  │  └────────────────────┘                                │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

### Files

| File | Purpose |
|---|---|
| `plugin.json` | Plugin metadata and registration |
| `FancySwitcherWidget.qml` | Main widget — workspace detection, pip layout, scroll/click handling |
| `FancySwitcherPip.qml` | Individual workspace pip — visual styling, hover/click signals |
| `FancySwitcherPopup.qml` | Hover popup — window enumeration, icon resolution, focus action |
| `FancySwitcherSettings.qml` | Settings panel (informational) |

## Theming

The plugin inherits all DMS theme settings automatically:
- Workspace pip colours follow the workspace colour mode settings
- Popup uses the standard DMS surface container with popup transparency
- Typography uses the bar's configured font scale

## Compatibility

- **DMS**: Tested with `dms-git` 1.4.5+
- **Quickshell**: Uses standard QML and Quickshell APIs
- **Compositors**: Hyprland, Niri, Sway, Scroll, Miracle WM, DWL, and any compositor supporting ext-workspace-unstable-v1

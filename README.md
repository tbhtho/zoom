# AE Timeline Zoom

Menu-bar utility for After Effects on macOS.

- **Ctrl + scroll over the Timeline** zooms the time ruler around the pointer.
- **Plain scroll is untouched**, so normal up/down scrolling keeps working.
- Horizontal scroll and Ctrl+scroll outside the Timeline always pass through.

The app installs a session-level `CGEvent` tap and rewrites only vertical
Control+scroll events whose location falls inside the Timeline panel, converting
them to After Effects' native Option+scroll zoom. Nothing else is intercepted,
and it never touches the After Effects installation.

## Requirements

- macOS 13 or newer
- After Effects 2022 or 2025 (the Timeline split is read from the saved workspace)
- Accessibility permission for the app

## Build

```sh
./build.sh              # build/AE Timeline Zoom.app
./build.sh --install    # copy to /Applications/AE Timeline Zoom.app
```

`build.sh` signs the bundle ad-hoc with the identifier `local.ae.timelinezoom`
so the Accessibility grant survives rebuilds.

## Install

```sh
./build.sh --install
open "/Applications/AE Timeline Zoom.app"
```

Grant Accessibility when macOS asks (or use the menu item **Open Accessibility
Settings**). The menu-bar item shows `AE Zoom` once the event tap is running.
The app registers itself as a login item on first launch; toggle it from the
menu.

## Menu

| Item | Action |
| --- | --- |
| Control+Scroll Zoom in Timeline | Enable/disable the remap |
| Show Timeline Zone | Flash the detected Timeline rectangle |
| Recompute Zone from Workspace | Re-read AE's `UserWorkspace.xml` |
| Open Accessibility Settings | Jump to the Privacy pane |
| Open Config Folder | Reveal the config file |
| Start at Login | Register/unregister the login item |

## Config

`~/Library/Application Support/AETimelineZoom/config.json` is created on first
launch:

```json
{
  "enabled": true,
  "mode": "optionScroll",
  "timelineTopFraction": null,
  "chromeTop": 64,
  "statusBar": 17,
  "invertDirection": false,
  "verbose": false
}
```

- `mode`: `optionScroll` for native pointer-centred zoom, `keys` to send `=` / `-`.
- `timelineTopFraction`: `null` reads the Timeline split from
  `~/Library/Preferences/Adobe/After Effects/<version>/ModifiedWorkspaces/UserWorkspace.xml`;
  set a value between 0 and 1 to override.
- `chromeTop` / `statusBar`: pixels excluded above and below the panel area.
- `invertDirection`: flips the zoom direction.
- `verbose`: log each remapped event to stderr / unified log.

## Verify

Routing logic can be tested without After Effects or Accessibility:

```sh
"/Applications/AE Timeline Zoom.app/Contents/MacOS/AETimelineZoom" --router-selftest
```

It prints eight PASS/FAIL lines and exits non-zero on failure. With After
Effects running and frontmost, `--selftest` checks the detected Timeline
rectangle against four probe points.

`tools/aescroll.swift` posts synthetic scroll gestures for manual testing:

```sh
xcrun swiftc -O tools/aescroll.swift -o /tmp/aescroll -framework Cocoa
/tmp/aescroll 3 900 855 1 ctrl   # Ctrl+scroll up inside the Timeline
/tmp/aescroll -3 900 855 1       # plain scroll down
```

## Uninstall

Uncheck **Start at Login**, quit from the menu, delete the app, and optionally
remove `~/Library/Application Support/AETimelineZoom/`.

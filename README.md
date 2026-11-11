# AE Timeline Zoom

Ctrl+scroll timeline zoom for **After Effects 2022**. AE 2022 has no
Ctrl+scroll zoom for the timeline; this menu-bar utility adds one without
touching the app.

Hold **Control** and scroll over the Timeline to zoom around the pointer.
Plain scroll is untouched, so normal up/down scrolling still works. Horizontal
scroll and Ctrl+scroll outside the Timeline pass through.

## Build

```sh
./build.sh --install
open "/Applications/AE Timeline Zoom.app"
```

Grant Accessibility when macOS asks. The app registers as a login item on first
launch; toggle it from the menu-bar item.

## Config

`~/Library/Application Support/AETimelineZoom/config.json`

- `invertDirection` — flip zoom direction.
- `mode` — `optionScroll` (native, pointer-centred) or `keys` (`=` / `-`).
- `timelineTopFraction` — `null` reads the Timeline split from AE's
  `UserWorkspace.xml`.

## Test

```sh
"/Applications/AE Timeline Zoom.app/Contents/MacOS/AETimelineZoom" --router-selftest
```

## How it works

A session-level `CGEvent` tap rewrites only vertical Control+scroll events inside
the Timeline panel into After Effects' native Option+scroll zoom. Everything else
is left alone.

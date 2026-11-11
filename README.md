# AE Timeline Zoom

Adds modifier+scroll timeline zoom to **After Effects 2022**, which has no
built-in scroll-wheel zoom for the Timeline.

Hold **Command** and scroll over the Timeline to zoom around the pointer.
Plain scroll is untouched, so normal up/down scrolling still works. Horizontal
scroll and modifier+scroll outside the Timeline pass through.

## Build

```sh
./build.sh --install
open "/Applications/AE Timeline Zoom.app"
```

Grant Accessibility when macOS asks. The app registers as a login item on first
launch; toggle it from the menu-bar item.

## Config

`~/Library/Application Support/AETimelineZoom/config.json`

- `zoomModifier` — `command` (default), `control`, `option`, `shift`. Also in the menu.
- `invertDirection` — flip zoom direction.
- `mode` — `optionScroll` (native, pointer-centred) or `keys` (`=` / `-`).
- `timelineTopFraction` — `null` reads the Timeline split from AE's
  `UserWorkspace.xml`.

## Test

```sh
"/Applications/AE Timeline Zoom.app/Contents/MacOS/AETimelineZoom" --router-selftest
```

## How it works

A session-level `CGEvent` tap rewrites only modifier+vertical scroll events inside
the Timeline panel into After Effects' native Option+scroll zoom. Everything else
is left alone.

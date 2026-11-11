<h1 align="center">AE Timeline Zoom</h1>

<p align="center"><b>Scroll-wheel zoom for the After Effects 2022 timeline.</b><br>
Hold Command and scroll over the Timeline to zoom around the pointer.</p>

<p align="center">
  <img src="https://img.shields.io/badge/After_Effects-2022-9999FF.svg" alt="After Effects 2022">
  <img src="https://img.shields.io/badge/platform-macOS-blue.svg" alt="Platform: macOS">
  <img src="https://img.shields.io/badge/app-menu_bar-lightgrey.svg" alt="Menu-bar app">
  <img src="https://img.shields.io/badge/language-Swift-orange.svg" alt="Language: Swift">
</p>

## What it does

After Effects 2022 has no built-in scroll-wheel zoom for the Timeline. This menu-bar app adds it.

| Input | Result |
|---|---|
| Command + scroll over the Timeline | Zooms the timeline around the pointer |
| Plain scroll | Unchanged, scrolls layers as usual |
| Horizontal scroll | Unchanged |
| Command + scroll outside the Timeline | Unchanged |

## Install

You need the Xcode command line tools (`xcode-select --install`).

```sh
./build.sh --install
open "/Applications/AE Timeline Zoom.app"
```

Grant Accessibility when macOS asks. The app registers as a login item on first launch; toggle that from the menu-bar item.

## Settings

The modifier key can be changed from the menu-bar item. Everything else is in `~/Library/Application Support/AETimelineZoom/config.json`:

| Key | Values | What it does |
|---|---|---|
| `zoomModifier` | `command` (default), `control`, `option`, `shift` | The key to hold while scrolling |
| `invertDirection` | `true`, `false` | Flips the zoom direction |
| `mode` | `optionScroll` (default), `keys` | `optionScroll` zooms around the pointer; `keys` sends `=` and `-` instead |
| `timelineTopFraction` | a number, or `null` | Where the Timeline starts. `null` reads it from AE's saved workspace |

## How it works

A session-level `CGEvent` tap rewrites modifier + vertical scroll events inside the Timeline panel into After Effects' own Option + scroll zoom. Every other event is left alone.

To run the built-in self-test:

```sh
"/Applications/AE Timeline Zoom.app/Contents/MacOS/AETimelineZoom" --router-selftest
```

## Related

[AE 2022 on Apple Silicon](https://github.com/tbhtho/AE2022-Apple-Silicon) covers running After Effects 2022 and older Intel plugins on M-series Macs.

Not affiliated with or endorsed by Adobe.

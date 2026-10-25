<p align="center"><img src="design/kit/github/readme-banner.png" alt="Podium: Stage your work. A Stage Manager alternative for macOS." width="100%"></p>

Podium is a free, open-source menu bar app that replaces Apple's Stage Manager. The strip of recent windows sits on the left or the right of your screen, the Dock never moves, and nothing needs SIP changes.

Podium is not affiliated with or endorsed by Apple. "Stage Manager" is a trademark of Apple Inc.

## Install

**Download:** get `Podium-<version>.dmg` from the [Releases](../../releases) page, open it, and drag Podium to Applications.

Releases are not notarized yet, so macOS shows an "unidentified developer" warning the first time. To open the app anyway, right-click Podium in Applications and choose Open, or go to System Settings > Privacy & Security and click Open Anyway.

**Or build it yourself:** see [Build from source](#build-from-source).

Requires macOS 14 or later.

## First launch

Podium asks for two permissions:

- **Accessibility** lets Podium move and raise windows.
- **Screen Recording** lets Podium draw live thumbnails of your windows. Nothing is recorded or sent anywhere.

Turn Apple's Stage Manager off first (System Settings > Desktop & Dock). Podium will not run while it is on.

## What it does

- A strip of your recent windows on the left or right edge, with piles of up to three windows per app and the app icon on each item.
- Click an item to bring its windows on stage. Shift-click adds it to the current stage. Drag an item onto the stage to combine them.
- Drag a window by its title bar into the strip, or minimize it to the strip, instead of the Dock.
- Click the wallpaper to show the desktop, and click it again to bring your windows back.
- Optional Dock-icon shortcuts: click the front app's icon to minimize it to the strip, and Shift-click another app's icon to add it to the stage.
- Auto-hide when a window covers the strip, with a peek at the edge.
- Show all of an app's windows at once, or one at a time.
- Floating apps: windows of the apps you list (Archive Utility, qView and Preview by default) open over the stage and leave it alone.
- Settings for thumbnail size and shape, tilt, icon size, strip side, launch at login, and a hotkey (Control-Option-Command-P) that turns Podium on and off.

## Your windows stay safe

Podium parks the windows it hides, and it writes each one to `~/Library/Application Support/Podium/parked.json`. If Podium quits or crashes, the next launch puts them back. **Restore All Windows** in the menu bar does the same on demand.

## Build from source

You need the Swift 6 toolchain (Xcode or the Command Line Tools).

```bash
scripts/make-dev-cert.sh   # once: a local code-signing identity, so macOS keeps your permissions across rebuilds
scripts/run.sh             # builds build/Podium.app, signs it and launches it
scripts/test.sh            # runs the tests
scripts/make-dmg.sh        # builds build/Podium-<version>.dmg
```

Set `PODIUM_SIGN_IDENTITY` to use a different signing identity (`-` for ad-hoc). Ad-hoc signing makes macOS forget the permissions on every rebuild.

## Uninstall

Quit Podium from the menu bar, delete it from Applications, and remove its settings and parking file:

```bash
defaults delete dev.podium.Podium
rm -rf ~/Library/Application\ Support/Podium
```

## How it is built

`PodiumCore` is a pure Swift library with the stage model, strip layout and safety logic, and it has no AppKit dependency. `Podium` is the menu bar app on top of it. The notes in [`docs/research`](docs/research) record how Apple's Stage Manager decides what goes on stage and in the strip, and the values Podium takes from it.

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first.

## License

[MIT](LICENSE)

# ccusage-touchbar

Your Claude Code spend, live in the MacBook Pro Touch Bar.

![Touch Bar showing ✦$130 in the Control Strip](docs/touchbar.png)

A ~100-line Swift app that puts a button in the Touch Bar's **Control Strip**
(so your normal Touch Bar stays intact) showing today's
[ccusage](https://github.com/ccusage/ccusage) cost. Tap it for the full line:

```
✦ $127 today · $51 block · 2h14m
```

today's cost · cost of the current 5-hour billing block · time left in that block.
Refreshes every 60 seconds.

## Why not MTMR / BetterTouchTool?

MTMR does this with a shell-script button, but its last release isn't notarized,
so current macOS blocks it. BetterTouchTool is paid. Building locally sidesteps
Gatekeeper entirely: a binary you compile yourself is never quarantined.

## Install

Needs a Touch Bar Mac, Xcode command line tools, Node, and ccusage:

```sh
npm i -g ccusage
./install.sh      # builds, copies to ~/Applications, adds a login item
```

Uninstall: quit `CCUsageBar`, delete `~/Applications/CCUsageBar.app`, and remove it
from System Settings → General → Login Items.

## How it works

- `ccusage-line.sh` runs `ccusage daily` and `ccusage blocks --active` (both
  `--json --offline`) and formats one line with Node.
- `main.swift` places an `NSCustomTouchBarItem` in the Control Strip through the
  private `NSTouchBarItem addSystemTrayItem:` and
  `DFRElementSetControlStripPresenceForIdentifier` (DFRFoundation), the same calls
  MTMR and Pock use. Tapping presents a system-modal Touch Bar with the full line.
- It's an `LSUIElement` agent: no Dock icon, no menu bar.

Private APIs mean no App Store, and a future macOS could break it.

## License

MIT

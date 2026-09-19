# ccusage-touchbar

Your Claude plan limits, always on the MacBook Pro Touch Bar.

![Touch Bar: ✳ 5h 45% · 23:10, week 12% · Mon 06:00, Fable 15%, then the Control Strip](docs/touchbar-spark.png)

The same numbers Claude Code's `/usage` shows: the 5-hour session limit, the
weekly limit, and any per-model weekly limit (Fable, today). The line takes the
app area of the Touch Bar; brightness and volume stay in the Control Strip. The
system ✕ can close it; it comes back on the next app switch, or tap ✦ in the
Control Strip.

It covers the Touch Bar's Esc, so it suits Macs with a physical Esc key (or an
external keyboard).

## Why not MTMR / BetterTouchTool?

MTMR does this kind of thing, but its last release isn't notarized, so current
macOS blocks it. BetterTouchTool is paid. A binary you compile yourself is never
quarantined, so Gatekeeper stays out of the way.

## Install

Needs a Touch Bar Mac, Xcode command line tools, Node, and Claude Code logged in
with a Claude subscription:

```sh
./install.sh      # builds, copies to ~/Applications, adds a login item
```

Uninstall: quit `CCUsageBar`, delete `~/Applications/CCUsageBar.app`, and remove it
from System Settings → General → Login Items.

## How it works

- `ccusage-line.sh` reads Claude Code's OAuth token from the Keychain and calls
  the usage endpoint Claude Code itself uses (`/api/oauth/usage`). That endpoint
  rate-limits hard, so the answer is cached in `~/Library/Caches/ccusagebar.json`,
  fetched at most every 5 minutes, and shown as `(stale)` if a fetch fails.
- `main.swift` presents a system-modal Touch Bar through the private
  `NSTouchBar presentSystemModalTouchBar:placement:systemTrayItemIdentifier:` and
  anchors it on a Control Strip item (`DFRElementSetControlStripPresenceForIdentifier`),
  the same private calls MTMR and Pock use. It re-presents itself on every app
  switch and refreshes every 5 minutes; tap the line to refresh now.
- It's an `LSUIElement` agent: no Dock icon, no menu bar.

Undocumented endpoint and private APIs: no App Store, and either could break.

The repo name is from v1, which showed [ccusage](https://github.com/ccusage/ccusage)
dollar cost.

## License

MIT

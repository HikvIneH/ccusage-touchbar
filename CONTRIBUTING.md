# Contributing

Small project, small rules. It is one Swift app (`main.swift` and the few files beside it) and
one shell script (`ccusage-line.sh`), with no dependencies beyond what the README
lists. Changes that keep it that way are the easiest to merge.

## Build and run

```sh
./build.sh                                        # builds CCUsageBar.app here
pkill -x CCUsageBar                               # only one copy can hold the Touch Bar
./CCUsageBar.app/Contents/MacOS/CCUsageBar        # run it in the foreground
./install.sh                                      # when done: reinstall to ~/Applications
```

To exercise a mode the Mac would not pick by itself, pass it as an argument
instead of writing a default:

```sh
./CCUsageBar.app/Contents/MacOS/CCUsageBar -mode notch      # or: touchbar
```

`./ccusage-line.sh` runs by itself and prints the two lines the app shows. The
usage endpoint rate-limits hard; the script caches for 5 minutes, so do not loop it
with the cache deleted.

## Checking a change

There is no test suite: what matters is what appears on the hardware. Before
opening a pull request, check what your change touches:

- Touch Bar: the line shows, survives an app switch, a tap opens the details, and
  brightness and volume are still in the Control Strip.
- Notch: the label sits either side of the notch, hovering drops the full line,
  a click opens the details (↻ refreshes, a click elsewhere closes), and it hides
  when the built-in display is off.
- Colours: amber at 75%, red at 90%; to see them without burning usage, edit the
  numbers in `~/Library/Caches/ccusagebar.json` (it is refetched after 5 minutes).
- `mode` unset shows only what the Mac has; `touchbar` and `notch` override it.
- A failed fetch shows the last numbers marked `(stale)`, not an empty line.

Say in the pull request which Mac you checked on. Most people have a Touch Bar or
a notch, not both; "only checked with `-mode notch` on a Mac without a notch" is a
fine thing to write, and better than leaving it out.

## Code

- Match the file you are in: short, comments that say why and not what.
- Public API where there is one. The Touch Bar side needs private calls; keep
  them optional (`dlsym(...).map`, `responds(to:)`) so a Mac without them does not
  crash.
- No new runtime dependencies, no network calls other than the usage endpoint.
- Update the README when behaviour changes.

## Commits

One change per commit. The subject says what the app now does, as a sentence
without a full stop, capitalised, 72 characters or fewer:

```
Show only what the Mac has, with a mode setting to choose
```

Add a body when the reason is not obvious from the diff: what was wrong, or why
this way and not the obvious other way. To get the template in your editor:

```sh
git config commit.template .gitmessage
```

## Pull requests and issues

Pull requests go to `main` and use the template. For bugs, the issue template asks
for the Mac model and macOS version, because almost every bug here is specific to
one or the other.

Never paste your Claude Code OAuth token, or the output of the `security` command
in `ccusage-line.sh`, into an issue or pull request.

#!/bin/zsh
# Lets the notch answer Claude Code's permission prompts, questions and plans: adds a
# PermissionRequest hook to ~/.claude/settings.json that runs `CCUsageBar --hook`.
#   ./install-hook.sh            add it (the old settings are kept as settings.json.bak-ccusagebar)
#   ./install-hook.sh remove     take it out again
# With the app not running the hook prints nothing and Claude Code asks in the terminal as usual.
set -e
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
settings=~/.claude/settings.json
[[ -e $settings ]] || print '{}' > $settings
cp $settings $settings.bak-ccusagebar
ACTION=${1:-add} APP=~/Applications/CCUsageBar.app/Contents/MacOS/CCUsageBar node -e '
const fs = require("fs"), file = process.argv[1];
const s = JSON.parse(fs.readFileSync(file, "utf8"));
const command = `"${process.env.APP}" --hook`;
const ours = e => e.hooks?.some(h => h.command?.includes("CCUsageBar") && h.command.includes("--hook"));
s.hooks ??= {};
const list = (s.hooks.PermissionRequest ?? []).filter(e => !ours(e));
// An hour to answer; past that Claude Code drops the hook and asks in the terminal.
if (process.env.ACTION !== "remove") list.push({ matcher: "*", hooks: [{ type: "command", command, timeout: 3600 }] });
if (list.length) s.hooks.PermissionRequest = list; else delete s.hooks.PermissionRequest;
if (!Object.keys(s.hooks).length) delete s.hooks;
fs.writeFileSync(file + ".tmp", JSON.stringify(s, null, 2) + "\n");
fs.renameSync(file + ".tmp", file);
' $settings
[[ ${1:-add} == remove ]] && echo "hook removed from $settings" || echo "hook added to $settings; new Claude Code sessions pick it up"

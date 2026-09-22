#!/bin/zsh
# Claude plan limits for the Touch Bar (bundled into CCUsageBar.app).
# Prints two lines: the Control Strip label, then the tap-to-expand line.
#   5h 41% · wk 11% · F 14%
#   5h 41% · 23:10  │  week 11% · Mon 06:00  │  Fable 14%
# Same numbers as Claude Code's /usage, read with Claude Code's own login.
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
# The usage API rate-limits hard (429 for ~5 min), so: fetch at most every 5 min,
# and fall back to the last good answer, marked stale, when a fetch fails.
cache=~/Library/Caches/ccusagebar.json
if [[ ! -e $cache || -n $(find $cache -mmin +5) ]]; then
  tok=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null |
    node -e 'try { console.log(JSON.parse(require("fs").readFileSync(0, "utf8")).claudeAiOauth.accessToken ?? "") } catch {}')
  # The token goes in on stdin (-H @-): as an argument, ps would show it to any process.
  # No token (signed out, or the Keychain said no): nothing to send, so show stale.
  [[ -n $tok ]] && fresh=$(print -r -- "Authorization: Bearer $tok" | curl -sf -m 10 -H @- \
    -H "anthropic-beta: oauth-2025-04-20" https://api.anthropic.com/api/oauth/usage)
  if [[ -n $fresh ]]; then print -r -- $fresh > $cache; else stale=1; touch $cache 2>/dev/null; fi
fi
STALE=$stale node -e '
let u; try { u = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")) } catch {}
const mark = process.env.STALE ? " (stale)" : "";
// "limits" lists the session, the weekly, and any per-model weekly limits (e.g. Fable).
const limits = (u?.limits ?? []).map(l => ({
  short: l.kind === "session" ? "5h" : l.kind === "weekly_all" ? "wk" : (l.scope?.model?.display_name ?? "?")[0],
  long: l.kind === "session" ? "5h" : l.kind === "weekly_all" ? "week" : l.scope?.model?.display_name ?? "?",
  pct: `${Math.round(l.percent)}%`,
  resets: l.resets_at && new Date(l.resets_at).toLocaleString("en-GB", l.kind === "session"
    ? { hour: "2-digit", minute: "2-digit" } : { weekday: "short", hour: "2-digit", minute: "2-digit" }),
}));
if (!limits.length) { console.log("5h ? · wk ?\nLimits unavailable — retrying in a few minutes"); process.exit() }
console.log(limits.map(l => `${l.short} ${l.pct}`).join(" · ") + mark);
// Keep it short: the Touch Bar drops an item that does not fit rather than truncating it.
const weekly = limits.find(l => l.long === "week")?.resets;
console.log(limits.map(l => `${l.long} ${l.pct}` + (l.resets && (l.long === "week" || l.resets !== weekly) ? ` · ${l.resets}` : "")).join("  │  ") + mark);
' $cache

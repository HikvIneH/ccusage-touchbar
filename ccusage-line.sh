#!/bin/zsh
# Claude plan limits for the Touch Bar (bundled into CCUsageBar.app).
# Prints three lines: the short label, the full line, then JSON the app draws from.
#   5h 41% · wk 11% · F 14%
#   5h 41% · 23:10  │  week 11% · Mon 06:00  │  Fable 14%
#   {"stale":false,"fetched":1790343796,"rows":[{"title":"5-hour","pct":41,"level":0,…},…]}
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
const fs = require("fs");
let u; try { u = JSON.parse(fs.readFileSync(process.argv[1], "utf8")) } catch {}
const stale = !!process.env.STALE, mark = stale ? " (stale)" : "";
// 0 fine, 1 getting close, 2 nearly out: whichever of the API severity and the percent says more.
const level = (pct, sev) => Math.max(pct >= 90 ? 2 : pct >= 75 ? 1 : 0,
  !sev || sev === "normal" ? 0 : /crit|high|exceed|block|reached/.test(sev) ? 2 : 1);
// Reset times jitter by a fraction of a second between fetches (17:29:59.9, 17:30:00.3):
// the nearest minute is what names a window, and what to show.
const minute = at => at ? Math.round(Date.parse(at) / 60000) * 60 : null;
const time = (at, weekday) => at && new Date(minute(at) * 1000).toLocaleString("en-GB",
  weekday ? { weekday: "short", hour: "2-digit", minute: "2-digit" } : { hour: "2-digit", minute: "2-digit" });
const money = n => "$" + (Number.isInteger(n) ? n : n.toFixed(2));
const amount = a => typeof a === "number" ? a : a?.amount_minor != null ? a.amount_minor / 10 ** (a.exponent ?? 2) : null;

// "limits" lists the session, the weekly, and any per-model weekly limits (e.g. Fable).
const limits = (u?.limits ?? []).map(l => {
  const model = l.scope?.model?.display_name ?? "?", pct = Math.round(l.percent);
  const name = l.kind === "session" ? "5h" : l.kind === "weekly_all" ? "week" : model;
  return { title: l.kind === "session" ? "5-hour" : l.kind === "weekly_all" ? "Weekly" : `${model} weekly`,
    short: `${l.kind === "session" ? "5h" : l.kind === "weekly_all" ? "wk" : model[0]} ${pct}%`, name, pct,
    level: level(l.percent, l.severity), resetsAt: minute(l.resets_at),
    resets: time(l.resets_at, l.kind !== "session"), inLine: true };
});
if (!limits.length) {
  console.log("5h ? · wk ?\nLimits unavailable — retrying in a few minutes");
  console.log(JSON.stringify({ stale: true, fetched: 0, rows: [] }));
  process.exit();
}
// Keep it short: the Touch Bar drops an item that does not fit rather than truncating it.
const weekly = limits.find(l => l.name === "week")?.resets;
for (const l of limits) {
  l.long = `${l.name} ${l.pct}%` + (l.resets && (l.name === "week" || l.resets !== weekly) ? ` · ${l.resets}` : "");
  l.sub = l.resets ? `resets ${l.resets}` : "";
}

// Paid usage past the plan: in the line only while it is on (credits: while being spent).
const extras = [];
if (u?.spend?.enabled) {
  const used = amount(u.spend.used) ?? 0, cap = amount(u.spend.limit ?? u.spend.cap), pct = Math.round(u.spend.percent ?? 0);
  extras.push({ title: "Extra usage", short: money(used), long: `extra ${money(used)}` + (cap ? ` of ${money(cap)}` : ""),
    sub: cap ? `${money(used)} of ${money(cap)}` : `${money(used)} spent`, pct, level: level(pct, u.spend.severity), inLine: true });
} else if (u?.extra_usage?.is_enabled) {
  const pct = Math.round(u.extra_usage.utilization ?? 0);
  extras.push({ title: "Extra usage", short: `+${pct}%`, long: `extra ${pct}%`, sub: "this month", pct,
    level: level(pct, u.extra_usage.spend_limit_reached ? "reached" : null), inLine: true });
}
// Credit grants come under changing field names; what they share is a dollar limit.
for (const c of Object.values(u ?? {}).filter(v => v?.limit_dollars != null)) {
  const used = c.used_dollars ?? 0, pct = Math.round(c.utilization ?? 100 * used / c.limit_dollars);
  const until = c.resets_at ? ` · until ${new Date(c.resets_at).toLocaleDateString("en-GB", { day: "numeric", month: "short" })}` : "";
  extras.push({ title: "Credits", short: money(used), long: `credits ${money(used)} of ${money(c.limit_dollars)}`,
    sub: `${money(used)} of ${money(c.limit_dollars)}${until}`, pct, level: level(pct, c.locked_reason ? "blocked" : null),
    inLine: used > 0 });
}

const rows = [...limits, ...extras], line = rows.filter(r => r.inLine);
console.log(line.map(r => r.short).join(" · ") + mark);
console.log(line.map(r => r.long).join("  │  ") + mark);
console.log(JSON.stringify({ stale, fetched: Math.round(fs.statSync(process.argv[1]).mtimeMs / 1000),
  rows: rows.map(({ name, resets, ...r }) => r) }));
' $cache

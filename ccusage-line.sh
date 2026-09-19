#!/bin/zsh
# One-line Claude Code spend for the Touch Bar (bundled into CCUsageBar.app).
# e.g. "✦ $127 today · $51 block · 2h14m"
export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin
cd /tmp
today=$(date +%Y%m%d)
{ ccusage daily --json --since $today --offline 2>/dev/null; echo '@@'; ccusage blocks --active --json --offline 2>/dev/null; } | node -e '
let [d, b] = require("fs").readFileSync(0, "utf8").split("@@");
const j = s => { try { return JSON.parse(s) } catch { return null } };
d = j(d); b = j(b);
const cost = d?.totals?.totalCost ?? 0;
let out = `✦ $${cost.toFixed(0)} today`;
const blk = b?.blocks?.[0];
if (blk) {
  const m = blk.projection?.remainingMinutes ?? Math.max(0, Math.round((new Date(blk.endTime) - Date.now()) / 60000));
  out += ` · $${blk.costUSD.toFixed(0)} block · ${Math.floor(m / 60)}h${String(m % 60).padStart(2, "0")}m`;
}
console.log(out);
'

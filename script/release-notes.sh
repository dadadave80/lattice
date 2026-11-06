#!/usr/bin/env bash
# Compare frozen identities offline; '-' denotes the first canonical manifest.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$#" = 2 ] || { echo 'usage: release-notes.sh <previous.json|-> <current.json>' >&2; exit 1; }
previous=$1 current=$2
./script/release/validate-manifest.sh "$current"
if [ "$previous" != - ]; then ./script/release/validate-manifest.sh "$previous"; fi
jq -nr --slurpfile current "$current" \
    --slurpfile previous "$([ "$previous" = - ] && printf /dev/null || printf '%s' "$previous")" '
  def display: @html | gsub("`"; "&#96;") | gsub("[\r\n]"; " ");
  def id: .kind+"/"+.name;
  def selectors: .selectors | ascii_downcase | .[2:] | [scan(".{8}") | "0x"+.] | sort;
  def codes: map("`"+.+"`") | join(", ");
  ($current[0]) as $new | ($previous[0] // {contracts:[]}) as $old |
  ($old.contracts | map({key:id,value:.}) | from_entries) as $before |
  ($new.contracts | map({key:id,value:.}) | from_entries) as $after |
  [($before+$after | keys[]) as $id | $before[$id] as $a | $after[$id] as $b |
    if $a==null then "- Added <code>\($b.name|display)</code> (\($b.kind)): `\($b.address)`; runtime `\($b.codehash)`." +
      (if $b.kind=="facet" then "\n  - Added selectors: \($b|selectors|codes)." else "" end)
    elif $b==null then "- Removed <code>\($a.name|display)</code> (\($a.kind)): `\($a.address)`." +
      (if $a.kind=="facet" then "\n  - Removed selectors: \($a|selectors|codes)." else "" end)
    else [
      if $a.codehash!=$b.codehash then "  - Runtime codehash: `\($a.codehash)` → `\($b.codehash)`." else empty end,
      if $a.initCodeHash!=$b.initCodeHash then "  - Creation hash: `\($a.initCodeHash)` → `\($b.initCodeHash)`." else empty end,
      if ($a.address|ascii_downcase)!=($b.address|ascii_downcase) then "  - Address: `\($a.address)` → `\($b.address)`." else empty end,
      (($b|selectors)-($a|selectors)) as $added |
      (($a|selectors)-($b|selectors)) as $removed |
      if ($added|length)>0 then "  - Added selectors: \($added|codes)." else empty end,
      if ($removed|length)>0 then "  - Removed selectors: \($removed|codes)." else empty end,
      if $a.selectorsHash!=$b.selectorsHash and ($added|length)==0 and ($removed|length)==0
        then "  - Selector order changed; selector set unchanged." else empty end
    ] as $changes |
    if ($changes|length)>0 then "- Changed <code>\($b.name|display)</code> (\($b.kind)):\n\($changes|join("\n"))" else empty end end
  ] as $changes |
  "## Shared contract changes\n",
  (if ($previous|length)==0 then "First canonical manifest: \($new.lattice.version)."
   else "\($old.lattice.version) → \($new.lattice.version)." end),
  "Source: `\($new.lattice.commit)`. Comparison covers frozen identities; it does not assert an upgrade is safe.\n",
  (if ($changes|length)==0 then "No shared contract identities or selector sets changed." else $changes|join("\n") end)
'

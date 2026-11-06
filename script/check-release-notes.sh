#!/usr/bin/env bash
# Render the newest committed canonical manifest, or an explicit published tag.
set -euo pipefail
cd "$(dirname "$0")/.."
[ "$#" -ge 1 ] && [ "$#" -le 2 ] || { echo 'usage: check-release-notes.sh <destination.md> [tag]' >&2; exit 1; }
destination=$1 tag=${2:-}
manifests=()
while IFS= read -r file; do
    jq -e -s 'length==1 and (.[0]|type=="object")' "$file" >/dev/null
    jq -e 'has("chain")|not' "$file" >/dev/null || continue
    ./script/release/validate-manifest.sh "$file"
    jq -e '.publication=="release"' "$file" >/dev/null
    manifests+=("$file")
done < <(find deployments -type f -name 'release-*.json' | sort)
if [ "${#manifests[@]}" = 0 ]; then
    [ -z "$tag" ] || { echo 'release notes: requested canonical manifest missing' >&2; exit 1; }
    printf '## Shared contract changes\n\nNo canonical release manifest is committed yet.\n' > "$destination"
    exit 0
fi
ordered=$(for file in "${manifests[@]}"; do
    jq -c --arg file "$file" '{file:$file,version:(.lattice.version|split(".")|map(tonumber)),tag:.lattice.tag}' "$file"
    done |
    jq -s 'sort_by(.version)')
jq -e 'length==([.[].version]|unique|length)' <<< "$ordered" >/dev/null || { echo 'release notes: duplicate canonical versions' >&2; exit 1; }
current=$(jq -r --arg tag "$tag" 'if $tag=="" then .[-1].file else [.[]|select(.tag==$tag)] | if length==1 then .[0].file else error("requested tag missing or ambiguous") end end' <<< "$ordered")
previous=$(jq -r --arg current "$current" 'map(.file) | index($current) as $i | if $i==0 then "-" else .[$i-1] end' <<< "$ordered")
./script/release-notes.sh "$previous" "$current" > "$destination"

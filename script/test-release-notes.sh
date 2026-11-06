#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
temporary=$(mktemp -d "${TMPDIR:-/tmp}/lattice-release-notes.XXXXXX")
trap 'rm -rf "$temporary"' EXIT
baseline=test/fixtures/release-manifests/release.json
./script/release-notes.sh "$baseline" "$baseline" > "$temporary/same.md"
grep -q 'No shared contract identities or selector sets changed.' "$temporary/same.md"
jq '.lattice.version="99.0.1" | .lattice.tag="fixture/notes" |
    .contracts[2].codehash=("0x"+("1"*64)) |
    .contracts[2].selectors="0xd3948fec00000001"' "$baseline" > "$temporary/new.json"
# Version-derived salts/addresses must remain internally valid in fixture manifests.
while IFS= read -r name; do
    salt=$(cast keccak "lattice.$name.99.0.1")
    init_hash=$(jq -r --arg name "$name" '.contracts[] | select(.name==$name) | .initCodeHash' "$temporary/new.json")
    digest=$(cast keccak "0xff4e59b44847b379578588920ca78fbf26c0b4956c${salt#0x}${init_hash#0x}")
    jq --arg name "$name" --arg salt "$salt" --arg at "0x${digest:26}" \
        '(.contracts[] | select(.name==$name)) |= (.salt=$salt | .address=$at)' "$temporary/new.json" > "$temporary/next.json"
    mv "$temporary/next.json" "$temporary/new.json"
done < <(jq -r '.contracts[] | select(.kind=="facet" or .kind=="init") | .name' "$baseline")
hash=$(cast keccak 0xd3948fec00000001)
jq --arg hash "$hash" '.contracts[2].selectorsHash=$hash | del(.contracts[3])' "$temporary/new.json" > "$temporary/next.json"
mv "$temporary/next.json" "$temporary/new.json"
./script/release-notes.sh "$baseline" "$temporary/new.json" > "$temporary/changed.md"
grep -q 'Changed.*AcrossBridgeAdapter' "$temporary/changed.md"
grep -q 'Runtime codehash:' "$temporary/changed.md"
grep -q 'Added selectors:.*0x00000001' "$temporary/changed.md"
grep -q 'Removed selectors:.*0x3a5be8cb.*0xafdac3d6' "$temporary/changed.md"
grep -q 'Removed.*API3AdapterInit' "$temporary/changed.md"
./script/release-notes.sh "$temporary/new.json" "$baseline" > "$temporary/reverse.md"
grep -q 'Added.*API3AdapterInit' "$temporary/reverse.md"
./script/release-notes.sh - "$baseline" > "$temporary/first.md"
grep -q 'First canonical manifest' "$temporary/first.md"
[ "$(grep -c '^- Added ' "$temporary/first.md")" = 5 ]
jq '.contracts[4].name="[click](https://example.invalid)_*"' "$baseline" > "$temporary/markdown-name.json"
./script/release-notes.sh - "$temporary/markdown-name.json" > "$temporary/markdown-name.md"
grep -Fq '&#91;click&#93;&#40;https:&#47;&#47;example.invalid&#41;&#95;&#42;' "$temporary/markdown-name.md"
if grep -Fq '[click]' "$temporary/markdown-name.md"; then
    echo 'release notes rendered an untrusted Markdown link' >&2; exit 1
fi
# Registry/factory order is part of the native schema; reorder only the remaining catalog.
jq '.contracts = (.contracts[0:2] + (.contracts[2:] | reverse))' "$temporary/new.json" > "$temporary/reordered.json"
./script/release-notes.sh "$baseline" "$temporary/reordered.json" > "$temporary/reordered.md"
cmp "$temporary/changed.md" "$temporary/reordered.md"
hash=$(cast keccak 0xafdac3d63a5be8cbd3948fec)
jq --arg hash "$hash" '.contracts[2].selectors="0xafdac3d63a5be8cbd3948fec" | .contracts[2].selectorsHash=$hash' "$baseline" > "$temporary/selector-order.json"
./script/release-notes.sh "$baseline" "$temporary/selector-order.json" > "$temporary/selector-order.md"
grep -q 'Selector order changed; selector set unchanged.' "$temporary/selector-order.md"
if grep -q 'Added selectors:\|Removed selectors:' "$temporary/selector-order.md"; then
    echo 'release notes confuse export order with selector membership' >&2; exit 1
fi
for mutation in '.contracts[2].selectors="0x01"' '.contracts[2].selectors="0xd3948fecd3948fec"' '.contracts[2].selectorsHash=("0x"+("1"*64))'; do
    jq "$mutation" "$baseline" > "$temporary/invalid.json"
    if ./script/release-notes.sh "$baseline" "$temporary/invalid.json" > /dev/null 2>&1; then
        echo "release notes accepted invalid selector commitment: $mutation" >&2; exit 1
    fi
done
hash=$(cast keccak 0xd3948fecD3948FEC)
jq --arg hash "$hash" '.contracts[2].selectors="0xd3948fecD3948FEC" | .contracts[2].selectorsHash=$hash' "$baseline" > "$temporary/mixed-duplicate.json"
if ./script/release-notes.sh "$baseline" "$temporary/mixed-duplicate.json" > /dev/null 2>&1; then
    echo 'release notes accepted mixed-case duplicate selectors with a matching commitment' >&2; exit 1
fi
selection=$temporary/selection
mkdir -p "$selection/script/release" "$selection/deployments/schema"
cp script/release-notes.sh script/check-release-notes.sh "$selection/script/"
cp script/release/validate-manifest.sh script/release/validate-schema.jq "$selection/script/release/"
cp deployments/schema/release.schema.json "$selection/deployments/schema/"
jq '.publication="release" | .lattice.tag="v99.0.0"' "$baseline" > "$selection/deployments/release-z.json"
jq '.publication="release" | .lattice.tag="v99.0.1"' "$temporary/new.json" > "$selection/deployments/release-a.json"
bash "$selection/script/check-release-notes.sh" "$temporary/selected.md"
cmp "$temporary/changed.md" "$temporary/selected.md"
bash "$selection/script/check-release-notes.sh" "$temporary/tagged.md" v99.0.0
cmp "$temporary/first.md" "$temporary/tagged.md"
if bash "$selection/script/check-release-notes.sh" "$temporary/missing.md" v99.0.2 > /dev/null 2>&1; then
    echo 'release notes accepted missing requested tag' >&2; exit 1
fi
cp "$selection/deployments/release-a.json" "$selection/deployments/release-duplicate.json"
if bash "$selection/script/check-release-notes.sh" "$temporary/duplicate.md" > /dev/null 2>&1; then
    echo 'release notes accepted duplicate versions' >&2; exit 1
fi
jq -n '{body:"Release Please changelog"}' |
    jq -r --arg notes 'first comparison' -f script/release/append-notes.jq > "$temporary/body.txt"
jq -n --rawfile body "$temporary/body.txt" '{body:($body+"Maintainer trailing notes")}' |
    jq -r --arg notes 'updated comparison' -f script/release/append-notes.jq > "$temporary/updated-body.txt"
grep -q 'Release Please changelog' "$temporary/updated-body.txt"
grep -q 'Maintainer trailing notes' "$temporary/updated-body.txt"
grep -q 'updated comparison' "$temporary/updated-body.txt"
if grep -q 'first comparison' "$temporary/updated-body.txt"; then exit 1; fi
if jq -n '{body:"<!-- lattice-shared-contracts:start -->"}' |
    jq -r --arg notes text -f script/release/append-notes.jq > /dev/null 2>&1; then
    echo 'release notes accepted an incomplete generated block' >&2; exit 1
fi
echo 'release notes: identity/selector changes, first release, ordering and invalid commitments passed'

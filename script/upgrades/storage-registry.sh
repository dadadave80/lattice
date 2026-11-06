#!/usr/bin/env bash
# JSON twin of the normalized, source-checked storage-layout baseline. Run through
# make storage-check / storage-update so the Solidity layout is checked first.
set -euo pipefail

MODE="${1:---check}"
ROOT="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
[[ "${MODE}" == --check || "${MODE}" == --update ]] || { echo "Usage: $0 [--check|--update] [root]" >&2; exit 2; }
BASELINE="${ROOT}/script/upgrades/storage-layout.baseline"
REGISTRY="${ROOT}/script/upgrades/storage-registry.json"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
command -v cast >/dev/null || { echo 'storage-registry: cast is required (use the shared Foundry release).' >&2; exit 2; }

jq -Rn '
    reduce inputs as $line ([];
        if $line == "" then .
        elif $line | startswith("### ") then
            if $line | test("^### [A-Za-z0-9_]+ @ erc7201:[A-Za-z0-9._]+ \\(slot 0x[0-9a-f]{64}\\)$") then
                ($line | capture("^### (?<struct>[^ ]+) @ erc7201:(?<namespace>[^ ]+) \\(slot (?<slot>[^)]+)\\)$")) as $head
                | . + [$head + {fields: []}]
            elif $line | test("^### [A-Za-z0-9_]+ \\(nested\\)$") then
                . + [($line | capture("^### (?<struct>[^ ]+) \\(nested\\)$")) + {namespace: null, slot: null, fields: []}]
            else error("Invalid storage-layout header: " + $line) end
        else
            ($line | split("\t")) as $row
            | if length == 0 or ($row | length) != 4
                or ($row[0] | test("^[0-9]+$") | not)
                or ($row[1] | test("^[0-9]+$") | not)
                or ($row[1] | tonumber) > 31
                or ($row[2] | test("^[A-Za-z_$][A-Za-z0-9_$]*$") | not)
                or $row[3] == "" then error("Invalid storage-layout field: " + $line)
              else .[-1].fields += [{slot: $row[0], offset: ($row[1] | tonumber), name: $row[2], type: $row[3]}] end
        end
    )
    | if length == 0 or any(.[]; (.fields | length) == 0)
        or ([.[].struct] | length != (unique | length))
        or ([.[] | select(.namespace != null) | .namespace] | length == 0 or length != (unique | length))
        or ([.[] | select(.slot != null) | .slot] | length != (unique | length))
      then error("Empty or duplicate storage-layout sections")
      else {schemaVersion: 1, layouts: .} end
' <"${BASELINE}" >"${TMP}/registry.json"

while IFS=$'\t' read -r namespace slot; do
    awk -v namespace="${namespace}" -v slot="${slot}" '
        /^\|/ && index($0, "`" namespace "`") && index($0, "`" slot "`") { found = 1 }
        END { exit !found }
    ' "${ROOT}/STORAGE_REGISTRY.md" || {
        echo "Storage registry row missing or incorrect: ${namespace} ${slot}" >&2
        exit 1
    }
done < <(jq -r '.layouts[] | select(.namespace != null) | [.namespace, .slot] | @tsv' "${TMP}/registry.json")

# Read each declaration with its adjacent NatSpec or existing inline interface ID.
# Unknown formats fail closed so a new constant cannot silently disappear from the export.
while IFS= read -r source; do
    jq -Rs --arg source "${source#"${ROOT}/"}" '{source: $source, text: .}' "${source}"
done < <(find "${ROOT}/src" -name '*.sol' -type f -exec grep -l 'ERC165_MAP_' {} +) >"${TMP}/sources.json"

jq -s '
    def matches($pattern): [match($pattern; "g") | .captures | map({key: .name, value: .string}) | from_entries];
    [.[] |
        .source as $source |
        (.text | matches("(?:^|\\n)[ \t]*[A-Za-z0-9_]+\\s+(?:(?:internal|private|public)\\s+)?constant\\s+(?<constant>ERC165_MAP_[A-Z0-9_]+)")) as $declared |
        [.text | splits("\n[ \t\r]*\n") |
            . as $block |
            matches("(?:^|\\n)[ \t]*bytes32\\s+constant\\s+(?<constant>ERC165_MAP_[A-Z0-9_]+)\\s*=\\s*(?<slot>0x[0-9a-fA-F]{64})\\s*;(?<inline>[^\n]*)")[] |
            . as $constant |
            ([$constant.inline | scan("0x[0-9a-fA-F]{8}(?![0-9a-fA-F])")] +
                [$block | scan("bytes4\\(\\s*(0x[0-9a-fA-F]{8})\\s*\\)") | .[0]] +
                [$block | matches("(?<interface>[A-Za-z_][A-Za-z0-9_]*)\\s*=\\s*(?<id>0x[0-9a-fA-F]{8})(?![0-9a-fA-F])")[] |
                    select(("ERC165_MAP_" + (.interface | ascii_upcase) + "_SLOT") == $constant.constant) | .id]
                | map(ascii_downcase) | unique) as $ids |
            if ($ids | length) != 1 then error("Unrecognized ERC-165 interface ID: " + $source + ":" + .constant)
            else {interfaceId: $ids[0], slot: (.slot | ascii_downcase), source: $source, constant: .constant} end
        ] as $parsed |
        if ($declared | length) != ($parsed | length) then error("Unrecognized ERC-165 constant: " + $source)
        else $parsed[] end
    ] |
    group_by(.interfaceId) |
    map(if (map(.slot) | unique | length) != 1 then error("Conflicting ERC-165 map slots: " + .[0].interfaceId)
        else {interfaceId: .[0].interfaceId, slot: .[0].slot, sources: (map({source, constant}) | sort_by(.source, .constant))} end) |
    if length == 0 or (map(.slot) | length != (unique | length)) then error("Empty or colliding ERC-165 map slots") else . end
' "${TMP}/sources.json" >"${TMP}/interfaces.json"

ERC165_ROOT="$(cast index-erc7201 diamond.lib.storage.ERC165)"
while IFS=$'\t' read -r interface_id slot; do
    expected="$(cast keccak "$(cast abi-encode 'f(bytes4,bytes32)' "${interface_id}" "${ERC165_ROOT}")")"
    [[ "${slot}" == "${expected}" ]] || { echo "Incorrect ERC-165 map derivation: ${interface_id} ${slot}" >&2; exit 1; }
done < <(jq -r '.[] | [.interfaceId, .slot] | @tsv' "${TMP}/interfaces.json")

# Rows may advertise canonical IDs, several shared IDs, or no ID. Stateless extension
# omissions are intentional; every pair that the table does advertise must match source.
awk -F '|' '/^\|/ { if (NF != 8) { print "Malformed storage registry table row: " $0 > "/dev/stderr"; exit 1 }; print $2 "\t" $6 "\t" $7 }' "${ROOT}/STORAGE_REGISTRY.md" |
jq -Rn --slurpfile interfaces "${TMP}/interfaces.json" '
    inputs | split("\t") as $row |
    [$row[1] | scan("0x[0-9A-Za-z]+") | ascii_downcase] as $ids |
    [$row[2] | scan("0x[0-9A-Za-z]+") | ascii_downcase] as $slots |
    if $ids == ["0x00000000"] and $slots == [] then empty
    elif ($ids | length) != ($slots | length) then error("Incomplete ERC-165 table row: " + $row[0])
    else range(0; $ids | length) as $i |
        if any($interfaces[0][]; .interfaceId == $ids[$i] and .slot == $slots[$i]) then empty
        else error("Incorrect ERC-165 table row: " + $row[0] + " " + $ids[$i] + " " + $slots[$i]) end
    end
' >/dev/null

jq --slurpfile interfaces "${TMP}/interfaces.json" '.interfaces = $interfaces[0]' "${TMP}/registry.json" >"${TMP}/complete.json"
if [[ "${MODE}" == --update ]]; then
    cp "${TMP}/complete.json" "${REGISTRY}"
elif ! cmp -s "${TMP}/complete.json" "${REGISTRY}"; then
    echo "Storage registry drift: run make storage-update and review the layout/JSON diff." >&2
    diff -u "${REGISTRY}" "${TMP}/complete.json" >&2 || true
    exit 1
fi

#!/usr/bin/env bash
# JSON twin of the normalized, source-checked storage-layout baseline. Run through
# make storage-check / storage-update so the Solidity layout is checked first.
set -euo pipefail

MODE="${1:---check}"
ROOT="${2:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
[[ "${MODE}" == --check || "${MODE}" == --update ]] || { echo "Usage: $0 [--check|--update] [root]" >&2; exit 2; }
BASELINE="${ROOT}/script/upgrades/storage-layout.baseline"
REGISTRY="${ROOT}/script/upgrades/storage-registry.json"
TMP="$(mktemp)"
trap 'rm -f "${TMP}"' EXIT

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
' <"${BASELINE}" >"${TMP}"

while IFS=$'\t' read -r namespace slot; do
    awk -v namespace="${namespace}" -v slot="${slot}" '
        /^\|/ && index($0, "`" namespace "`") && index($0, "`" slot "`") { found = 1 }
        END { exit !found }
    ' "${ROOT}/STORAGE_REGISTRY.md" || {
        echo "Storage registry row missing or incorrect: ${namespace} ${slot}" >&2
        exit 1
    }
done < <(jq -r '.layouts[] | select(.namespace != null) | [.namespace, .slot] | @tsv' "${TMP}")

if [[ "${MODE}" == --update ]]; then
    cp "${TMP}" "${REGISTRY}"
elif ! cmp -s "${TMP}" "${REGISTRY}"; then
    echo "Storage registry drift: run make storage-update and review the layout/JSON diff." >&2
    diff -u "${REGISTRY}" "${TMP}" >&2 || true
    exit 1
fi

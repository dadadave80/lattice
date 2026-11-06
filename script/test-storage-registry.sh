#!/usr/bin/env bash
set -euo pipefail

CHECK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/upgrades/storage-registry.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
mkdir -p "${TMP}/script/upgrades"
BASELINE="${TMP}/script/upgrades/storage-layout.baseline"
REGISTRY="${TMP}/script/upgrades/storage-registry.json"
cat >"${TMP}/valid" <<'EOF'
### ExampleStorage @ erc7201:lattice.storage.Example (slot 0x0000000000000000000000000000000000000000000000000000000000000100)
0	0	_owner	t_address
1	0	_nested	t_struct(Nested)_storage

### Nested (nested)
0	0	value	t_uint256
EOF
cp "${TMP}/valid" "${BASELINE}"
printf '| Example | `lattice.storage.Example` | `0x0000000000000000000000000000000000000000000000000000000000000100` |\n' >"${TMP}/STORAGE_REGISTRY.md"
"${CHECK}" --update "${TMP}"
"${CHECK}" --check "${TMP}"
jq -e '.schemaVersion == 1 and (.layouts | length) == 2 and .layouts[0].namespace == "lattice.storage.Example" and .layouts[1].namespace == null and .layouts[0].fields[1].name == "_nested"' "${REGISTRY}" >/dev/null

expect_failure() {
    if "${CHECK}" --update "${TMP}" >"${TMP}/out" 2>"${TMP}/err"; then
        echo "FAIL: accepted $1" >&2
        exit 1
    fi
}
printf '\n' >"${BASELINE}"
expect_failure "empty baseline"
sed 's/slot 0x/slot 0z/' "${TMP}/valid" >"${BASELINE}"
expect_failure "invalid namespace slot"
awk -F '\t' 'BEGIN { OFS="\t" } $3 == "_owner" { $2=32 } { print }' "${TMP}/valid" >"${BASELINE}"
expect_failure "out-of-range offset"
printf '0\t0\torphan\tt_uint256\n' >"${BASELINE}"
expect_failure "field without section"
cat "${TMP}/valid" "${TMP}/valid" >"${BASELINE}"
expect_failure "duplicate sections"
cp "${TMP}/valid" "${BASELINE}"
"${CHECK}" --update "${TMP}"
cp "${TMP}/STORAGE_REGISTRY.md" "${TMP}/valid-table"
printf '| Example | `lattice.storage.Example` | `0x00` |\n' >"${TMP}/STORAGE_REGISTRY.md"
expect_failure "incorrect Markdown namespace row"
cp "${TMP}/valid-table" "${TMP}/STORAGE_REGISTRY.md"
printf '{}\n' >"${REGISTRY}"
if "${CHECK}" --check "${TMP}" >/dev/null 2>&1; then
    echo 'FAIL: accepted committed JSON drift' >&2
    exit 1
fi
echo 'Storage registry export and mutation fixtures passed.'

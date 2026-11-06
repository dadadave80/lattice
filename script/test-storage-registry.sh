#!/usr/bin/env bash
set -euo pipefail

CHECK="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/upgrades/storage-registry.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
mkdir -p "${TMP}/script/upgrades" "${TMP}/src"
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
cat >"${TMP}/source" <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
/// @dev `keccak256(abi.encode(bytes4(0xf5187bdc), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ICCTPBRIDGEADAPTER_SLOT =
    0x04cddf593d633f3c8537926f8f726adaafc298a0f78a2bfd4848abb0191103e1;

/// @custom:storage-location erc7201:lattice.storage.Example
struct ExampleStorage { address owner; }
EOF
cp "${TMP}/source" "${TMP}/src/ExampleLib.sol"
cat >"${TMP}/STORAGE_REGISTRY.md" <<'EOF'
| Example | `lattice.storage.Example` | `0x0000000000000000000000000000000000000000000000000000000000000100` | `ICCTPBridgeAdapter` | `0xf5187bdc` | `0x04cddf593d633f3c8537926f8f726adaafc298a0f78a2bfd4848abb0191103e1` |
EOF
"${CHECK}" --update "${TMP}"
"${CHECK}" --check "${TMP}"
jq -e '.schemaVersion == 1 and (.layouts | length) == 2 and .layouts[0].namespace == "lattice.storage.Example" and .layouts[1].namespace == null and .layouts[0].fields[1].name == "_nested" and (.interfaces | length) == 1 and .interfaces[0].interfaceId == "0xf5187bdc" and .interfaces[0].sources[0].source == "src/ExampleLib.sol"' "${REGISTRY}" >/dev/null

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
cat >"${TMP}/STORAGE_REGISTRY.md" <<'EOF'
| Example | `lattice.storage.Example` | `0x00` |
EOF
expect_failure "incorrect Markdown namespace row"
cp "${TMP}/valid-table" "${TMP}/STORAGE_REGISTRY.md"
sed 's/0xf5187bdc/0x9868b584/' "${TMP}/valid-table" >"${TMP}/STORAGE_REGISTRY.md"
expect_failure "stale CCTP interface ID"
sed 's/0x04cddf593d633f3c8537926f8f726adaafc298a0f78a2bfd4848abb0191103e1/0xc99af2d75b4d69e472159c90d5028834f8137d465c0aaebc7a1ffe39b3c97dee/' "${TMP}/valid-table" >"${TMP}/STORAGE_REGISTRY.md"
expect_failure "stale CCTP map slot"
cp "${TMP}/valid-table" "${TMP}/STORAGE_REGISTRY.md"
sed 's/|$/| extra |/' "${TMP}/valid-table" >"${TMP}/STORAGE_REGISTRY.md"
expect_failure "malformed table row"
cp "${TMP}/valid-table" "${TMP}/STORAGE_REGISTRY.md"
sed 's/0xf5187bdc/0x9868b584/' "${TMP}/source" >"${TMP}/src/ExampleLib.sol"
expect_failure "incorrect source map derivation"
sed '/bytes4(0xf5187bdc)/d' "${TMP}/source" >"${TMP}/src/ExampleLib.sol"
expect_failure "missing source interface ID"
sed 's/bytes32 constant/bytes32 internal constant/' "${TMP}/source" >"${TMP}/src/ExampleLib.sol"
expect_failure "unrecognized constant declaration"
sed 's/0x04cddf593d633f3c8537926f8f726adaafc298a0f78a2bfd4848abb0191103e1/bytes32(uint256(1))/' "${TMP}/source" >"${TMP}/src/ExampleLib.sol"
expect_failure "nonliteral map slot"
cp "${TMP}/source" "${TMP}/src/ExampleLib.sol"
cp "${TMP}/source" "${TMP}/src/SharedLib.sol"
"${CHECK}" --update "${TMP}"
jq -e '(.interfaces | length) == 1 and (.interfaces[0].sources | length) == 2' "${REGISTRY}" >/dev/null
rm "${TMP}/src/SharedLib.sol"

# Existing compact account declarations and canonical-vs-bundled IDs remain supported.
cat >"${TMP}/src/LegacyLib.sol" <<'EOF'
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;
/// @dev IERC6551Account = 0x6faff5f1; IERC6551Executable = 0x51945447.
bytes32 constant ERC165_MAP_IERC6551ACCOUNT_SLOT = 0xe5e50471a231013bea8f6034ec0b978814d697120ebd88e3624ed42959ed0a66;
bytes32 constant ERC165_MAP_IERC6551EXECUTABLE_SLOT =
    0x7119a8e42d55700f1f34f34e17ffb769e414497fcab2ff2004aa97c610742b4b;

bytes32 constant ERC165_MAP_IERC7579EXECUTION_SLOT = 0x1adc25256844eecf70d1111a7d897d059d6c39bccc33e2fe1bcdd0aa07e45227; // 0x3f3f9537
bytes32 constant ERC165_MAP_IERC7579ACCOUNTCONFIG_SLOT =
    0xca27659497801bbd07af0889ead6ea5a1a9b8739438e7af51464f7082b08ae43; // 0xbe1d6cf6

/// @dev The canonical ID is 0x80ac58cd; the bundled interface type derives 0xdbf24b52.
/// `keccak256(abi.encode(bytes4(0x80ac58cd), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC721_SLOT = 0x741e8246930c2bfc93c4e7042569e8d7f42e535e31e366398006f597e42d38fb;
EOF
cat >>"${TMP}/STORAGE_REGISTRY.md" <<'EOF'
| ERC721 | — | — | `IERC721` | `0x80ac58cd` | `0x741e8246930c2bfc93c4e7042569e8d7f42e535e31e366398006f597e42d38fb` |
| ErrorsOnly | — | — | no functions | `0x00000000` | — |
EOF
"${CHECK}" --update "${TMP}"
"${CHECK}" --check "${TMP}"
jq -e '(.interfaces | length) == 6 and any(.interfaces[]; .interfaceId == "0x80ac58cd") and all(.interfaces[]; .interfaceId != "0xdbf24b52")' "${REGISTRY}" >/dev/null
printf '{}\n' >"${REGISTRY}"
if "${CHECK}" --check "${TMP}" >/dev/null 2>&1; then
    echo 'FAIL: accepted committed JSON drift' >&2
    exit 1
fi
echo 'Storage registry export and mutation fixtures passed.'

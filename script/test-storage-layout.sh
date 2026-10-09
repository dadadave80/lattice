#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# test-storage-layout.sh
#
# Regression tests for the storage-safety Action's checker
# (.github/actions/storage-layout/check-storage-layout.sh). Each case copies the fixture consumer
# project (.github/actions/storage-layout/fixture, no Lattice sources or dependencies) into a git
# repository whose path contains a space, commits it as the trusted base, applies one change, and
# asserts the checker's exit status (0 pass, 1 layout failure, 2 usage or environment error) and the
# reason it reports.
#
# Usage: ./script/test-storage-layout.sh   (`make scripts-check` runs it; needs forge, cast, jq, git)
# ---------------------------------------------------------------------------
# Case setups are single-quoted on purpose: expect() evals them, so they expand per case.
# shellcheck disable=SC2016
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="${HERE}/../.github/actions/storage-layout/check-storage-layout.sh"
FIXTURE="${HERE}/../.github/actions/storage-layout/fixture"
tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT
repo="${tmp}/consumer repo"
failures=0
n=0

mkdir -p "${repo}"
cp -R "${FIXTURE}/." "${repo}/"
rm -rf "${repo}/out" "${repo}/cache"
g() { git -C "${repo}" -c user.name=test -c user.email=test@example.invalid -c commit.gpgsign=false "$@"; }
g init -q
g add -A
g commit -qm base
base="$(g rev-parse HEAD)"
# Trusted commits whose baseline labels the nested Position as top-level: `legacy` under its parent's
# namespace (one namespace on two sections, as an older Lattice checker wrote it), `toplevel` under a
# namespace of its own (a real top-level struct, which may not become nested).
relabel() {
    g reset -q --hard "${base}"
    perl -0pi -e "s/### Position \(nested\)/### Position \@ erc7201:$1 (slot $(cast index-erc7201 "$1"))/" "${repo}/storage-layout.baseline"
    g commit -qam "$1"
    g rev-parse HEAD
}
legacy="$(relabel fixture.storage.Vault)"
toplevel="$(relabel fixture.storage.Position)"
g reset -q --hard "${base}"

check() {
    "${CHECK}" --root "${repo}" --probe script/StorageProbe.sol:StorageProbe --baseline storage-layout.baseline --profile default "$@"
}
regen() { check --update >/dev/null 2>&1; }
# edit <file> <perl-expression>: edit a fixture file in place (portable to macOS and Linux).
edit() { perl -0pi -e "$2" "${repo}/$1"; }
resets() { printf '%s\n' "$@" >"${repo}/storage-layout.resets"; }
# reset_line <struct>: the reviewed reset line the checker prints for <struct>.
reset_line() { { check --baseline-ref "${base}" 2>&1 || true; } | grep -oE "'$1 [0-9a-f]{12}'" | tr -d "'" | head -n1; }
slot() { cast index-erc7201 "$1" | cut -c3-; }

# expect <0|1|2> <name> <setup> <pattern> [checker args...]: restore the base tree, run <setup> (which
# must change the tree unless it is `:`), run the checker, and require its exit status and, unless
# <pattern> is empty, an output line matching the extended regex <pattern>.
expect() {
    local want=$1 name=$2 setup=$3 pattern=$4 got why=""
    shift 4
    n=$((n + 1))
    g checkout -q -- .
    g clean -qfd
    eval "${setup}"
    if [[ "${setup}" != ":" && -z "$(g status --porcelain)" ]]; then
        why="setup did not change the fixture"
    fi
    set +e
    check "$@" >"${tmp}/out.log" 2>&1
    got=$?
    set -e
    [[ "${got}" == "${want}" ]] || why="expected exit ${want}, got ${got}"
    if [[ -z "${why}" && -n "${pattern}" ]] && ! grep -qE -- "${pattern}" "${tmp}/out.log"; then
        why="output does not match /${pattern}/"
    fi
    if [[ -z "${why}" ]]; then
        echo "ok   ${name}"
    else
        echo "FAIL ${name} (${why})"
        sed 's/^/     /' "${tmp}/out.log"
        failures=$((failures + 1))
    fi
}

B=(--baseline-ref "${base}")
APPEND='edit src/VaultLib.sol "s/(Position\[\] history;)/\$1\n    uint256 total;/"'
SWAP_CONFIG='edit src/VaultLib.sol "s/uint256 cap;\n    bool paused;/bool paused;\n    uint256 cap;/"'

# Passing
expect 0 "identical layout, drift only" ':' 'no --baseline-ref'
expect 0 "identical layout against the trusted base" ':' 'append-only relative to' "${B[@]}"
expect 0 "AST-id-only change (a declaration added before the structs)" \
    'edit src/VaultLib.sol "s/(struct Position)/error Unused();\n\n\$1/"' 'append-only relative to' "${B[@]}"
expect 0 "top-level append with an updated baseline" "${APPEND}; regen" 'append-only relative to' "${B[@]}"
expect 0 "packed top-level append into a slot's free tail" \
    'edit src/VaultLib.sol "s/(bool paused;)/\$1\n    uint8 mode;/"; regen' 'append-only relative to' "${B[@]}"
expect 0 "new namespace with an updated baseline" \
    'edit src/VaultLib.sol "s/(\/\/\/ \@title)/\/\/\/ \@custom:storage-location erc7201:fixture.storage.Extra\nstruct ExtraStorage {\n    uint256 x;\n}\n\n\$1/; s/(library VaultLib \{)/\$1\n    bytes32 internal constant EXTRA = 0x$(slot fixture.storage.Extra);/"
     edit script/StorageProbe.sol "s/\{ConfigStorage, /{ConfigStorage, ExtraStorage, /; s/(ConfigStorage internal config;)/\$1\n    ExtraStorage internal extra;/"
     regen' 'append-only relative to' "${B[@]}"
expect 0 "struct declared inside the library, same layout" \
    'edit src/VaultLib.sol "s/\/\/\/ \@custom:storage-location erc7201:fixture.storage.Config\nstruct ConfigStorage \{\n    uint256 cap;\n    bool paused;\n\}\n\n//; s/(library VaultLib \{)/\$1\n    \/\/\/ \@custom:storage-location erc7201:fixture.storage.Config\n    struct ConfigStorage {\n        uint256 cap;\n        bool paused;\n    }\n/"
     edit script/StorageProbe.sol "s/\{ConfigStorage, VaultStorage\}/{VaultLib, VaultStorage}/; s/ConfigStorage internal config/VaultLib.ConfigStorage internal config/"' \
    'append-only relative to' "${B[@]}"

# Layout failures
expect 1 "top-level append with a stale baseline" "${APPEND}" '^\+3	0	total	t_uint256' "${B[@]}"
expect 1 "source-only retype with an untouched baseline (drift only)" \
    'edit src/VaultLib.sol "s/uint96 fee/uint64 fee/"' '^FAIL: ERC-7201 storage layout drifted'
expect 1 "reorder, baseline regenerated in the same change" \
    'edit src/VaultLib.sol "s/address owner;\n    uint96 fee;/uint96 fee;\n    address owner;/"; regen' \
    '^VaultStorage: existing members changed' "${B[@]}"
expect 1 "removal, baseline regenerated" \
    'edit src/VaultLib.sol "s/\n    Position\[\] history;//"; regen' '^VaultStorage: members removed' "${B[@]}"
expect 1 "width change, baseline regenerated" \
    'edit src/VaultLib.sol "s/uint96 fee/uint64 fee/"; regen' '^> 0	20	fee	t_uint64' "${B[@]}"
expect 1 "rename, baseline regenerated" \
    'edit src/VaultLib.sol "s/bool paused;/bool frozen;/"; regen' '^ConfigStorage: existing members changed' "${B[@]}"
expect 1 "namespace and slot change, baseline regenerated" \
    'edit src/VaultLib.sol "s/fixture.storage.Vault\b/fixture.storage.Vault2/; s/$(slot fixture.storage.Vault)/$(slot fixture.storage.Vault2)/"; regen' \
    '^VaultStorage: header changed' "${B[@]}"
expect 1 "mapping key change, baseline regenerated" \
    'edit src/VaultLib.sol "s/mapping\(address account/mapping(bytes32 account/"; regen' \
    '^> 1	0	positions	t_mapping\(t_bytes32' "${B[@]}"
expect 1 "mapping value change, baseline regenerated" \
    'edit src/VaultLib.sol "s/=> Position\) positions/=> uint256) positions/"; regen' \
    '^> 1	0	positions	t_mapping\(t_address,t_uint256\)' "${B[@]}"
expect 1 "nested append under an unchanged outer type, baseline regenerated" \
    'edit src/VaultLib.sol "s/(uint64 since;)/\$1\n    uint32 flags;/"; regen' '^Position: nested struct changed size' "${B[@]}"
expect 1 "nested retype under an unchanged outer type, baseline regenerated" \
    'edit src/VaultLib.sol "s/uint64 since;/uint32 since;/"; regen' '^Position: existing members changed' "${B[@]}"

# Reviewed fresh-deployment resets
expect 0 "reset waives only the struct it names" \
    "${SWAP_CONFIG}; regen; resets \"\$(reset_line ConfigStorage)\"" '^RESET: ConfigStorage' \
    "${B[@]}" --resets storage-layout.resets
expect 1 "reset does not waive another struct" \
    "${SWAP_CONFIG}; edit src/VaultLib.sol 's/uint96 fee/uint64 fee/'; regen; resets \"\$(reset_line ConfigStorage)\"" \
    '^VaultStorage: existing members changed' "${B[@]}" --resets storage-layout.resets
expect 1 "reset bound to another layout has no effect" \
    "${SWAP_CONFIG}; regen; resets 'ConfigStorage 000000000000'" '^NOTE: reset entry .* has no effect' \
    "${B[@]}" --resets storage-layout.resets
expect 1 "reset whose change was reverted waives nothing and fails" \
    "${SWAP_CONFIG}; regen; resets \"\$(reset_line ConfigStorage)\"; g checkout -q -- src storage-layout.baseline" \
    "^ConfigStorage: unused reset 'ConfigStorage [0-9a-f]{12}'" "${B[@]}" --resets storage-layout.resets
expect 1 "unused reset beside a used one fails" \
    'edit src/VaultLib.sol "s/uint96 fee/uint64 fee/"; regen; v="$(reset_line VaultStorage)"; g checkout -q -- src storage-layout.baseline
     '"${SWAP_CONFIG}"'; regen; resets "$(reset_line ConfigStorage)" "${v}"' \
    '^VaultStorage: unused reset' "${B[@]}" --resets storage-layout.resets

# Baselines written by an older checker
expect 0 "nested struct labelled with its parent's namespace by an older checker" ':' \
    '^NOTE: Position is labelled .* by an older checker' --baseline-ref "${legacy}"
expect 1 "older-checker label does not hide a nested change" \
    'edit src/VaultLib.sol "s/uint64 since;/uint32 since;/"; regen' '^Position: existing members changed' --baseline-ref "${legacy}"
expect 1 "a top-level struct with its own namespace may not become nested" ':' \
    '^Position: header changed' --baseline-ref "${toplevel}"
expect 1 "older-checker label does not let another namespace become nested" \
    'edit src/VaultLib.sol "s/ \@custom:storage-location erc7201:fixture.storage.Config/ Config, now held inside VaultStorage./; s/(Position\[\] history;)/\$1\n    ConfigStorage config;/"; regen' \
    '^ConfigStorage: header changed' --baseline-ref "${legacy}"

# Fail closed
MIRROR='struct VaultStorage {\n    address owner;\n    uint96 fee;\n    mapping(address account => Position) positions;\n    Position[] history;\n}'
expect 2 "probe redeclares a mirror struct" \
    'edit script/StorageProbe.sol "s/import \{ConfigStorage, VaultStorage\} from \"..\/src\/VaultLib.sol\";/import {ConfigStorage} from \"..\/src\/VaultLib.sol\";\n\nstruct VaultStorage {\n    address owner;\n}/"' \
    'lays out a copy of VaultStorage \(AST id [0-9]+\), not the struct declared in src/VaultLib.sol'
expect 2 "probe redeclares a mirror beside an aliased real import" \
    'edit script/StorageProbe.sol "s/VaultStorage\}/VaultStorage as Real, Position}/; s/(contract StorageProbe)/'"${MIRROR}"'\n\n\$1/"' \
    'lays out a copy of VaultStorage'
expect 2 "aliased mirror from a side file hides a reorder" \
    'mkdir -p "${repo}/script/m"
     printf "// SPDX-License-Identifier: MIT\npragma solidity ^0.8.30;\n\nimport {Position} from \"../../src/VaultLib.sol\";\n\n'"${MIRROR}"'\n" >"${repo}/script/m/Frozen.sol"
     edit script/StorageProbe.sol "s/(\nimport)/\nimport {VaultStorage as Frozen} from \".\/m\/Frozen.sol\";\$1/; s/VaultStorage internal vault/Frozen internal vault/"
     edit src/VaultLib.sol "s/address owner;\n    uint96 fee;/uint96 fee;\n    address owner;/"' \
    'lays out a copy of VaultStorage' "${B[@]}"
expect 2 "two distinct structs with one name reach the probe" \
    'mkdir -p "${repo}/script/m"
     printf "// SPDX-License-Identifier: MIT\npragma solidity ^0.8.30;\n\nstruct Position {\n    uint8 x;\n}\n" >"${repo}/script/m/Other.sol"
     edit script/StorageProbe.sol "s/(\nimport)/\nimport {Position as P2} from \".\/m\/Other.sol\";\$1/; s/(ConfigStorage internal config;)/\$1\n    P2 internal p2;/"' \
    'distinct structs share a name in the probe layout.*: Position'
expect 2 "two annotated structs share a name" \
    'printf "// SPDX-License-Identifier: MIT\npragma solidity ^0.8.30;\n\n/// @custom:storage-location erc7201:fixture.storage.Other\nstruct ConfigStorage {\n    uint256 x;\n}\n" >"${repo}/src/Other.sol"' \
    'annotated structs share a name.*ConfigStorage'
expect 2 "two annotations share a namespace" \
    'edit src/VaultLib.sol "s/(\/\/\/ \@title)/\/\/\/ \@custom:storage-location erc7201:fixture.storage.Vault\nstruct ExtraStorage {\n    uint256 x;\n}\n\n\$1/"' \
    'namespace is declared more than once.*fixture.storage.Vault'
expect 2 "probe does not compile a guarded struct's file" \
    'printf "// SPDX-License-Identifier: MIT\npragma solidity ^0.8.30;\n\n/// @custom:storage-location erc7201:fixture.storage.Other\nstruct OtherStorage {\n    uint256 x;\n}\n\n/// @dev 0x%s\n" "$(slot fixture.storage.Other)" >"${repo}/src/Other.sol"' \
    'does not compile src/Other.sol'
expect 2 "probe omits a guarded struct" 'edit script/StorageProbe.sol "s/\n    ConfigStorage internal config;//"' 'ZERO member rows'
expect 2 "probe file missing" ':' 'probe source .* not found' --probe script/Missing.sol:StorageProbe
expect 2 "probe contract missing" ':' 'no storageLayout for probe' --probe script/StorageProbe.sol:Missing
expect 2 "annotation not followed by its struct" \
    'edit src/VaultLib.sol "s/(\/\/\/ \@custom:storage-location erc7201:fixture.storage.Config)/\$1\n\/\/\/ a\n\/\/\/ b\n\/\/\/ c/"' \
    'paired only 1 with a struct'
expect 2 "slot literal missing from the declaring file" 'edit src/VaultLib.sol "s/0x4cde6f/0x4cde6e/"' 'does not contain its slot'
expect 2 "compile error" 'edit src/VaultLib.sol "s/uint256 cap;/uint256 cap/"' 'forge build of the probe .* failed'
expect 2 "baseline missing" 'rm "${repo}/storage-layout.baseline"' 'baseline .* missing'
expect 2 "baseline ref is not a commit" ':' 'is not a commit' --baseline-ref 0000000000000000000000000000000000000000
expect 2 "no annotated struct" 'edit src/VaultLib.sol "s/\@custom:storage-location/custom location/g"' 'no .* annotation found'

echo "$((n - failures))/${n} storage-layout cases passed"
[[ "${failures}" -eq 0 ]]

#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# check-storage-layout.sh
#
# Dependency-free CI guard for the APPEND-ONLY ERC-7201 storage-struct rule
# (see CLAUDE.md "Append-only storage struct rule (upgrade safety)").
#
# Lattice composes modules into a long-lived, governance-upgradeable Diamond.
# An ERC-7201 storage struct must therefore only ever be EXTENDED by appending
# new fields at the end -- never reorder, retype, shrink, or remove an existing
# field, and never change the struct's @custom:storage-location namespace.
# Reordering/retyping silently corrupts live storage in a way that slot-
# uniqueness checks (StorageSlotVerificationTest) cannot catch.
#
# HOW IT WORKS
#   1. `forge inspect <Probe> storageLayout` under FOUNDRY_PROFILE=ci (which the
#      repo already sets `extra_output = ["storageLayout"]`) emits the field-by-
#      field layout of each module struct, imported and declared as a state variable
#      in `script/upgrades/StorageLayoutProbe.sol`. (A module's real struct is only
#      reached via an assembly slot-cast, so solc emits NO layout for the library
#      itself -- the probe is what makes the layout inspectable. This is the
#      standard Foundry idiom for ERC-7201 namespaced storage.)
#   2. We normalize each struct's members to `slot offset label baseType`,
#      stripping solc's build-volatile numeric AST ids from composite type names
#      (e.g. `t_struct(CutRecord)69929_storage` -> `t_struct(CutRecord)_storage`)
#      so the baseline is stable across recompiles.
#   3. We diff the current normalized layout against the committed baseline at
#      `script/upgrades/storage-layout.baseline`. ANY difference fails CI: an
#      appended field changes the baseline (re-run with --update and review the
#      diff in code review); a reorder/retype/shrink/removal ALSO changes it and
#      is the incompatible case the reviewer must reject.
#
# NESTED STRUCTS: every other struct type reachable from a guarded struct (e.g. `Group` inside
#   SemaphoreStorage, `CutRecord` inside the *DiamondCut storages, `ChainRecord` inside
#   ChainRegistryStorage) gets its own "(nested)" section, so reordering or retyping a nested
#   struct's fields fails the check too.
#
# USAGE
#   script/upgrades/check-storage-layout.sh            # verify (CI mode; exit 1 on drift)
#   script/upgrades/check-storage-layout.sh --update   # regenerate the baseline
#
# REQUIRES: foundry (`forge`, `cast`) and `jq` (preinstalled on GitHub runners).
# ---------------------------------------------------------------------------
set -euo pipefail
# Byte-order collation, so `sort` gives the same section order on macOS and on the Linux CI runner.
export LC_ALL=C

# Resolve repo root from this script's location so it runs from anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

BASELINE="script/upgrades/storage-layout.baseline"
PROBE="StorageLayoutProbe"

# Structs to guard: EVERY `@custom:storage-location erc7201:<ns>` annotation in src/, paired with the
# `struct <Name>` line that follows it. Deriving the list (instead of maintaining it by hand) makes the
# guard complete by construction: a new module struct is checked automatically, and if it is missing from
# StorageLayoutProbe.sol the check fails loudly with a ZERO-member-rows error below.
GUARDED_STRUCTS=()
while IFS= read -r entry; do GUARDED_STRUCTS+=("${entry}"); done < <(
    grep -rn --include='*.sol' -A3 '@custom:storage-location erc7201:' src \
        | awk '
            match($0, /erc7201:[A-Za-z0-9._]+/) { ns = substr($0, RSTART + 8, RLENGTH - 8); next }
            ns != "" && match($0, /-struct [A-Za-z0-9_]+/) {
                print substr($0, RSTART + 8, RLENGTH - 8) " " ns; ns = ""
            }' \
        | sort
)
NAMESPACE_COUNT="$(grep -rhoE --include='*.sol' '@custom:storage-location erc7201:[A-Za-z0-9._]+' src | wc -l | tr -d ' ')"
if [[ "${#GUARDED_STRUCTS[@]}" -ne "${NAMESPACE_COUNT}" ]]; then
    echo "ERROR: found ${NAMESPACE_COUNT} erc7201 annotations in src/ but paired only ${#GUARDED_STRUCTS[@]} with a struct." >&2
    echo "Each annotation must sit directly above its 'struct <Name> {' line." >&2
    exit 2
fi

command -v forge >/dev/null 2>&1 || { echo "ERROR: forge not found on PATH" >&2; exit 2; }
command -v jq    >/dev/null 2>&1 || { echo "ERROR: jq not found on PATH" >&2; exit 2; }

# Emit the normalized layout for every guarded struct to stdout.
generate_layout() {
    # Build under the CI profile so storageLayout is emitted into the artifact,
    # then inspect the probe by bare contract name (resolves via the artifact cache).
    FOUNDRY_PROFILE=ci forge build >/dev/null 2>&1
    local raw
    raw="$(FOUNDRY_PROFILE=ci forge inspect "${PROBE}" storageLayout --json 2>/dev/null)"
    if [[ -z "${raw}" ]]; then
        echo "ERROR: empty storageLayout for probe '${PROBE}'. Did 'forge build' (ci) succeed?" >&2
        exit 2
    fi

    # Members of struct <name>, one "slot offset label type" row each. Volatile numeric AST ids are
    # stripped from composite type names so the baseline is recompile-stable. The match is anchored to
    # REAL struct entries ("^t_struct(Name)"): an unanchored match also hits mapping/array type keys that
    # EMBED the struct name, whose .members is null, and would silently emit an EMPTY section.
    struct_members() {
        echo "${raw}" | jq -r --arg n "$1" '
            .types
            | to_entries[]
            | select(.key | test("^t_struct\\(" + $n + "\\)"))
            | (.value.members // [])[]
            | "\(.slot)\t\(.offset)\t\(.label)\t\(.type)"
        ' | sed -E 's/\)[0-9]+/)/g' | sort -n -k1,1 -k2,2
    }

    # Sections are keyed by struct name, so two different structs sharing a name would merge their rows.
    local clash
    clash="$(echo "${raw}" | jq -r '.types | keys[] | capture("^t_struct\\((?<n>[A-Za-z0-9_]+)\\)(?<id>[0-9]+)") | "\(.n) \(.id)"' \
        | sort -u | awk '{print $1}' | uniq -d)"
    if [[ -n "${clash}" ]]; then
        echo "ERROR: several distinct structs share a name, so their layouts can't be told apart: ${clash}" >&2
        exit 2
    fi

    local entry name ns slot_root header members
    local -a top_names=()
    for entry in "${GUARDED_STRUCTS[@]}"; do
        name="${entry%% *}"
        ns="${entry#* }"
        # Verify the erc7201 slot the namespace derives matches the live module slot.
        slot_root="$(cast index-erc7201 "${ns}" 2>/dev/null || true)"
        header="### ${name} @ erc7201:${ns}"
        [[ -n "${slot_root}" ]] && header="${header} (slot ${slot_root})"
        echo "${header}"

        top_names+=("${name}")
        members="$(struct_members "${name}")"
        # FAIL LOUD on an empty section: a guarded struct with zero member rows means the guard
        # is vacuous (missing from the probe, or a filter regression).
        if [[ -z "${members}" ]]; then
            echo "ERROR: guarded struct '${name}' produced ZERO member rows — vacuous guard." >&2
            echo "Import ${name} into ${PROBE}.sol and declare it as an internal state variable." >&2
            exit 2
        fi
        echo "${members}"
        echo ""
    done

    # Every other struct type in the probe layout is nested inside a guarded struct.
    local nested
    nested="$(echo "${raw}" | jq -r '.types | keys[] | select(startswith("t_struct(")) | capture("^t_struct\\((?<n>[A-Za-z0-9_]+)\\)").n' \
        | sort -u | grep -vxF -f <(printf '%s\n' "${top_names[@]}") || true)"
    for name in ${nested}; do
        echo "### ${name} (nested)"
        struct_members "${name}"
        echo ""
    done
}

CURRENT="$(generate_layout)"

if [[ "${1:-}" == "--update" ]]; then
    printf '%s\n' "${CURRENT}" > "${BASELINE}"
    echo "Baseline written to ${BASELINE}:"
    echo "------------------------------------------------------------------"
    cat "${BASELINE}"
    echo "------------------------------------------------------------------"
    echo "Review the diff in code review. An APPENDED field is safe; a"
    echo "reorder/retype/shrink/removal is an UPGRADE-BREAKING change."
    exit 0
fi

if [[ ! -f "${BASELINE}" ]]; then
    echo "ERROR: baseline '${BASELINE}' missing. Generate it with:" >&2
    echo "  script/upgrades/check-storage-layout.sh --update" >&2
    exit 2
fi

if diff -u "${BASELINE}" <(printf '%s\n' "${CURRENT}") >/tmp/storage-layout.diff 2>&1; then
    echo "OK: ERC-7201 storage layouts match the committed baseline (append-only intact)."
    exit 0
else
    echo "FAIL: ERC-7201 storage layout drifted from ${BASELINE}." >&2
    echo "----------------------------------------------------------------------" >&2
    cat /tmp/storage-layout.diff >&2
    echo "----------------------------------------------------------------------" >&2
    echo "If you APPENDED a field (safe): re-run with --update and commit the new" >&2
    echo "baseline. If a field was reordered/retyped/shrunk/removed, that is an" >&2
    echo "UPGRADE-BREAKING change to live storage -- revert it." >&2
    exit 1
fi

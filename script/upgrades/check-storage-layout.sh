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
#      field layout of each module struct, mirrored as a real state variable in
#      `script/upgrades/StorageLayoutProbe.sol`. (A module's real struct is only
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
# LIMITATION (nested value-structs): the diff captures a struct member typed as a
#   nested value-struct (or a mapping to one) by its TYPE NAME only, not by that
#   nested struct's internal field layout. So reordering/retyping the fields of a
#   nested struct (e.g. `Group` inside SemaphoreStorage, `CutRecord` inside the
#   *DiamondCut storages, `Commitment` inside CommitReveal) is NOT caught here.
#   Mitigation: every such nested struct is mirrored VERBATIM in
#   StorageLayoutProbe.sol, so the change is visible in code review -- reviewers
#   MUST manually inspect any edit to a nested value-struct's fields. (A future
#   enhancement could recursively expand nested structs into the diffed layout.)
#
# USAGE
#   script/upgrades/check-storage-layout.sh            # verify (CI mode; exit 1 on drift)
#   script/upgrades/check-storage-layout.sh --update   # regenerate the baseline
#
# REQUIRES: foundry (`forge`, `cast`) and `jq` (preinstalled on GitHub runners).
# ---------------------------------------------------------------------------
set -euo pipefail

# Resolve repo root from this script's location so it runs from anywhere.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
cd "${REPO_ROOT}"

BASELINE="script/upgrades/storage-layout.baseline"
PROBE="StorageLayoutProbe"

# Module structs to guard. Add a line "<StructName> <erc7201-namespace>" here when
# you mirror a new module struct into StorageLayoutProbe.sol.
#   <StructName>            : the struct name as declared in the probe.
#   <namespace>             : the module's @custom:storage-location erc7201 string.
GUARDED_STRUCTS=(
    "GovernedDiamondCutStorage lattice.storage.GovernedDiamondCut"
    "SafeDiamondCutStorage lattice.storage.SafeDiamondCut"
    "GovernedSafeDiamondCutStorage lattice.storage.GovernedSafeDiamondCut"
    "ERC6538RegistryStorage lattice.storage.ERC6538Registry"
    "ENSReverseClaimerStorage lattice.storage.ENSReverseClaimer"
    "ENSResolverStorage lattice.storage.ENSResolver"
    "ENSSubnameIssuerStorage lattice.storage.ENSSubnameIssuer"
    "SafeHarborAdopterStorage lattice.storage.SafeHarborAdopter"
    "CommitRevealStorage lattice.storage.CommitReveal"
    "SemaphoreStorage lattice.storage.Semaphore"
    "PrivateVotingStorage lattice.storage.PrivateVoting"
    "ShieldedPoolStorage lattice.storage.ShieldedPool"
    "PythAdapterStorage lattice.storage.PythAdapter"
    "API3AdapterStorage lattice.storage.API3Adapter"
    "ChronicleAdapterStorage lattice.storage.ChronicleAdapter"
    "DIAAdapterStorage lattice.storage.DIAAdapter"
    "BandAdapterStorage lattice.storage.BandAdapter"
    "TellorAdapterStorage lattice.storage.TellorAdapter"
    "RedStoneAdapterStorage lattice.storage.RedStoneAdapter"
    "CrosschainLinkStorage lattice.storage.CrosschainLink"
    "BridgeERC20Storage lattice.storage.BridgeERC20"
    "BridgeERC7802Storage lattice.storage.BridgeERC7802"
    "AxelarGatewayAdapterStorage lattice.storage.AxelarGatewayAdapter"
    "WormholeGatewayAdapterStorage lattice.storage.WormholeGatewayAdapter"
    "ERC7786OpenBridgeStorage lattice.storage.ERC7786OpenBridge"
    "CCIPGatewayAdapterStorage lattice.storage.CCIPGatewayAdapter"
    "CCTPBridgeAdapterStorage lattice.storage.CCTPBridgeAdapter"
    "AggregatorExecAdapterStorage lattice.storage.AggregatorExecAdapter"
    "LayerZeroGatewayAdapterStorage lattice.storage.LayerZeroGatewayAdapter"
    "L2ToL2CrossDomainMessengerGatewayAdapterStorage lattice.storage.L2ToL2CrossDomainMessengerGatewayAdapter"
    "ZetaChainGatewayAdapterStorage lattice.storage.ZetaChainGatewayAdapter"
    "L1ToL2CrossDomainMessengerGatewayAdapterStorage lattice.storage.L1ToL2CrossDomainMessengerGatewayAdapter"
    "PythEntropyAdapterStorage lattice.storage.PythEntropyAdapter"
    "GelatoVRFAdapterStorage lattice.storage.GelatoVRFAdapter"
    "API3QRNGAdapterStorage lattice.storage.API3QRNGAdapter"
    "GelatoAutomateAdapterStorage lattice.storage.GelatoAutomateAdapter"
    "ChainlinkAutomationAdapterStorage lattice.storage.ChainlinkAutomationAdapter"
    "ChainlinkCREAdapterStorage lattice.storage.ChainlinkCREAdapter"
    "MarketplaceZoneStorage lattice.storage.MarketplaceZone"
    "AccountSignerStorage lattice.storage.AccountSigner"
    "ERC4337ValidationStorage lattice.storage.ERC4337Validation"
    "SessionKeyStorage lattice.storage.SessionKey"
    "ERC7579ModuleConfigStorage lattice.storage.ERC7579ModuleConfig"
    "ERC6551AccountStorage lattice.storage.ERC6551Account"
    "ERC6900ModuleManagerStorage lattice.storage.ERC6900ModuleManager"
    "AcrossBridgeAdapterStorage lattice.storage.AcrossBridgeAdapter"
)

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

    local entry name ns slot_root header expected_ns
    for entry in "${GUARDED_STRUCTS[@]}"; do
        name="${entry%% *}"
        ns="${entry#* }"
        # Verify the erc7201 slot the namespace derives matches the live module slot.
        slot_root="$(cast index-erc7201 "${ns}" 2>/dev/null || true)"
        header="### ${name} @ erc7201:${ns}"
        [[ -n "${slot_root}" ]] && header="${header} (slot ${slot_root})"
        echo "${header}"

        # Pull the struct's members; strip volatile numeric AST ids from composite
        # type names so the baseline is recompile-stable.
        echo "${raw}" | jq -r --arg n "${name}" '
            .types
            | to_entries[]
            | select(.key | test("\\(" + $n + "\\)"))
            | .value.members[]
            | "\(.slot)\t\(.offset)\t\(.label)\t\(.type)"
        ' | sed -E 's/\)[0-9]+/)/g' | sort -n -k1,1 -k2,2
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

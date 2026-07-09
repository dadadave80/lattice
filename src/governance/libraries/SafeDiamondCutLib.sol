// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib, FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ISafe} from "@lattice/interfaces/external/ISafe.sol";
import {IEmergencyCut} from "@lattice/interfaces/governance/IEmergencyCut.sol";
import {IFrozenSelectors} from "@lattice/interfaces/governance/IFrozenSelectors.sol";
import {ISafeAuthority} from "@lattice/interfaces/governance/ISafeAuthority.sol";
import {ISafeDiamondCut} from "@lattice/interfaces/governance/ISafeDiamondCut.sol";
import {IUpgradeRegistry} from "@lattice/interfaces/governance/IUpgradeRegistry.sol";
import {EMERGENCY_GUARDIAN_ROLE, EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {EnumerableSet} from "@lattice/utils/libraries/EnumerableSet.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.SafeDiamondCut")) - 1)) & ~bytes32(uint256(0xff))`.
///      Verify with: `cast index-erc7201 "lattice.storage.SafeDiamondCut"`.
bytes32 constant SAFE_DIAMOND_CUT_STORAGE_SLOT = 0xdfdae3ef74d2f2c31fc34cd5e60ae4b170cd90587a13d52debd5569f575e7900;

/// @dev ERC-165 storage location (same across all Lattice/diamond-lib modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant SAFE_DIAMOND_CUT_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev `type(ISafeDiamondCut).interfaceId` is NOT the cut selector: `ISafeDiamondCut` bundles
///      `diamondCut` + `setSafe` + `safe`, so its raw `interfaceId` differs from `0x1f931c1c`. But the
///      ONLY selector this facet must occupy to transparently replace diamond-lib's `DiamondCutFacet`
///      is the canonical cut selector `0x1f931c1c` (== `IDiamondCut.diamondCut.selector`). Its ERC-165
///      map slot is therefore `keccak256(abi.encode(bytes4(0x1f931c1c), ERC165_STORAGE_LOCATION))`
///      `= 0xa0f80413692945aab97c6ef0328381ebb94e4b17a84d11ebf6b61f73435b6d7e`, which is exactly
///      `DiamondLib`'s `ERC165_MAP_ICUT_SLOT`. We do NOT mint a separate constant or register a second
///      time: `DiamondLib.registerInterface()` already sets this flag in any 2535 deployment. The
///      `setSafe`/`safe` plus frozen/registry/emergency surface are plain facet functions, NOT advertised
///      as a distinct ERC-165 interface (matching {GovernedDiamondCut}).
bytes32 constant ERC165_MAP_ICUT_SLOT = 0xa0f80413692945aab97c6ef0328381ebb94e4b17a84d11ebf6b61f73435b6d7e;

/// @notice ERC-7201 namespaced storage for the SafeDiamondCut module.
/// @dev Pins the Safe authority and holds the module's own append-only upgrade audit trail.
///      APPEND-ONLY: fields are only ever added at the end — never reordered, retyped, or removed —
///      so the ERC-7201 slot stays stable across upgrades. The slot constant is unchanged because the
///      namespace string is unchanged.
/// @custom:storage-location erc7201:lattice.storage.SafeDiamondCut
struct SafeDiamondCutStorage {
    /// @dev The pinned Safe multisig that is the sole authority for cuts / freezes / rotation. The
    ///      facet trusts `msg.sender == _safe`; the Safe verifies its M-of-N owner signatures off-chain
    ///      and on-chain in `execTransaction` and MUST dispatch with `operation = Call`.
    address _safe;
    /// @dev Monotonic counter of cuts applied; doubles as the latest registry version. The value
    ///      assigned to a cut (post-increment) IS that cut's `version`.
    uint256 _cutCount;
    /// @dev Append-only registry: version (1-indexed) => immutable {IUpgradeRegistry.CutRecord}.
    ///      Written once per successful cut and never mutated thereafter.
    mapping(uint256 version => IUpgradeRegistry.CutRecord record) _cutRegistry;
    /// @dev Append-only set of frozen function selectors. A selector in this set can never be the
    ///      target of a `Replace` or `Remove` in any future cut (the guard checks this set BEFORE
    ///      delegating to diamond-lib). There is deliberately no unfreeze.
    EnumerableSet.Bytes4Set _frozenSelectors;
}

/// @title SafeDiamondCut Library
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Library that gates EIP-2535 diamond cuts behind EmergencyStop + a pinned Gnosis Safe
///         multisig, then delegates the actual cut to `DiamondLib.diamondCut`. Introduces no new cut
///         logic. The instant (no-delay) Safe-gated analogue of {GovernedDiamondCutLib}.
/// @dev Three-layer pattern: this library holds all logic and the namespaced storage. The stateless
///      {SafeDiamondCut} facet delegates its external calls here. AUTHORITY MODEL: a Safe collects
///      M-of-N owner signatures off-chain, verifies the threshold on-chain in `execTransaction`, then
///      calls the diamond with `operation = Call`, so the diamond sees `msg.sender == theSafe`. This
///      module therefore does NOT re-verify signatures — it only trusts `msg.sender == $._safe`. The
///      Safe MUST call with `operation = Call`; a DelegateCall would execute this facet's code in the
///      Safe's own context (wrong `msg.sender`, wrong storage) and is unsupported.
library SafeDiamondCutLib {
    using EnumerableSet for EnumerableSet.Bytes4Set;

    //*//////////////////////////////////////////////////////////////////////////
    //                           STORAGE ACCESSOR
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns a storage reference to the SafeDiamondCutStorage struct.
    function safeDiamondCutStorage() internal pure returns (SafeDiamondCutStorage storage $) {
        assembly {
            $.slot := SAFE_DIAMOND_CUT_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the SafeDiamondCut module by pinning the Safe authority.
    /// @dev Validates `_safe` is non-zero and is a real, sensibly-configured Safe whose on-chain
    ///      `getThreshold()` meets `_minThreshold` (which must itself be > 0). Reverts
    ///      {ISafeAuthority.SafeDiamondCutZeroSafe}, {ISafeAuthority.SafeDiamondCutZeroThreshold}, or
    ///      {ISafeAuthority.SafeDiamondCutThresholdTooLow} otherwise. Must be called inside the
    ///      preInitializer/postInitializer window. Does NOT register an ERC-165 interface: the canonical
    ///      cut selector `0x1f931c1c` is already registered by `DiamondLib.registerInterface()` (see the
    ///      ERC165_MAP_ICUT_SLOT note above).
    /// @param _safe The Safe multisig to pin as the cut authority.
    /// @param _minThreshold The minimum signature threshold the pinned Safe must enforce.
    function __SafeDiamondCut_init(address _safe, uint256 _minThreshold) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        _validateSafe(_safe, _minThreshold);
        safeDiamondCutStorage()._safe = _safe;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              SAFE AUTHORITY
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Reverts {ISafeAuthority.SafeDiamondCutUnauthorized} unless the caller is the pinned Safe.
    /// @dev Library `internal` functions inline into the calling facet, so `msg.sender` here is the
    ///      original caller of the Diamond — i.e. the Safe when it dispatches with `operation = Call`.
    function _checkSafe(SafeDiamondCutStorage storage $) private view {
        if (msg.sender != $._safe) {
            revert ISafeAuthority.SafeDiamondCutUnauthorized(msg.sender);
        }
    }

    /// @notice Validates a candidate Safe authority: non-zero, real Safe, threshold >= minimum (> 0).
    function _validateSafe(address _safe, uint256 _minThreshold) private view {
        if (_safe == address(0)) revert ISafeAuthority.SafeDiamondCutZeroSafe();
        if (_minThreshold == 0) revert ISafeAuthority.SafeDiamondCutZeroThreshold();
        uint256 threshold = ISafe(_safe).getThreshold();
        if (threshold < _minThreshold) {
            revert ISafeAuthority.SafeDiamondCutThresholdTooLow(threshold, _minThreshold);
        }
    }

    /// @notice Rotates the pinned Safe authority to `_newSafe`. Self-administered: callable ONLY by the
    ///         current pinned Safe, so only the existing multisig can hand authority to its successor.
    /// @dev `_newSafe` is validated exactly like the init Safe, re-asserting `getThreshold() >= 1` (the
    ///      minimum-meaningful threshold). Emits {ISafeAuthority.SafeRotated}.
    /// @param _newSafe The new Safe to pin as the cut authority.
    function setSafe(address _newSafe) internal {
        SafeDiamondCutStorage storage $ = safeDiamondCutStorage();
        _checkSafe($);
        _validateSafe(_newSafe, 1);
        address old = $._safe;
        $._safe = _newSafe;
        emit ISafeAuthority.SafeRotated(old, _newSafe);
    }

    /// @notice Returns the currently pinned Safe authority.
    function safe() internal view returns (address) {
        return safeDiamondCutStorage()._safe;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              SAFE-GATED CUT
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Guarded diamond cut: reverts if emergency-stopped, then requires the caller to be the
    ///         pinned Safe, then delegates to `DiamondLib.diamondCut`. Introduces no new cut logic —
    ///         all selector-collision, immutable-function, bytecode-existence, and init-delegatecall
    ///         handling is diamond-lib's.
    /// @param _diamondCut The facet addresses, cut actions, and function selectors.
    /// @param _init The address delegatecalled after the cut (address(0) to skip).
    /// @param _calldata The calldata passed to `_init`.
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) internal {
        // 1) Outer guard: a guardian can halt ALL upgrades without touching the Safe.
        EmergencyStopLib.checkNotStopped();

        SafeDiamondCutStorage storage $ = safeDiamondCutStorage();

        // 2) Authority: only the pinned Safe (msg.sender) may cut. The Safe enforced its M-of-N owner
        //    threshold off-chain/on-chain and dispatched with operation = Call.
        _checkSafe($);

        // 3) Protection: reject any Replace/Remove that targets a frozen selector BEFORE applying the
        //    cut. This prevents a cut from removing/replacing load-bearing selectors (e.g. the loupe or
        //    the cut path itself). Add actions are unaffected.
        _enforceNotFrozen($, _diamondCut);

        // 4) Apply the cut via diamond-lib (untouched core). If it reverts (e.g. selector clash),
        //    execution never reaches the registry write below — so a failed cut records NOTHING.
        DiamondLib.diamondCut(_diamondCut, _init, _calldata);

        uint256 version;
        unchecked {
            // Post-increment value is this cut's 1-indexed version (registry is 1-indexed).
            version = ++$._cutCount;
        }

        // 5) Append the immutable audit record under `version` (append-only registry).
        bytes32 cutHash = keccak256(abi.encode(_diamondCut, _init, _calldata));
        $._cutRegistry[version] = IUpgradeRegistry.CutRecord({
            cutHash: cutHash,
            executor: msg.sender,
            executedAt: uint48(block.timestamp),
            facetCutCount: uint32(_diamondCut.length),
            init: _init
        });

        emit ISafeDiamondCut.UpgradeExecuted(msg.sender, _diamondCut.length, _init);
        emit IUpgradeRegistry.CutRecorded(version, cutHash, msg.sender);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       EMERGENCY REMOVAL-ONLY CUT
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Zero-delay, REMOVAL-ONLY escape hatch: lets a guardian instantly unbind a compromised or
    ///         buggy facet's selectors WITHOUT going through the Safe — and, by design, even while the
    ///         normal cut path is halted by EmergencyStop. Deliberately constrained so a rogue guardian
    ///         can only AMPUTATE code (every entry must be `Remove`), never add or replace it (that still
    ///         requires `diamondCut` under the Safe authority), and can never remove a frozen
    ///         load-bearing selector.
    /// @dev Guard ordering mirrors {GovernedDiamondCutLib.emergencyRemoveCut}: (1) guardian-only
    ///      authority; (2) NO `checkNotStopped()` — this is the panic button and must work while
    ///      stopped; (3) removal-only (any Add/Replace reverts {IEmergencyCut.EmergencyCutMustBeRemoveOnly});
    ///      (4) frozen protection; (5) NO init delegatecall. Recorded in the SAME append-only registry
    ///      and additionally emits {IEmergencyCut.EmergencyCutExecuted}.
    /// @param _cuts The facet cuts to apply; every entry MUST be a `Remove` (facetAddress == address(0)).
    function emergencyRemoveCut(FacetCut[] calldata _cuts) internal {
        // 1) Authority: guardian-only. Reverts AccessControlUnauthorizedAccount(caller, role).
        AccessControlLib.checkRole(EMERGENCY_GUARDIAN_ROLE);

        // NOTE: `EmergencyStopLib.checkNotStopped()` is DELIBERATELY NOT called here. This path is the
        // panic button and must function while the diamond is emergency-stopped.

        SafeDiamondCutStorage storage $ = safeDiamondCutStorage();

        // 2) Removal-only + 3) frozen protection, fused in a single pass; also accumulate the selector
        //    count for the audit event.
        uint256 cutsLength = _cuts.length;
        uint256 selectorCount;
        EnumerableSet.Bytes4Set storage frozen = $._frozenSelectors;
        for (uint256 i; i < cutsLength; ++i) {
            FacetCutAction action = _cuts[i].action;
            if (action != FacetCutAction.Remove) {
                revert IEmergencyCut.EmergencyCutMustBeRemoveOnly(uint8(action));
            }
            bytes4[] calldata selectors = _cuts[i].functionSelectors;
            uint256 selectorsLength = selectors.length;
            for (uint256 j; j < selectorsLength; ++j) {
                if (frozen.contains(selectors[j])) {
                    revert IFrozenSelectors.FrozenSelectorProtected(selectors[j]);
                }
            }
            unchecked {
                selectorCount += selectorsLength;
            }
        }

        // 4) Apply the removal via diamond-lib. NO init callback — removal-only. `msg.data[:0]` is the
        //    canonical zero-length calldata slice. If diamond-lib reverts, nothing below records.
        bytes calldata emptyCalldata = msg.data[:0];
        DiamondLib.diamondCut(_cuts, address(0), emptyCalldata);

        uint256 version;
        unchecked {
            version = ++$._cutCount;
        }

        // 5) Record in the SAME append-only registry so emergency removals appear in cut history.
        bytes32 cutHash = keccak256(abi.encode(_cuts, address(0), emptyCalldata));
        $._cutRegistry[version] = IUpgradeRegistry.CutRecord({
            cutHash: cutHash,
            executor: msg.sender,
            executedAt: uint48(block.timestamp),
            facetCutCount: uint32(cutsLength),
            init: address(0)
        });

        emit IEmergencyCut.EmergencyCutExecuted(version, msg.sender, selectorCount);
        emit IUpgradeRegistry.CutRecorded(version, cutHash, msg.sender);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           FROZEN SELECTORS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Permanently freezes `_selectors`: each becomes ineligible to be the target of a
    ///         `Replace`/`Remove` in any future cut. Gated to the pinned Safe — the same authority that
    ///         gates `diamondCut`. Append-only: already-frozen selectors are idempotent no-ops, and
    ///         there is no unfreeze.
    /// @param _selectors The function selectors to freeze.
    function freezeSelectors(bytes4[] calldata _selectors) internal {
        SafeDiamondCutStorage storage $ = safeDiamondCutStorage();
        _checkSafe($);
        EnumerableSet.Bytes4Set storage frozen = $._frozenSelectors;
        uint256 length = _selectors.length;
        for (uint256 i; i < length; ++i) {
            frozen.add(_selectors[i]);
        }
        emit IFrozenSelectors.SelectorsFrozen(msg.sender, _selectors);
    }

    /// @dev Reverts {IFrozenSelectors.FrozenSelectorProtected} if any `Replace`/`Remove` action in
    ///      `_diamondCut` targets a frozen selector. `Add` actions are never inspected.
    function _enforceNotFrozen(SafeDiamondCutStorage storage $, FacetCut[] calldata _diamondCut) private view {
        EnumerableSet.Bytes4Set storage frozen = $._frozenSelectors;
        uint256 cutsLength = _diamondCut.length;
        for (uint256 i; i < cutsLength; ++i) {
            FacetCutAction action = _diamondCut[i].action;
            if (action == FacetCutAction.Add) continue;
            bytes4[] calldata selectors = _diamondCut[i].functionSelectors;
            uint256 selectorsLength = selectors.length;
            for (uint256 j; j < selectorsLength; ++j) {
                if (frozen.contains(selectors[j])) {
                    revert IFrozenSelectors.FrozenSelectorProtected(selectors[j]);
                }
            }
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the number of cuts applied so far (also the latest registry version).
    function cutCount() internal view returns (uint256) {
        return safeDiamondCutStorage()._cutCount;
    }

    /// @notice Returns the immutable audit record for a given registry `version`.
    /// @dev Versions are 1-indexed; an unwritten version (0, or any value > {cutCount}) returns a
    ///      zero-valued {IUpgradeRegistry.CutRecord}.
    /// @param _version The registry version to look up.
    function getCutRecord(uint256 _version) internal view returns (IUpgradeRegistry.CutRecord memory) {
        return safeDiamondCutStorage()._cutRegistry[_version];
    }

    /// @notice Returns whether `_selector` is in the frozen set (protected from Replace/Remove).
    /// @param _selector The function selector to query.
    function isSelectorFrozen(bytes4 _selector) internal view returns (bool) {
        return safeDiamondCutStorage()._frozenSelectors.contains(_selector);
    }

    /// @notice Returns the full set of frozen selectors.
    function frozenSelectors() internal view returns (bytes4[] memory) {
        return safeDiamondCutStorage()._frozenSelectors.values();
    }

    /// @notice Pre-flight simulation of the frozen-selector guard against the current set, with no
    ///         state change. Only `Replace`/`Remove` actions are inspected; a pure read of the frozen
    ///         set (does NOT re-implement diamond-lib's collision/immutable/bytecode checks).
    /// @param _cuts The candidate facet cuts to simulate.
    /// @return ok `true` if no `Replace`/`Remove` in `_cuts` targets a frozen selector.
    /// @return offendingSelector The first frozen selector a `Replace`/`Remove` would touch (zero if `ok`).
    function previewCut(FacetCut[] calldata _cuts) internal view returns (bool ok, bytes4 offendingSelector) {
        EnumerableSet.Bytes4Set storage frozen = safeDiamondCutStorage()._frozenSelectors;
        uint256 cutsLength = _cuts.length;
        for (uint256 i; i < cutsLength; ++i) {
            if (_cuts[i].action == FacetCutAction.Add) continue;
            bytes4[] calldata selectors = _cuts[i].functionSelectors;
            uint256 selectorsLength = selectors.length;
            for (uint256 j; j < selectorsLength; ++j) {
                if (frozen.contains(selectors[j])) {
                    return (false, selectors[j]);
                }
            }
        }
        return (true, bytes4(0));
    }

    /// @notice Verifies whether `_interfaceId` is currently advertised in the diamond's ERC-165 map.
    /// @dev Thin wrapper over the shared ERC-165 support read. Equivalent to `supportsInterface`.
    /// @param _interfaceId The ERC-165 interface identifier to check.
    function verifyInterfaceRegistered(bytes4 _interfaceId) internal view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

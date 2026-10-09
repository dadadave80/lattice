// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib, FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ISafe} from "@lattice/interfaces/external/safe/ISafe.sol";
import {IEmergencyCut} from "@lattice/interfaces/governance/IEmergencyCut.sol";
import {IFrozenSelectors} from "@lattice/interfaces/governance/IFrozenSelectors.sol";
import {IGovernedSafeDiamondCut} from "@lattice/interfaces/governance/IGovernedSafeDiamondCut.sol";
import {ISafeAuthority} from "@lattice/interfaces/governance/ISafeAuthority.sol";
import {ISafeDiamondCut} from "@lattice/interfaces/governance/ISafeDiamondCut.sol";
import {ITimelockController} from "@lattice/interfaces/governance/ITimelockController.sol";
import {IUpgradeRegistry} from "@lattice/interfaces/governance/IUpgradeRegistry.sol";
import {EMERGENCY_GUARDIAN_ROLE, EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {EnumerableSet} from "@lattice/utils/libraries/EnumerableSet.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.GovernedSafeDiamondCut")) - 1)) & ~bytes32(uint256(0xff))`.
///      Verify with: `cast index-erc7201 "lattice.storage.GovernedSafeDiamondCut"`.
bytes32 constant GOVERNED_SAFE_DIAMOND_CUT_STORAGE_SLOT =
    0x67b04bedb2ce49892ef6d6cc51adf679ddefc544b7aca2da8ae73f02694ff300;

/// @dev ERC-165 storage location (same across all Lattice/diamond-lib modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant GOVERNED_SAFE_DIAMOND_CUT_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0xacb1aeb6 is `type(IGovernedSafeDiamondCut).interfaceId`. Unlike {SafeDiamondCut}, this module
///      does NOT serve the canonical cut selector `0x1f931c1c` (every cut is delayed via the timelock),
///      so its scheduling surface (`scheduleCut`/`executeCut`/`cancelCut` + views) is a genuinely NEW
///      interface that must mint its own ERC-165 map slot:
///      `keccak256(abi.encode(bytes4(0xacb1aeb6), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`
///      `= 0xe71618ea5c7977b34866901ace6d6c6585c16253798f12024e30133e7fb7b675`.
///      Verify with: `cast keccak $(cast abi-encode 'f(bytes4,bytes32)' 0xacb1aeb6 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200)`.
bytes32 constant ERC165_MAP_IGOVERNEDSAFEDIAMONDCUT_SLOT =
    0xe71618ea5c7977b34866901ace6d6c6585c16253798f12024e30133e7fb7b675;

/// @notice ERC-7201 namespaced storage for the GovernedSafeDiamondCut module.
/// @dev Pins the Safe authority, the timelock min-delay, the pending-operation schedule, and the
///      module's own append-only upgrade audit trail. APPEND-ONLY: fields are only ever added at the
///      end — never reordered, retyped, or removed — so the ERC-7201 slot stays stable across upgrades.
/// @custom:storage-location erc7201:lattice.storage.GovernedSafeDiamondCut
struct GovernedSafeDiamondCutStorage {
    /// @dev The pinned Safe multisig that is the sole authority for schedule/execute/cancel/rotation.
    address _safe;
    /// @dev Minimum timelock delay (seconds) last committed. The delay in force is `_pendingMinDelay`
    ///      once `_minDelayEffectAt` has passed (see `minDelay`). May be 0 (instant execution once
    ///      scheduled) but that defeats the timelock — see init NatSpec.
    uint256 _minDelay;
    /// @dev Schedule: operation id => ready timestamp (`eta`). 0 means "not scheduled" (never scheduled,
    ///      or cancelled); 1 (`DONE_TIMESTAMP`) means "executed"; any other value is the `eta`, "pending"
    ///      while > block.timestamp and "ready" once reached.
    mapping(bytes32 id => uint256 eta) _scheduledAt;
    /// @dev Monotonic counter of cuts applied; doubles as the latest registry version.
    uint256 _cutCount;
    /// @dev Append-only registry: version (1-indexed) => immutable {IUpgradeRegistry.CutRecord}.
    mapping(uint256 version => IUpgradeRegistry.CutRecord record) _cutRegistry;
    /// @dev Append-only set of frozen function selectors (no unfreeze).
    EnumerableSet.Bytes4Set _frozenSelectors;
    /// @dev Minimum delay requested by the latest `setMinDelay`; replaces `_minDelay` at
    ///      `_minDelayEffectAt`. APPENDED.
    uint256 _pendingMinDelay;
    /// @dev Timestamp from which `_pendingMinDelay` is the delay in force; 0 when no change was ever
    ///      requested. APPENDED.
    uint256 _minDelayEffectAt;
}

/// @title GovernedSafeDiamondCut Library
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Library that gates EIP-2535 diamond cuts behind EmergencyStop + a pinned Gnosis Safe
///         multisig AND a self-contained timelock: cuts must be scheduled, mature past `minDelay`, and
///         only then be executed. No external Governor/TimelockController is required. Delegates the
///         actual cut to `DiamondLib.diamondCut`; introduces no new cut logic.
/// @dev Three-layer pattern: this library holds all logic and the namespaced storage. The stateless
///      {GovernedSafeDiamondCut} facet delegates its external calls here. AUTHORITY MODEL: a Safe
///      collects M-of-N owner signatures off-chain, verifies the threshold on-chain in
///      `execTransaction`, then calls the diamond with `operation = Call`, so the diamond sees
///      `msg.sender == theSafe`. This module does NOT re-verify signatures — it only trusts
///      `msg.sender == $._safe`. The Safe MUST call with `operation = Call` (NEVER DelegateCall).
///      Unlike {SafeDiamondCutLib} this module does NOT expose a synchronous cut at `0x1f931c1c`; every
///      cut travels schedule -> delay -> execute, so its scheduling surface is a NEW ERC-165 interface
///      (`0xacb1aeb6`) registered at init.
library GovernedSafeDiamondCutLib {
    using EnumerableSet for EnumerableSet.Bytes4Set;

    /// @dev `_scheduledAt` marker for an executed operation (OpenZeppelin's `_DONE_TIMESTAMP`). It keeps an
    ///      executed id distinct from a never-scheduled or cancelled one (0) and blocks its replay. As in
    ///      OpenZeppelin, an `eta` that lands on a marker is misread: with a zero delay, scheduling at
    ///      timestamp 1 reads as Done (cannot execute or cancel; use another salt) and at timestamp 0 as
    ///      Unset. Neither timestamp occurs on a live chain.
    uint256 internal constant DONE_TIMESTAMP = 1;

    //*//////////////////////////////////////////////////////////////////////////
    //                           STORAGE ACCESSOR
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns a storage reference to the GovernedSafeDiamondCutStorage struct.
    function governedSafeDiamondCutStorage() internal pure returns (GovernedSafeDiamondCutStorage storage $) {
        assembly {
            $.slot := GOVERNED_SAFE_DIAMOND_CUT_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IGovernedSafeDiamondCut interface via ERC-165.
    /// @dev Writes `true` to the precomputed ERC-165 map slot (see ERC165_MAP_IGOVERNEDSAFEDIAMONDCUT_SLOT).
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IGOVERNEDSAFEDIAMONDCUT_SLOT, true)
        }
    }

    /// @notice Initializes the GovernedSafeDiamondCut module by pinning the Safe authority and timelock.
    /// @dev Validates `_safe` is non-zero and a real Safe whose `getThreshold()` meets `_minThreshold`
    ///      (which must itself be > 0). `_minDelay` MAY be 0, but a zero delay makes the timelock a
    ///      no-op (a scheduled cut is immediately executable) — set a meaningful delay in production so
    ///      the multisig's intent is publicly observable before it takes effect. There is no floor or
    ///      ceiling: a delay so large that `block.timestamp + delay` overflows makes every `scheduleCut`
    ///      and `setMinDelay` revert, permanently. Must be called inside the
    ///      preInitializer/postInitializer window. Registers the IGovernedSafeDiamondCut ERC-165 id.
    /// @param _safe The Safe multisig to pin as the cut authority.
    /// @param _minThreshold The minimum signature threshold the pinned Safe must enforce.
    /// @param _minDelay The minimum timelock delay (seconds) between schedule and execute.
    function __GovernedSafeDiamondCut_init(address _safe, uint256 _minThreshold, uint256 _minDelay) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        _validateSafe(_safe, _minThreshold);
        GovernedSafeDiamondCutStorage storage $ = governedSafeDiamondCutStorage();
        $._safe = _safe;
        $._minDelay = _minDelay;
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              SAFE AUTHORITY
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Reverts {ISafeAuthority.SafeDiamondCutUnauthorized} unless the caller is the pinned Safe.
    function _checkSafe(GovernedSafeDiamondCutStorage storage $) private view {
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
    ///         current pinned Safe. `_newSafe` is validated like the init Safe (threshold >= 1). Emits
    ///         {ISafeAuthority.SafeRotated}.
    /// @param _newSafe The new Safe to pin as the cut authority.
    function setSafe(address _newSafe) internal {
        GovernedSafeDiamondCutStorage storage $ = governedSafeDiamondCutStorage();
        _checkSafe($);
        _validateSafe(_newSafe, 1);
        address old = $._safe;
        $._safe = _newSafe;
        emit ISafeAuthority.SafeRotated(old, _newSafe);
    }

    /// @notice Requests a new minimum timelock delay (seconds). Self-administered: callable ONLY by the
    ///         pinned Safe. The change is NOT immediate: it applies to operations scheduled from
    ///         `effectAt = block.timestamp + max(current, _newDelay)`, so lowering the delay waits out the
    ///         delay it replaces and the Safe cannot zero the delay and push a cut through in one
    ///         transaction. A new request replaces any pending one (re-requesting the current delay
    ///         withdraws it). Emits {IGovernedSafeDiamondCut.MinDelayChangeScheduled}.
    /// @dev Pending-delay pattern after OpenZeppelin's AccessManager. Not gated on `msg.sender ==
    ///      address(this)` like OpenZeppelin's TimelockController `updateDelay`: in a composed diamond
    ///      `address(this)` can be reachable through other facets. Reverts on overflow of `effectAt`.
    /// @param _newDelay The new minimum delay (seconds); may be 0 (see init NatSpec on the risk).
    function setMinDelay(uint256 _newDelay) internal {
        GovernedSafeDiamondCutStorage storage $ = governedSafeDiamondCutStorage();
        _checkSafe($);
        uint256 current = _minDelayInForce($);
        uint256 effectAt = block.timestamp + (_newDelay > current ? _newDelay : current);
        $._minDelay = current;
        $._pendingMinDelay = _newDelay;
        $._minDelayEffectAt = effectAt;
        emit IGovernedSafeDiamondCut.MinDelayChangeScheduled(current, _newDelay, effectAt);
    }

    /// @dev The delay in force now: the requested delay once its `effectAt` has passed, else the last
    ///      committed one.
    function _minDelayInForce(GovernedSafeDiamondCutStorage storage $) private view returns (uint256) {
        uint256 effectAt = $._minDelayEffectAt;
        if (effectAt != 0 && effectAt <= block.timestamp) return $._pendingMinDelay;
        return $._minDelay;
    }

    /// @notice Returns the currently pinned Safe authority.
    function safe() internal view returns (address) {
        return governedSafeDiamondCutStorage()._safe;
    }

    /// @notice Returns the minimum timelock delay (seconds) in force now. A change requested through
    ///         {setMinDelay} is reflected only from its `effectAt`.
    function minDelay() internal view returns (uint256) {
        return _minDelayInForce(governedSafeDiamondCutStorage());
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            TIMELOCKED CUT
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Computes the operation id binding the full cut payload plus a disambiguating salt.
    function _operationId(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata, bytes32 _salt)
        private
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(_diamondCut, _init, _calldata, _salt));
    }

    /// @dev Classifies a stored `_scheduledAt` value: 0 is Unset (never scheduled or cancelled),
    ///      `DONE_TIMESTAMP` is Done, and any other value is Waiting until its `eta`, then Ready.
    function _state(uint256 _eta) private view returns (ITimelockController.OperationState) {
        if (_eta == 0) return ITimelockController.OperationState.Unset;
        if (_eta == DONE_TIMESTAMP) return ITimelockController.OperationState.Done;
        if (_eta > block.timestamp) return ITimelockController.OperationState.Waiting;
        return ITimelockController.OperationState.Ready;
    }

    /// @notice Schedules a cut for later execution. Reverts if emergency-stopped, then requires the
    ///         caller to be the pinned Safe, then stores `eta = block.timestamp + minDelay` under the
    ///         operation id (checked: a delay that would overflow reverts rather than wrap `eta` into the
    ///         past). Reverts {IGovernedSafeDiamondCut.CutAlreadyScheduled} if the id is already
    ///         scheduled or was executed; re-running an executed cut takes a new salt. Does NOT validate
    ///         frozen selectors here — that check fires at execution time (against the then-current
    ///         frozen set), matching the synchronous path's ordering.
    /// @param _diamondCut The facet addresses, cut actions, and function selectors.
    /// @param _init The address delegatecalled after the cut (address(0) to skip).
    /// @param _calldata The calldata passed to `_init`.
    /// @param _salt A caller-chosen salt disambiguating otherwise-identical payloads.
    /// @return id The operation id.
    function scheduleCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata, bytes32 _salt)
        internal
        returns (bytes32 id)
    {
        EmergencyStopLib.checkNotStopped();
        GovernedSafeDiamondCutStorage storage $ = governedSafeDiamondCutStorage();
        _checkSafe($);

        id = _operationId(_diamondCut, _init, _calldata, _salt);
        if ($._scheduledAt[id] != 0) {
            revert IGovernedSafeDiamondCut.CutAlreadyScheduled(id);
        }

        uint256 eta = block.timestamp + _minDelayInForce($);
        $._scheduledAt[id] = eta;

        emit IGovernedSafeDiamondCut.CutScheduled(id, _diamondCut.length, _init, _salt, eta);
    }

    /// @notice Executes a previously-scheduled, matured cut. Reverts if emergency-stopped, requires the
    ///         caller to be the pinned Safe, re-derives the id and requires it scheduled and matured
    ///         (an executed id reverts {IGovernedSafeDiamondCut.CutNotScheduled}), marks it done, enforces
    ///         the frozen-selector guard, applies the cut, and records it in the append-only registry.
    ///         Emits {IGovernedSafeDiamondCut.CutExecuted}.
    /// @param _diamondCut The facet addresses, cut actions, and function selectors (must match schedule).
    /// @param _init The address delegatecalled after the cut (must match schedule).
    /// @param _calldata The calldata passed to `_init` (must match schedule).
    /// @param _salt The salt used at schedule time.
    function executeCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata, bytes32 _salt)
        internal
    {
        EmergencyStopLib.checkNotStopped();
        GovernedSafeDiamondCutStorage storage $ = governedSafeDiamondCutStorage();
        _checkSafe($);

        bytes32 id = _operationId(_diamondCut, _init, _calldata, _salt);
        uint256 eta = $._scheduledAt[id];
        ITimelockController.OperationState state = _state(eta);
        if (state == ITimelockController.OperationState.Waiting) {
            revert IGovernedSafeDiamondCut.CutNotReady(id, eta);
        }
        if (state != ITimelockController.OperationState.Ready) revert IGovernedSafeDiamondCut.CutNotScheduled(id);

        // Effects before interactions: mark the operation done BEFORE the external cut so neither a
        // re-entrant nor a later executeCut with the same id can replay it. Defense-in-depth — the
        // _checkSafe gate already blocks re-entry, since an init delegatecall runs as the diamond
        // (msg.sender != the Safe).
        $._scheduledAt[id] = DONE_TIMESTAMP;

        // Frozen-selector protection BEFORE applying the cut, against the CURRENT frozen set.
        _enforceNotFrozen($, _diamondCut);

        // Apply the cut via diamond-lib (untouched core).
        DiamondLib.diamondCut(_diamondCut, _init, _calldata);

        uint256 version;
        unchecked {
            version = ++$._cutCount;
        }

        bytes32 cutHash = keccak256(abi.encode(_diamondCut, _init, _calldata));
        $._cutRegistry[version] = IUpgradeRegistry.CutRecord({
            cutHash: cutHash,
            executor: msg.sender,
            executedAt: uint48(block.timestamp),
            facetCutCount: uint32(_diamondCut.length),
            init: _init
        });

        emit IGovernedSafeDiamondCut.CutExecuted(id);
        emit ISafeDiamondCut.UpgradeExecuted(msg.sender, _diamondCut.length, _init);
        emit IUpgradeRegistry.CutRecorded(version, cutHash, msg.sender);
    }

    /// @notice Cancels a scheduled, not-yet-executed operation (pending or ready). Requires the caller to
    ///         be the pinned Safe. Reverts {IGovernedSafeDiamondCut.CutNotScheduled} if the id is not
    ///         currently scheduled, including an executed id. Emits {IGovernedSafeDiamondCut.CutCancelled}.
    /// @param _id The operation id to cancel.
    function cancelCut(bytes32 _id) internal {
        GovernedSafeDiamondCutStorage storage $ = governedSafeDiamondCutStorage();
        _checkSafe($);
        ITimelockController.OperationState state = _state($._scheduledAt[_id]);
        if (state == ITimelockController.OperationState.Unset || state == ITimelockController.OperationState.Done) {
            revert IGovernedSafeDiamondCut.CutNotScheduled(_id);
        }
        delete $._scheduledAt[_id];
        emit IGovernedSafeDiamondCut.CutCancelled(_id);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       EMERGENCY REMOVAL-ONLY CUT
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Zero-delay, REMOVAL-ONLY escape hatch: lets a guardian instantly unbind a compromised or
    ///         buggy facet's selectors WITHOUT scheduling and WITHOUT the Safe — and, by design, even
    ///         while the normal cut path is halted by EmergencyStop. Removal-only, frozen-protected, no
    ///         init delegatecall, and never `scheduleCut`/`executeCut` or a stop-recovery selector
    ///         (`emergencyResume`, `removeGuardian`, `revokeRole`; reverts
    ///         {IEmergencyCut.EmergencyCutEntrypointProtected} even with an empty frozen set). Recorded in
    ///         the SAME append-only registry and emits {IEmergencyCut.EmergencyCutExecuted}. Mirrors
    ///         {GovernedDiamondCutLib.emergencyRemoveCut}.
    /// @dev Liveness: a guardian can still trip the stop, which blocks `scheduleCut` and `executeCut`, and
    ///      can trip it again between the two. A stop only delays: a ready operation never expires, and
    ///      since the recovery selectors cannot be removed, the `DEFAULT_ADMIN_ROLE` holder can always
    ///      revoke a hostile guardian, resume, and let the Safe cut again to restore anything removed.
    ///      This assumes a live admin; with the admin role renounced a stop is permanent.
    /// @param _cuts The facet cuts to apply; every entry MUST be a `Remove` (facetAddress == address(0)).
    function emergencyRemoveCut(FacetCut[] calldata _cuts) internal {
        AccessControlLib.checkRole(EMERGENCY_GUARDIAN_ROLE);

        // NOTE: `EmergencyStopLib.checkNotStopped()` is DELIBERATELY NOT called here — panic button.

        GovernedSafeDiamondCutStorage storage $ = governedSafeDiamondCutStorage();

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
                bytes4 selector = selectors[j];
                if (
                    selector == IGovernedSafeDiamondCut.scheduleCut.selector
                        || selector == IGovernedSafeDiamondCut.executeCut.selector
                        || EmergencyStopLib.isRecoverySelector(selector)
                ) {
                    revert IEmergencyCut.EmergencyCutEntrypointProtected(selector);
                }
                if (frozen.contains(selector)) {
                    revert IFrozenSelectors.FrozenSelectorProtected(selector);
                }
            }
            unchecked {
                selectorCount += selectorsLength;
            }
        }

        bytes calldata emptyCalldata = msg.data[:0];
        DiamondLib.diamondCut(_cuts, address(0), emptyCalldata);

        uint256 version;
        unchecked {
            version = ++$._cutCount;
        }

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

    /// @notice Permanently freezes `_selectors`. Gated to the pinned Safe. Append-only; no unfreeze.
    /// @param _selectors The function selectors to freeze.
    function freezeSelectors(bytes4[] calldata _selectors) internal {
        GovernedSafeDiamondCutStorage storage $ = governedSafeDiamondCutStorage();
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
    function _enforceNotFrozen(GovernedSafeDiamondCutStorage storage $, FacetCut[] calldata _diamondCut) private view {
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
    //                          TIMELOCK VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the ready timestamp (`eta`) of an operation: 0 if never scheduled or cancelled, and
    ///         `DONE_TIMESTAMP` (1) once executed.
    /// @param _id The operation id to query.
    function getTimestamp(bytes32 _id) internal view returns (uint256) {
        return governedSafeDiamondCutStorage()._scheduledAt[_id];
    }

    /// @notice Returns whether `_id` is scheduled but not yet matured (eta in the future).
    /// @param _id The operation id to query.
    function isOperationPending(bytes32 _id) internal view returns (bool) {
        return _state(governedSafeDiamondCutStorage()._scheduledAt[_id]) == ITimelockController.OperationState.Waiting;
    }

    /// @notice Returns whether `_id` is scheduled and matured (eta reached, not yet executed).
    /// @param _id The operation id to query.
    function isOperationReady(bytes32 _id) internal view returns (bool) {
        return _state(governedSafeDiamondCutStorage()._scheduledAt[_id]) == ITimelockController.OperationState.Ready;
    }

    /// @notice Returns whether `_id` has been executed. Never-scheduled and cancelled ids report false,
    ///         matching OpenZeppelin's TimelockController `Done` state.
    /// @param _id The operation id to query.
    function isOperationDone(bytes32 _id) internal view returns (bool) {
        return governedSafeDiamondCutStorage()._scheduledAt[_id] == DONE_TIMESTAMP;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          REGISTRY VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the number of cuts applied so far (also the latest registry version).
    function cutCount() internal view returns (uint256) {
        return governedSafeDiamondCutStorage()._cutCount;
    }

    /// @notice Returns the immutable audit record for a given registry `version`.
    /// @param _version The registry version to look up.
    function getCutRecord(uint256 _version) internal view returns (IUpgradeRegistry.CutRecord memory) {
        return governedSafeDiamondCutStorage()._cutRegistry[_version];
    }

    /// @notice Returns whether `_selector` is in the frozen set (protected from Replace/Remove).
    /// @param _selector The function selector to query.
    function isSelectorFrozen(bytes4 _selector) internal view returns (bool) {
        return governedSafeDiamondCutStorage()._frozenSelectors.contains(_selector);
    }

    /// @notice Returns the full set of frozen selectors.
    function frozenSelectors() internal view returns (bytes4[] memory) {
        return governedSafeDiamondCutStorage()._frozenSelectors.values();
    }

    /// @notice Pre-flight simulation of the frozen-selector guard against the current set, no mutation.
    /// @param _cuts The candidate facet cuts to simulate.
    /// @return ok `true` if no `Replace`/`Remove` in `_cuts` targets a frozen selector.
    /// @return offendingSelector The first frozen selector a `Replace`/`Remove` would touch (zero if `ok`).
    function previewCut(FacetCut[] calldata _cuts) internal view returns (bool ok, bytes4 offendingSelector) {
        EnumerableSet.Bytes4Set storage frozen = governedSafeDiamondCutStorage()._frozenSelectors;
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
    /// @param _interfaceId The ERC-165 interface identifier to check.
    function verifyInterfaceRegistered(bytes4 _interfaceId) internal view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

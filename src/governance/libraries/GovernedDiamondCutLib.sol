// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib, FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IFrozenSelectors} from "@lattice/interfaces/IFrozenSelectors.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/IGovernedDiamondCut.sol";
import {IUpgradeRegistry} from "@lattice/interfaces/IUpgradeRegistry.sol";
import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {EnumerableSet} from "@lattice/utils/libraries/EnumerableSet.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.GovernedDiamondCut")) - 1)) & ~bytes32(uint256(0xff))`.
///      Verify with: `cast index-erc7201 "lattice.storage.GovernedDiamondCut"`.
bytes32 constant GOVERNED_DIAMOND_CUT_STORAGE_SLOT = 0x9a46da229426897da8e8df190858c430564a988584235445fd229e2bef8a8700;

/// @dev ERC-165 storage location (same across all Lattice/diamond-lib modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant GOVERNED_DIAMOND_CUT_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev `type(IGovernedDiamondCut).interfaceId == 0x1f931c1c`, identical to `IDiamondCut` (the
///      interface exposes only `diamondCut`). Its ERC-165 map slot is therefore
///      `keccak256(abi.encode(bytes4(0x1f931c1c), ERC165_STORAGE_LOCATION))`
///      `= 0xa0f80413692945aab97c6ef0328381ebb94e4b17a84d11ebf6b61f73435b6d7e`, which is exactly
///      `DiamondLib`'s `ERC165_MAP_ICUT_SLOT`. We do NOT mint a separate constant or register a
///      second time: `DiamondLib.registerInterface()` already sets this flag in any 2535 deployment.
bytes32 constant ERC165_MAP_ICUT_SLOT = 0xa0f80413692945aab97c6ef0328381ebb94e4b17a84d11ebf6b61f73435b6d7e;

/// @dev Role required to execute a governed cut. Granted ONLY to `address(this)` at init, so the
///      sole legitimate caller is a timelock relaying a passed governance proposal back into the
///      diamond. `keccak256("UPGRADE_EXECUTOR_ROLE")`.
bytes32 constant UPGRADE_EXECUTOR_ROLE = keccak256("UPGRADE_EXECUTOR_ROLE");

/// @notice ERC-7201 namespaced storage for the GovernedDiamondCut module.
/// @dev Authority itself lives in AccessControl + EmergencyStop storage; this slot holds the
///      module's own append-only upgrade audit trail. APPEND-ONLY: fields are only ever added at
///      the end — never reordered, retyped, or removed — so the ERC-7201 slot stays stable across
///      upgrades. The slot constant is unchanged because the namespace string is unchanged.
/// @custom:storage-location erc7201:lattice.storage.GovernedDiamondCut
struct GovernedDiamondCutStorage {
    /// @dev Monotonic counter of governed cuts applied; doubles as the latest registry version.
    ///      The value assigned to a cut (post-increment) IS that cut's `version`.
    uint256 _cutCount;
    /// @dev Append-only registry: version (1-indexed) => immutable {IUpgradeRegistry.CutRecord}.
    ///      Written once per successful cut and never mutated thereafter.
    mapping(uint256 version => IUpgradeRegistry.CutRecord record) _cutRegistry;
    /// @dev Append-only set of frozen function selectors. A selector in this set can never be the
    ///      target of a `Replace` or `Remove` in any future governed cut (the guard checks this set
    ///      BEFORE delegating to diamond-lib). There is deliberately no unfreeze. APPENDED at the end
    ///      of this struct — the ERC-7201 slot is unchanged because the namespace string is unchanged.
    EnumerableSet.Bytes4Set _frozenSelectors;
}

/// @title GovernedDiamondCut Library
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Library that gates EIP-2535 diamond cuts behind EmergencyStop + a single-holder role,
///         then delegates the actual cut to `DiamondLib.diamondCut`. Introduces no new cut logic.
/// @dev Three-layer pattern: this library holds all logic and the namespaced storage. The stateless
///      {GovernedDiamondCut} facet delegates its single external call here.
library GovernedDiamondCutLib {
    using EnumerableSet for EnumerableSet.Bytes4Set;

    //*//////////////////////////////////////////////////////////////////////////
    //                           STORAGE ACCESSOR
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns a storage reference to the GovernedDiamondCutStorage struct.
    function governedDiamondCutStorage() internal pure returns (GovernedDiamondCutStorage storage $) {
        assembly {
            $.slot := GOVERNED_DIAMOND_CUT_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the GovernedDiamondCut module.
    /// @dev Grants UPGRADE_EXECUTOR_ROLE to `address(this)` so only a timelock-relayed governance
    ///      call can pass the role gate. Must be called inside the preInitializer/postInitializer
    ///      window; AccessControl must already be initialized (the role write targets its storage).
    ///      Does NOT register an ERC-165 interface: `0x1f931c1c` is already registered by
    ///      `DiamondLib.registerInterface()` (see the ERC165_MAP_ICUT_SLOT note above).
    function __GovernedDiamondCut_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        AccessControlLib._grantRole(UPGRADE_EXECUTOR_ROLE, address(this));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            GOVERNED CUT
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Guarded diamond cut: reverts if emergency-stopped, then requires the caller to hold
    ///         UPGRADE_EXECUTOR_ROLE, then delegates to `DiamondLib.diamondCut`. Introduces no new
    ///         cut logic — all selector-collision, immutable-function, bytecode-existence, and
    ///         init-delegatecall handling is diamond-lib's.
    /// @param _diamondCut The facet addresses, cut actions, and function selectors.
    /// @param _init The address delegatecalled after the cut (address(0) to skip).
    /// @param _calldata The calldata passed to `_init`.
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) internal {
        // 1) Outer guard: a guardian can halt ALL upgrades without a governance round.
        EmergencyStopLib.checkNotStopped();
        // 2) Authority: only address(this) holds the role, so only a timelock-relayed governance
        //    proposal can reach here. Reverts AccessControlUnauthorizedAccount(caller, role).
        AccessControlLib.checkRole(UPGRADE_EXECUTOR_ROLE);

        GovernedDiamondCutStorage storage $ = governedDiamondCutStorage();

        // 3) Protection: reject any Replace/Remove that targets a frozen selector BEFORE applying the
        //    cut. This prevents a (mistaken or malicious) cut from removing/replacing load-bearing
        //    selectors (e.g. the loupe or the cut path itself). Add actions are unaffected.
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

        emit IGovernedDiamondCut.UpgradeExecuted(msg.sender, _diamondCut.length, _init);
        emit IUpgradeRegistry.CutRecorded(version, cutHash, msg.sender);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           FROZEN SELECTORS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Permanently freezes `_selectors`: each becomes ineligible to be the target of a
    ///         `Replace`/`Remove` in any future governed cut. Gated behind UPGRADE_EXECUTOR_ROLE — the
    ///         same single-holder role that gates `diamondCut` — so only a timelock-relayed governance
    ///         proposal can freeze. Append-only: already-frozen selectors are idempotent no-ops, and
    ///         there is no unfreeze.
    /// @param _selectors The function selectors to freeze.
    function freezeSelectors(bytes4[] calldata _selectors) internal {
        AccessControlLib.checkRole(UPGRADE_EXECUTOR_ROLE);
        EnumerableSet.Bytes4Set storage frozen = governedDiamondCutStorage()._frozenSelectors;
        uint256 length = _selectors.length;
        for (uint256 i; i < length; ++i) {
            frozen.add(_selectors[i]);
        }
        emit IFrozenSelectors.SelectorsFrozen(msg.sender, _selectors);
    }

    /// @dev Reverts {IFrozenSelectors.FrozenSelectorProtected} if any `Replace`/`Remove` action in
    ///      `_diamondCut` targets a frozen selector. `Add` actions are never inspected. This is the
    ///      shared core of both the guarded `diamondCut` (reverting form) and `previewCut` (the
    ///      reverting form is reused via a try/catch-free direct read in `previewCut`).
    function _enforceNotFrozen(GovernedDiamondCutStorage storage $, FacetCut[] calldata _diamondCut) private view {
        EnumerableSet.Bytes4Set storage frozen = $._frozenSelectors;
        uint256 cutsLength = _diamondCut.length;
        for (uint256 i; i < cutsLength; ++i) {
            FacetCutAction action = _diamondCut[i].action;
            // Add never touches an existing selector binding, so it can never harm a frozen one.
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

    /// @notice Returns the number of governed cuts applied so far (also the latest registry version).
    function cutCount() internal view returns (uint256) {
        return governedDiamondCutStorage()._cutCount;
    }

    /// @notice Returns the immutable audit record for a given registry `version`.
    /// @dev Versions are 1-indexed; an unwritten version (0, or any value > {cutCount}) returns a
    ///      zero-valued {IUpgradeRegistry.CutRecord}.
    /// @param _version The registry version to look up.
    function getCutRecord(uint256 _version) internal view returns (IUpgradeRegistry.CutRecord memory) {
        return governedDiamondCutStorage()._cutRegistry[_version];
    }

    /// @notice Returns whether `_selector` is in the frozen set (protected from Replace/Remove).
    /// @param _selector The function selector to query.
    function isSelectorFrozen(bytes4 _selector) internal view returns (bool) {
        return governedDiamondCutStorage()._frozenSelectors.contains(_selector);
    }

    /// @notice Returns the full set of frozen selectors.
    function frozenSelectors() internal view returns (bytes4[] memory) {
        return governedDiamondCutStorage()._frozenSelectors.values();
    }

    /// @notice Pre-flight simulation of the frozen-selector guard against the current set, with no
    ///         state change. Mirrors exactly the check the guarded `diamondCut` performs before
    ///         applying: only `Replace`/`Remove` actions are inspected. Pure read of the frozen set —
    ///         it does NOT re-implement diamond-lib's collision/immutable/bytecode checks (those fire
    ///         at execution).
    /// @param _cuts The candidate facet cuts to simulate.
    /// @return ok `true` if no `Replace`/`Remove` in `_cuts` targets a frozen selector.
    /// @return offendingSelector The first frozen selector a `Replace`/`Remove` would touch (zero if `ok`).
    function previewCut(FacetCut[] calldata _cuts) internal view returns (bool ok, bytes4 offendingSelector) {
        EnumerableSet.Bytes4Set storage frozen = governedDiamondCutStorage()._frozenSelectors;
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
    /// @dev Thin wrapper over the shared ERC-165 support read so an upgrade workflow can confirm an
    ///      expected interface is still/now advertised after a cut. Equivalent to `supportsInterface`.
    /// @param _interfaceId The ERC-165 interface identifier to check.
    function verifyInterfaceRegistered(bytes4 _interfaceId) internal view returns (bool) {
        return ERC165Lib.supportsInterface(_interfaceId);
    }
}

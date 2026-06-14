// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib, FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/IGovernedDiamondCut.sol";
import {IUpgradeRegistry} from "@lattice/interfaces/IUpgradeRegistry.sol";
import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";

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
}

/// @title GovernedDiamondCut Library
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Library that gates EIP-2535 diamond cuts behind EmergencyStop + a single-holder role,
///         then delegates the actual cut to `DiamondLib.diamondCut`. Introduces no new cut logic.
/// @dev Three-layer pattern: this library holds all logic and the namespaced storage. The stateless
///      {GovernedDiamondCut} facet delegates its single external call here.
library GovernedDiamondCutLib {
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
        // 3) Apply the cut via diamond-lib (untouched core). If it reverts (e.g. selector clash),
        //    execution never reaches the registry write below — so a failed cut records NOTHING.
        DiamondLib.diamondCut(_diamondCut, _init, _calldata);

        GovernedDiamondCutStorage storage $ = governedDiamondCutStorage();
        uint256 version;
        unchecked {
            // Post-increment value is this cut's 1-indexed version (registry is 1-indexed).
            version = ++$._cutCount;
        }

        // 4) Append the immutable audit record under `version` (append-only registry).
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
}

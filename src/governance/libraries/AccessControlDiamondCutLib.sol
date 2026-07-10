// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib, FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControlDiamondCut} from "@lattice/interfaces/governance/IAccessControlDiamondCut.sol";
import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";

/// @dev `type(IAccessControlDiamondCut).interfaceId == 0x1f931c1c`, identical to `IDiamondCut` (the
///      interface exposes only `diamondCut`). Its ERC-165 map slot is therefore
///      `keccak256(abi.encode(bytes4(0x1f931c1c), ERC165_STORAGE_LOCATION))`
///      `= 0xa0f80413692945aab97c6ef0328381ebb94e4b17a84d11ebf6b61f73435b6d7e`, which is exactly
///      `DiamondLib`'s `ERC165_MAP_ICUT_SLOT`. We do NOT mint a separate constant or register a
///      second time: `DiamondLib.registerInterface()` already sets this flag in any 2535 deployment.
bytes32 constant ERC165_MAP_IACCESSCONTROLDIAMONDCUT_SLOT =
    0xa0f80413692945aab97c6ef0328381ebb94e4b17a84d11ebf6b61f73435b6d7e;

/// @title AccessControlDiamondCut Library
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Library that gates EIP-2535 diamond cuts behind EmergencyStop + `DEFAULT_ADMIN_ROLE`,
///         then delegates the actual cut to `DiamondLib.diamondCut`. Introduces no new cut logic —
///         all selector-collision, immutable-function, bytecode-existence, and init-delegatecall
///         handling is diamond-lib's.
/// @dev Three-layer pattern: the stateless {AccessControlDiamondCut} facet delegates its single
///      external call here. DELIBERATELY STATELESS — authority lives entirely in AccessControl (+
///      EmergencyStop) storage, so there is no `__*_init` and no new ERC-7201 namespace: the host
///      recipe's existing init (which seeds `DEFAULT_ADMIN_ROLE`) is the only prerequisite. Recipes
///      wanting an on-chain upgrade registry, frozen selectors, or a guardian escape hatch should
///      cut {GovernedDiamondCut} instead.
library AccessControlDiamondCutLib {
    /// @notice Guarded diamond cut: reverts if emergency-stopped, then requires the caller to hold
    ///         `DEFAULT_ADMIN_ROLE`, then delegates to `DiamondLib.diamondCut`.
    /// @dev The stop gate runs FIRST so a guardian halt blocks upgrades in recipes that also cut
    ///      {EmergencyStop}; in recipes without it the flag storage is default-false and the check
    ///      is a no-op. Reverts `AccessControlUnauthorizedAccount(caller, DEFAULT_ADMIN_ROLE)` for
    ///      any non-admin caller.
    /// @param _diamondCut The facet addresses, cut actions, and function selectors.
    /// @param _init The address delegatecalled after the cut (address(0) to skip).
    /// @param _calldata The calldata passed to `_init`.
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) internal {
        EmergencyStopLib.checkNotStopped();
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        DiamondLib.diamondCut(_diamondCut, _init, _calldata);
        emit IAccessControlDiamondCut.AdminUpgradeExecuted(msg.sender, _diamondCut.length, _init);
    }
}

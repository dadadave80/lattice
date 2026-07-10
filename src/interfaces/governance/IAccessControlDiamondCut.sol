// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";

/// @title IAccessControlDiamondCut
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice External interface for the admin-gated diamond-cut facet. Exposes the EIP-2535
///         `diamondCut` function at the canonical selector `0x1f931c1c` so it transparently
///         replaces diamond-lib's owner-gated `DiamondCutFacet` in an AccessControl deployment —
///         ONE authority model: the module admin (`DEFAULT_ADMIN_ROLE`) is also the upgrade
///         authority, no parallel Ownable owner.
/// @dev The single function makes `type(IAccessControlDiamondCut).interfaceId == 0x1f931c1c`, equal
///      to `IDiamondCut`. ERC-165 support for `0x1f931c1c` is therefore already registered by
///      `DiamondLib.registerInterface()`; this module does not mint a separate ERC-165 slot.
interface IAccessControlDiamondCut {
    /// @dev Emitted after an admin-gated cut is authorized and applied. Mirrors that the guard
    ///      (emergency-stop, then DEFAULT_ADMIN_ROLE) passed before delegating to DiamondLib.
    /// @param executor The caller that passed the role gate (a DEFAULT_ADMIN_ROLE holder).
    /// @param facetCutCount The number of FacetCut entries applied.
    /// @param init The init address delegatecalled after the cut (address(0) if none).
    event AdminUpgradeExecuted(address indexed executor, uint256 facetCutCount, address indexed init);

    /// @notice Add/replace/remove any number of functions and optionally execute a function with
    ///         delegatecall — but only when not emergency-stopped and the caller holds
    ///         `DEFAULT_ADMIN_ROLE`. The host recipe's init seeds that role (usually to its `admin`
    ///         parameter), so the module admin is the upgrade authority — no separate Ownable owner.
    /// @param _diamondCut The facet addresses, cut actions, and function selectors.
    /// @param _init The address of the contract or facet to delegatecall after the cut (0 to skip).
    /// @param _calldata The calldata passed to `_init`.
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external payable;
}

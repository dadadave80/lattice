// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";

/// @title IGovernedDiamondCut
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice External interface for the governance-gated diamond-cut facet. Exposes the EIP-2535
///         `diamondCut` function at the canonical selector `0x1f931c1c` so it transparently
///         replaces diamond-lib's owner-gated `DiamondCutFacet` in a governed deployment.
/// @dev The single function makes `type(IGovernedDiamondCut).interfaceId == 0x1f931c1c`, equal to
///      `IDiamondCut`. ERC-165 support for `0x1f931c1c` is therefore already registered by
///      `DiamondLib.registerInterface()`; this module does not mint a separate ERC-165 slot.
interface IGovernedDiamondCut {
    /// @dev Emitted after a governed cut is authorized and applied. Mirrors that the guard
    ///      (emergency-stop, then UPGRADE_EXECUTOR_ROLE) passed before delegating to DiamondLib.
    /// @param executor The caller that passed the role gate (the timelock relaying a passed proposal).
    /// @param facetCutCount The number of FacetCut entries applied.
    /// @param init The init address delegatecalled after the cut (address(0) if none).
    event UpgradeExecuted(address indexed executor, uint256 facetCutCount, address indexed init);

    /// @dev Thrown when a caller without UPGRADE_EXECUTOR_ROLE attempts a cut.
    /// @param caller The unauthorized caller.
    error GovernedDiamondCutUnauthorized(address caller);

    /// @notice Add/replace/remove any number of functions and optionally execute a function with
    ///         delegatecall — but only when not emergency-stopped and the caller holds
    ///         UPGRADE_EXECUTOR_ROLE. That role is granted solely to `address(this)` at init AND is
    ///         pinned to administer itself, so `DEFAULT_ADMIN_ROLE` cannot grant it out-of-band: the
    ///         only way to reach this function is a timelock-relayed passed governance proposal.
    /// @param _diamondCut The facet addresses, cut actions, and function selectors.
    /// @param _init The address of the contract or facet to delegatecall after the cut (0 to skip).
    /// @param _calldata The calldata passed to `_init`.
    function diamondCut(FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external payable;
}

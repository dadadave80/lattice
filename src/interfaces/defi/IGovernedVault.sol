// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IGovernedVault
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice First-party surface unique to the self-governed ERC-4626 vault facet: the governor ballot-nonce
///         accessor. Every other selector the {GovernedVault} facet exposes belongs to an existing interface
///         (IERC20, IERC4626, IVaultCore, IVotes, IGovernor, ITimelockController) whose id is registered by the
///         corresponding module.
/// @dev The governor's `castVoteBySig` uses a DEDICATED nonce space, separate from the ERC-20 `delegateBySig`
///      nonce (which stays on {NoncesLib}). On a single diamond both signature paths would otherwise draw from
///      one shared {NoncesLib} counter, so a delegation would silently invalidate a pending vote signature (and
///      vice versa). Keeping the two namespaces distinct preserves the isolation the canonical
///      separate-contract OZ deployment has for free.
interface IGovernedVault {
    /// @notice The next unused governor-ballot nonce for `voter` (consumed by `castVoteBySig`). Distinct from the
    ///         ERC-20 delegation nonce returned elsewhere.
    function ballotNonce(address voter) external view returns (uint256);
}

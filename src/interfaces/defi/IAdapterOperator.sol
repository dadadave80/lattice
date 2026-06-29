// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IAdapterOperator
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Sidecar interface carrying the authorized-operator surface of every Lattice protocol
///         adapter. Kept SEPARATE from `IProtocolAdapter` on purpose: `IProtocolAdapter` has a
///         pinned ERC-165 interfaceId (`0x8f7783e6`) that the adapters register, and adding external
///         functions to it would change that id. The operator setter/getter therefore live here so
///         the `IProtocolAdapter` id stays frozen while adapters still expose a typed operator ABI.
/// @dev The operator is the single address allowed to call an adapter's `deploy`/`withdraw`/`harvest`
///      trio (in the live system, the StrategyManager). It is unset (zero) until wired, so those
///      three entrypoints revert until an admin authorizes the manager — a secure-by-default posture.
///      Wide pragma so older-compiler consumers can import the ABI.
interface IAdapterOperator {
    /// @notice Sets the authorized operator permitted to call `deploy`/`withdraw`/`harvest`.
    /// @dev Admin-gated (`DEFAULT_ADMIN_ROLE`). Rejects `address(0)`; emits
    ///      `IProtocolAdapter.OperatorSet`.
    /// @param operator_ The new operator (typically the StrategyManager diamond).
    function setOperator(address operator_) external;

    /// @notice Returns the authorized operator (zero until wired).
    function operator() external view returns (address);
}

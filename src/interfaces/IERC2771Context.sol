// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC2771Context
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/metatx/ERC2771Context.sol)
/// @notice Interface for ERC-2771 meta-transaction support.
///         Allows a trusted forwarder to relay signed transactions on behalf of original signers.
interface IERC2771Context {
    /// @notice Emitted when the trusted forwarder is updated.
    event TrustedForwarderUpdated(address indexed forwarder);

    /// @notice Returns whether the given address is the trusted forwarder.
    /// @param forwarder The address to check.
    /// @return bool True if the address is the trusted forwarder.
    function isTrustedForwarder(address forwarder) external view returns (bool);

    /// @notice Returns the current trusted forwarder address.
    /// @return address The trusted forwarder.
    function trustedForwarder() external view returns (address);

    /// @notice Sets the trusted forwarder address.
    /// @param forwarder The new trusted forwarder address (zero address disables forwarding).
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE.
    function setTrustedForwarder(address forwarder) external;
}

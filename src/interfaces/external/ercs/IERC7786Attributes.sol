// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IERC7786Attributes
/// @author Vendored from OpenZeppelin community-contracts (commit f7e5f08, MIT)
///         (https://github.com/OpenZeppelin/openzeppelin-community-contracts/blob/f7e5f08e8fd42023084eb41f4a992d7be897b915/contracts/interfaces/IERC7786Attributes.sol).
/// @notice Non-standardized ERC-7786 attribute selectors. `requestRelay` carries relay gas parameters for
///         gateways (e.g. Wormhole) that charge for delivery. The selector `0x4cbb573a` is used as the
///         attribute key. This is NOT yet a finalized standard — treat as unstable.
interface IERC7786Attributes {
    /// @notice Relay-request attribute: deliver with `value` + `gasLimit`, refunding to `refundRecipient`.
    function requestRelay(uint256 value, uint256 gasLimit, address refundRecipient) external;
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IBridgeFungible
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin `BridgeFungible` v5.6.1 (https://github.com/OpenZeppelin/openzeppelin-contracts)
///         (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/crosschain/bridges/abstract/BridgeFungible.sol)
/// @notice Shared events, errors, and ABI for the fungible cross-chain bridge facets — {BridgeERC20}
///         (custody) and {BridgeERC7802} (mint/burn). Both register this interface for ERC-165 discovery;
///         they differ only in their ERC-7201 storage namespace and the lock/unlock token operation, so a
///         given Diamond mounts at most one of them (they share the `crosschainTransfer`/handler selectors).
/// @dev Each bridge is an {IERC7786MessageHandler} registered under a shared fungible-bridge tag on a
///      co-mounted {CrosschainLink} facet; `crosschainTransfer` sends through that facet's link registry.
interface IBridgeFungible {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when a crosschain transfer is sent. `to` is a full ERC-7930 interoperable address.
    event CrosschainFungibleTransferSent(bytes32 indexed sendId, address indexed from, bytes to, uint256 amount);

    /// @notice Emitted when an inbound crosschain transfer is credited to `to` on this chain.
    event CrosschainFungibleTransferReceived(bytes32 indexed receiveId, bytes from, address indexed to, uint256 amount);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice The bridged token configured at init was the zero address.
    error BridgeZeroToken();

    /// @notice An ERC-20 `transfer`/`transferFrom` failed (reverted or returned non-true).
    error BridgeTransferFailed(address token);

    /// @notice The inbound destination address was not a 20-byte EVM address.
    error BridgeInvalidRecipient();

    /// @notice `processMessage` was called by something other than the Diamond's own authenticated
    ///         `receiveMessage` dispatch (i.e. `msg.sender != address(this)`).
    error BridgeUnauthorizedCaller(address caller);

    /// @notice A locked-custody `transferFrom` credited an amount other than requested (fee-on-transfer
    ///         tokens are unsupported: locking less than is minted on the destination breaks 1:1).
    error BridgeAmountMismatch(uint256 requested, uint256 received);

    // -------------------------------------------------------------------------
    //                                   ABI
    // -------------------------------------------------------------------------

    /// @notice Bridge `amount` of the configured token to a crosschain recipient.
    /// @param to     The full ERC-7930 interoperable address of the recipient (chain ref + address).
    /// @param amount The amount to lock/burn here and release/mint on the destination chain.
    /// @return sendId The ERC-7786 gateway-assigned send id.
    function crosschainTransfer(bytes calldata to, uint256 amount) external returns (bytes32 sendId);
}

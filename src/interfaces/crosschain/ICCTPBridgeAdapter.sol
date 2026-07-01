// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ICCTPBridgeAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Admin / read / action surface of the Circle CCTP v2 USDC token-bridge adapter. CCTP is a BURN-AND-
///         MINT token bridge (USDC is burned on the source chain and minted on the destination via an
///         off-chain Iris attestation), NOT an ERC-7786 message gateway — it is deliberately not wrapped as a
///         gateway source and is never routed through the OpenBridge / CrosschainLink messaging stack.
/// @dev The CCTP domain table (Eth 0, Avax 1, OP 2, Arb 3, Base 6, …) is NOT hardcoded — it is admin-registered
///      per chainId, and the per-domain fee / finality / destinationCaller config is likewise admin-managed.
///      Outbound recipients are ERC-7930 interoperable addresses; the destination address is down-converted to
///      a `bytes32` `mintRecipient` (so both 20-byte EVM and 32-byte non-EVM recipients are supported).
interface ICCTPBridgeAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when USDC is burned on this chain for minting on `destinationDomain`.
    event DepositForBurn(
        address indexed sender,
        uint256 indexed destinationChainId,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        uint256 amount
    );

    /// @notice Emitted when an inbound Iris-attested CCTP message is relayed to the transmitter for minting.
    event RelayedMessage(address indexed caller);

    /// @notice Emitted when an EVM/non-EVM chainId ⇒ CCTP domain equivalence is registered.
    event RegisteredChainDomain(uint256 indexed chainId, uint32 domain);

    /// @notice Emitted when the per-domain fee / finality / destinationCaller config is set.
    event ConfiguredDomain(
        uint32 indexed domain, uint256 maxFee, uint32 minFinalityThreshold, bytes32 destinationCaller
    );

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice A required address (tokenMessenger / messageTransmitter / usdc) was the zero address.
    error CCTPZeroAddress();

    /// @notice No CCTP domain is registered for the destination chainId decoded from the recipient.
    error CCTPUnknownDestinationChain(uint256 chainId);

    /// @notice The chain reference decoded from the ERC-7930 recipient does not fit in a uint256.
    error CCTPChainReferenceTooLong(uint256 length);

    /// @notice The CCTP transmitter's `receiveMessage` returned false (attestation invalid / already used).
    error CCTPRelayFailed();

    // -------------------------------------------------------------------------
    //                                  Reads
    // -------------------------------------------------------------------------

    /// @notice The CCTP v2 `TokenMessengerV2` this adapter burns through.
    function tokenMessenger() external view returns (address);

    /// @notice The CCTP v2 `MessageTransmitterV2` this adapter relays inbound messages to.
    function messageTransmitter() external view returns (address);

    /// @notice The bridged USDC token (burn source of funds is `msg.sender`, not the Diamond balance).
    function usdc() external view returns (address);

    /// @notice The CCTP domain registered for `chainId` (meaningless unless {isChainRegistered} is true).
    function getDomain(uint256 chainId) external view returns (uint32);

    /// @notice Whether `chainId` has a registered CCTP domain (distinguishes domain 0 = Ethereum from unset).
    function isChainRegistered(uint256 chainId) external view returns (bool);

    /// @notice The per-domain config used when burning toward `domain`.
    function getDomainConfig(uint32 domain)
        external
        view
        returns (uint256 maxFee, uint32 minFinalityThreshold, bytes32 destinationCaller);

    // -------------------------------------------------------------------------
    //                                  Admin
    // -------------------------------------------------------------------------

    /// @notice Registers `chainId` ⇒ CCTP `domain`. Admin only. Verify the domain table at deploy.
    function registerChainDomain(uint256 chainId, uint32 domain) external;

    /// @notice Sets the per-domain `maxFee`, `minFinalityThreshold` and `destinationCaller`. Admin only.
    function configureDomain(uint32 domain, uint256 maxFee, uint32 minFinalityThreshold, bytes32 destinationCaller)
        external;

    // -------------------------------------------------------------------------
    //                                  Actions
    // -------------------------------------------------------------------------

    /// @notice Burns `amount` USDC (pulled from `msg.sender`) for minting to the ERC-7930 `recipient` on its
    ///         destination chain via CCTP. Approves the TokenMessenger for EXACTLY `amount`, then resets to 0.
    function depositForBurn(uint256 amount, bytes calldata recipient) external;

    /// @notice PERMISSIONLESS passthrough: forwards an Iris-attested CCTP message to the transmitter, which
    ///         mints USDC directly to the recipient. Reverts {CCTPRelayFailed} if the transmitter returns false.
    function relayMessage(bytes calldata message, bytes calldata attestation) external;
}

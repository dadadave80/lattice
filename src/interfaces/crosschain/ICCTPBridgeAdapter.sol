// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ICCTPBridgeAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Circle CCTP v2 (https://github.com/circlefin/evm-cctp-contracts)
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

    /// @notice Emitted when USDC is burned WITH a CCTP v2 hook payload for the destination recipient to execute.
    event DepositForBurnWithHook(
        address indexed sender,
        uint256 indexed destinationChainId,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        uint256 amount,
        bytes hookData
    );

    /// @notice Emitted after an inbound hooked message is relayed: `success` is whether the hook target ran
    ///         without reverting. The mint stands and the CCTP `nonce` is consumed regardless of `success`.
    event HookExecuted(bytes32 indexed nonce, address indexed target, bool success);

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

    /// @notice `registerChainDomain` was called with `chainId` 0 (reserved as the unregistered sentinel).
    error CCTPZeroChainId();

    /// @notice The chainId is already registered — identity registers exactly once (fail-loud, no overwrite).
    error CCTPChainAlreadyRegistered(uint256 chainId);

    /// @notice The domain is already owned by `ownerChainId` — two chains can never share a CCTP domain.
    error CCTPDomainAlreadyRegistered(uint32 domain, uint256 ownerChainId);

    /// @notice `configureDomain` targeted a domain no chain has registered.
    error CCTPDomainNotRegistered(uint32 domain);

    /// @notice The domain's configured `maxFee` is `>=` the burn `amount` (CCTP requires `amount > maxFee`; the
    ///         `>=` form also rejects a zero-amount burn).
    error CCTPMaxFeeExceedsAmount(uint256 maxFee, uint256 amount);

    /// @notice `depositForBurnWithHook` was called with empty `hookData` (use {depositForBurn} for no hook).
    error CCTPEmptyHookData();

    /// @notice An inbound hooked message's `hookData` is not a valid Lattice envelope (missing magic or < 24 B).
    error CCTPInvalidHookData();

    /// @notice An inbound message is not a CCTP v2 `BurnMessageV2` addressed to this adapter's TokenMessenger
    ///         (wrong length, wrong header/body version, or a mismatched header recipient).
    error CCTPNotBurnMessage();

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

    /// @notice The chainId that registered `domain` (0 = unregistered).
    function domainOwner(uint32 domain) external view returns (uint256);

    /// @notice The per-domain config used when burning toward `domain`.
    function getDomainConfig(uint32 domain)
        external
        view
        returns (uint256 maxFee, uint32 minFinalityThreshold, bytes32 destinationCaller);

    /// @notice The role-less, fund-less {CCTPHookExecutor} this diamond routes inbound hooks through (deployed
    ///         once at init, immutable — no setter). Never the zero address on an initialized adapter.
    function hookExecutor() external view returns (address);

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

    /// @notice Like {depositForBurn} but attaches CCTP v2 `hookData` to the burn message (via
    ///         `TokenMessengerV2.depositForBurnWithHook`) for the destination recipient to execute. Reverts
    ///         {CCTPEmptyHookData} if `hookData` is empty (use {depositForBurn} for a hook-less burn).
    function depositForBurnWithHook(uint256 amount, bytes calldata recipient, bytes calldata hookData) external;

    /// @notice PERMISSIONLESS passthrough: forwards an Iris-attested CCTP message to the transmitter, which
    ///         mints USDC directly to the recipient. Reverts {CCTPRelayFailed} if the transmitter returns false.
    function relayMessage(bytes calldata message, bytes calldata attestation) external;

    /// @notice PERMISSIONLESS relay that ALSO executes a Lattice hook envelope carried in the burn message: it
    ///         validates the message is a `BurnMessageV2` addressed to this adapter's TokenMessenger carrying a
    ///         valid Lattice `hookData` envelope, mints via the transmitter, THEN calls the decoded hook target
    ///         through the {CCTPHookExecutor} with Circle-ATTESTED context. Hook execution is LENIENT — a
    ///         reverting/return-bombing target does NOT revert the relay (the mint stands, nonce consumed).
    ///         Reverts {CCTPNotBurnMessage} / {CCTPInvalidHookData} on a non-conforming message BEFORE minting,
    ///         and {CCTPRelayFailed} if the transmitter returns false.
    function relayMessageWithHook(bytes calldata message, bytes calldata attestation) external;
}

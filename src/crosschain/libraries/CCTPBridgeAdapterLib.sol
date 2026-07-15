// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {CCTPHookExecutor} from "@lattice/crosschain/CCTPHookExecutor.sol";
import {BridgeFungibleLib} from "@lattice/crosschain/libraries/BridgeFungibleLib.sol";
import {NonEvmAddress} from "@lattice/crosschain/libraries/NonEvmAddress.sol";
import {AdapterBaseLib} from "@lattice/defi/libraries/AdapterBaseLib.sol";
import {ICCTPBridgeAdapter} from "@lattice/interfaces/crosschain/ICCTPBridgeAdapter.sol";
import {ICCTPHookExecutor} from "@lattice/interfaces/crosschain/ICCTPHookExecutor.sol";
import {IReceiverV2} from "@lattice/interfaces/external/IReceiverV2.sol";
import {ITokenMessengerV2} from "@lattice/interfaces/external/ITokenMessengerV2.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.CCTPBridgeAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant CCTP_BRIDGE_ADAPTER_STORAGE_SLOT = 0x94bcfd23a6ef7deebf3dfac9da6ba8c390ae8a620c8a163523fd263b20958b00;

/// @dev 0xf5187bdc is `type(ICCTPBridgeAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xf5187bdc), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ICCTPBRIDGEADAPTER_SLOT =
    0x04cddf593d633f3c8537926f8f726adaafc298a0f78a2bfd4848abb0191103e1;

/// @dev The leading 4 bytes that mark a `hookData` blob as a Lattice CCTP hook envelope
///      (`HOOK_MAGIC ‖ target(20) ‖ payload`). `bytes4(keccak256("lattice.cctp.hookdata.v1"))`.
bytes4 constant HOOK_MAGIC = 0xf43059e4;

//*//////////////////////////////////////////////////////////////////////////
//                          CCTP v2 MESSAGE OFFSETS
//////////////////////////////////////////////////////////////////////////*//

// Hand-rolled fixed-offset calldata reads that mirror Circle's `TypedMemView` layout WITHOUT vendoring the
// upstream `TypedMemView`-based `MessageV2` / `BurnMessageV2` libraries. See upstream
// `src/messages/v2/{MessageV2,BurnMessageV2}.sol` (https://github.com/circlefin/evm-cctp-contracts).
//
// MessageV2 header (absolute byte offsets): version(uint32)@0, sourceDomain@4, destinationDomain@8,
// nonce(bytes32)@12, sender@44, recipient@76, destinationCaller@108, minFinalityThreshold@140,
// finalityThresholdExecuted@144, messageBody@148.
// BurnMessageV2 body (relative to `_MSG_BODY` = 148): version@0, burnToken@4, mintRecipient@36, amount@68,
// messageSender@100, maxFee@132, feeExecuted@164, expirationBlock@196, hookData@228.
uint256 constant _MSG_VERSION = 0;
uint256 constant _MSG_SOURCE_DOMAIN = 4;
uint256 constant _MSG_NONCE = 12;
uint256 constant _MSG_SENDER = 44;
uint256 constant _MSG_RECIPIENT = 76;
uint256 constant _MSG_BODY = 148;
uint256 constant _BODY_MINT_RECIPIENT = 36;
uint256 constant _BODY_AMOUNT = 68;
uint256 constant _BODY_SENDER = 100;
uint256 constant _BODY_FEE_EXECUTED = 164;
uint256 constant _BODY_HOOK_DATA = 228;

/// @dev A message shorter than header+body-up-to-hookData (`_MSG_BODY + _BODY_HOOK_DATA` = 376) cannot be a
///      BurnMessageV2 carrying a hook.
uint256 constant _MSG_MIN_HOOK_LENGTH = 376;
/// @dev CCTP v2 header AND BurnMessageV2 body version discriminants (both are 1).
uint32 constant _CCTP_VERSION_V2 = 1;
/// @dev A valid Lattice hook envelope is at least `HOOK_MAGIC (4) ‖ target (20)` = 24 bytes.
uint256 constant _HOOK_ENVELOPE_MIN = 24;

/// @notice In-memory bundle of a resolved CCTP burn call, passed as ONE argument to keep the deep 8-arg
///         `depositForBurnWithHook` external call within the legacy-codegen stack limit (no via-IR). NOT a
///         storage struct — never persisted.
struct CctpBurnCall {
    address messenger;
    address token;
    uint256 amount;
    uint32 domain;
    bytes32 mintRecipient;
    bytes32 destinationCaller;
    uint256 maxFee;
    uint32 minFinalityThreshold;
    bytes hookData;
}

/// @notice In-memory ATTESTED context for an inbound hook, read from the CCTP message (never from `hookData`).
///         Passed as ONE argument so the deep 7-arg `executeHook` call fits the legacy-codegen stack limit (no
///         via-IR). NOT a storage struct — never persisted.
struct InboundHook {
    uint32 sourceDomain;
    bytes32 sender;
    bytes32 mintRecipient;
    uint256 amount;
    bytes32 nonce;
    address target;
}

/// @notice Per-CCTP-domain outbound config, all admin-registered. Used verbatim as the trailing args of
///         `ITokenMessengerV2.depositForBurn`. APPEND-ONLY.
struct DomainConfig {
    /// @notice Maximum fee (in USDC units) payable to CCTP for a burn toward this domain.
    uint256 maxFee;
    /// @notice Minimum finality threshold before Iris attests (e.g. 1000 fast / 2000 standard-finalized).
    uint32 minFinalityThreshold;
    /// @notice Optional destination caller lock (`bytes32(0)` = permissionless mint).
    bytes32 destinationCaller;
}

/// @notice ERC-7201 namespaced storage for the CCTP v2 USDC token-bridge adapter.
/// @custom:storage-location erc7201:lattice.storage.CCTPBridgeAdapter
struct CCTPBridgeAdapterStorage {
    /// @notice The CCTP v2 `TokenMessengerV2` (deployed contract, configured at init). APPEND-ONLY.
    address _tokenMessenger;
    /// @notice The CCTP v2 `MessageTransmitterV2` (deployed contract, configured at init). APPEND-ONLY.
    address _messageTransmitter;
    /// @notice The bridged USDC token (deployed contract, configured at init). APPEND-ONLY.
    address _usdc;
    /// @notice chainId => CCTP domain id (meaningless unless `_chainRegistered[chainId]`). APPEND-ONLY.
    mapping(uint256 chainId => uint32 domain) _chainIdToDomain;
    /// @notice chainId => registered flag (distinguishes domain 0 = Ethereum from unset). APPEND-ONLY.
    mapping(uint256 chainId => bool registered) _chainRegistered;
    /// @notice CCTP domain id => per-domain outbound config. APPEND-ONLY.
    mapping(uint32 domain => DomainConfig config) _domainConfig;
    /// @notice CCTP domain id => the chainId that registered it (0 = unregistered; chainId 0 is rejected, so 0
    ///         is a safe sentinel). Loud-duplicate reverse map — two chains can NEVER share a domain. APPEND-ONLY.
    mapping(uint32 domain => uint256 chainId) _domainOwner;
    /// @notice The role-less, fund-less {CCTPHookExecutor} deployed once at init (`new CCTPHookExecutor(diamond)`)
    ///         and never changed — inbound hooks are executed through it so attacker `hookData` gains no
    ///         authority. NO admin setter (a swappable executor would be a forgeable trust anchor). APPEND-ONLY.
    address _hookExecutor;
}

/// @title CCTPBridgeAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Circle CCTP v2 (https://github.com/circlefin/evm-cctp-contracts)
/// @notice Logic + ERC-7201 storage for the Circle CCTP v2 USDC token-bridge adapter. Outbound
///         `depositForBurn` pulls exactly `amount` USDC from the caller, force-approves the TokenMessenger for
///         exactly that amount, burns via CCTP, then resets the allowance to 0 (approval hygiene). Inbound
///         `relayMessage` is a PERMISSIONLESS passthrough to `MessageTransmitterV2.receiveMessage`; the mint
///         goes DIRECTLY to the recipient through Circle's transmitter and the adapter adds no authorization.
/// @dev TRUST MODEL: the inbound mint's correctness is rooted entirely in Circle's off-chain Iris attester set
///      and denylist (the transmitter verifies the attestation signatures) — this adapter neither attests nor
///      gates it. CCTP is a token bridge; it is intentionally NOT an {IERC7786GatewaySource} and is never
///      routed through {ERC7786OpenBridge} / {CrosschainLink}. Reuses the shared safe-transfer / force-approve
///      helpers ({BridgeFungibleLib.pullExact}, {AdapterBaseLib.forceApprove}); no bespoke ERC-20 plumbing.
library CCTPBridgeAdapterLib {
    function cctpBridgeAdapterStorage() internal pure returns (CCTPBridgeAdapterStorage storage $) {
        assembly {
            $.slot := CCTP_BRIDGE_ADAPTER_STORAGE_SLOT
        }
    }

    /// @notice Configures the deployed CCTP contracts + USDC, deploys this diamond's {CCTPHookExecutor}, and
    ///         registers the ICCTPBridgeAdapter ERC-165 id.
    /// @dev Reverts {CCTPZeroAddress} if any address is zero (BEFORE deploying the executor, so the zero-address
    ///      init-revert tests still hold). Called via `delegatecall` inside the diamond initializing window, so
    ///      `address(this)` IS the diamond — the executor is bound to it immutably as its `relay`.
    function __CCTPBridgeAdapter_init(address tokenMessenger_, address messageTransmitter_, address usdc_) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        if (tokenMessenger_ == address(0) || messageTransmitter_ == address(0) || usdc_ == address(0)) {
            revert ICCTPBridgeAdapter.CCTPZeroAddress();
        }
        CCTPBridgeAdapterStorage storage $ = cctpBridgeAdapterStorage();
        $._tokenMessenger = tokenMessenger_;
        $._messageTransmitter = messageTransmitter_;
        $._usdc = usdc_;
        // Deploy the diamond's single hook indirection. `address(this)` is the diamond (delegatecalled init).
        $._hookExecutor = address(new CCTPHookExecutor(address(this)));
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for `ICCTPBridgeAdapter`.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ICCTPBRIDGEADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function tokenMessenger() internal view returns (address) {
        return cctpBridgeAdapterStorage()._tokenMessenger;
    }

    function messageTransmitter() internal view returns (address) {
        return cctpBridgeAdapterStorage()._messageTransmitter;
    }

    function usdc() internal view returns (address) {
        return cctpBridgeAdapterStorage()._usdc;
    }

    function getDomain(uint256 chainId) internal view returns (uint32) {
        return cctpBridgeAdapterStorage()._chainIdToDomain[chainId];
    }

    function domainOwner(uint32 domain) internal view returns (uint256) {
        return cctpBridgeAdapterStorage()._domainOwner[domain];
    }

    function isChainRegistered(uint256 chainId) internal view returns (bool) {
        return cctpBridgeAdapterStorage()._chainRegistered[chainId];
    }

    function getDomainConfig(uint32 domain)
        internal
        view
        returns (uint256 maxFee, uint32 minFinalityThreshold, bytes32 destinationCaller)
    {
        DomainConfig storage cfg = cctpBridgeAdapterStorage()._domainConfig[domain];
        return (cfg.maxFee, cfg.minFinalityThreshold, cfg.destinationCaller);
    }

    function hookExecutor() internal view returns (address) {
        return cctpBridgeAdapterStorage()._hookExecutor;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers `chainId` ⇒ CCTP `domain` (the domain table is caller-supplied, never inferred). Admin.
    /// @dev FAIL-LOUD identity registration (mirrors every other adapter's AlreadyRegistered guards): a chainId
    ///      registers exactly once ({CCTPChainAlreadyRegistered}) and a domain belongs to exactly one chainId
    ///      ({CCTPDomainAlreadyRegistered}) — a fat-fingered duplicate can no longer silently remap USDC burns
    ///      to the wrong destination or clobber another chain's domain config. `chainId` 0 is rejected so the
    ///      `_domainOwner` zero-sentinel stays unambiguous.
    function registerChainDomain(uint256 chainId, uint32 domain) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (chainId == 0) revert ICCTPBridgeAdapter.CCTPZeroChainId();
        CCTPBridgeAdapterStorage storage $ = cctpBridgeAdapterStorage();
        if ($._chainRegistered[chainId]) revert ICCTPBridgeAdapter.CCTPChainAlreadyRegistered(chainId);
        uint256 owner = $._domainOwner[domain];
        if (owner != 0) revert ICCTPBridgeAdapter.CCTPDomainAlreadyRegistered(domain, owner);
        $._chainIdToDomain[chainId] = domain;
        $._chainRegistered[chainId] = true;
        $._domainOwner[domain] = chainId;
        emit ICCTPBridgeAdapter.RegisteredChainDomain(chainId, domain);
    }

    /// @notice Sets the per-domain outbound config (`maxFee`, `minFinalityThreshold`, `destinationCaller`). Admin.
    /// @dev Tunables stay UPDATABLE (unlike identity), but only for a registered domain
    ///      ({CCTPDomainNotRegistered}) — configuring an unowned domain is always a misconfiguration.
    function configureDomain(uint32 domain, uint256 maxFee, uint32 minFinalityThreshold, bytes32 destinationCaller)
        internal
    {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (cctpBridgeAdapterStorage()._domainOwner[domain] == 0) {
            revert ICCTPBridgeAdapter.CCTPDomainNotRegistered(domain);
        }
        DomainConfig storage cfg = cctpBridgeAdapterStorage()._domainConfig[domain];
        cfg.maxFee = maxFee;
        cfg.minFinalityThreshold = minFinalityThreshold;
        cfg.destinationCaller = destinationCaller;
        emit ICCTPBridgeAdapter.ConfiguredDomain(domain, maxFee, minFinalityThreshold, destinationCaller);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   BURN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Burns `amount` USDC (pulled from `msg.sender`) for minting to the ERC-7930 `recipient` on its
    ///         destination chain via CCTP v2. Strict CEI under the reentrancy guard: pull exactly `amount`,
    ///         approve the messenger for exactly `amount`, burn, then reset the allowance to 0.
    /// @param amount    The USDC amount to burn (source of funds is the caller, NOT the Diamond balance).
    /// @param recipient The full ERC-7930 interoperable recipient (chain reference + destination address).
    function depositForBurn(uint256 amount, bytes calldata recipient) internal {
        ReentrancyGuardLib.nonReentrantBefore();
        // `recipient[0:0]` is a zero-length calldata slice → the hook-less branch of {_burn}.
        _burn(amount, recipient, recipient[0:0]);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice Like {depositForBurn} but attaches CCTP v2 `hookData` to the burn message (via
    ///         `depositForBurnWithHook`) for the destination recipient to execute.
    /// @dev Reverts {CCTPEmptyHookData} BEFORE any work if `hookData` is empty — a hook-less burn must use
    ///      {depositForBurn} so its `DepositForBurn` event and 7-arg CCTP call are unambiguous.
    /// @param amount    The USDC amount to burn (source of funds is the caller, NOT the Diamond balance).
    /// @param recipient The full ERC-7930 interoperable recipient (chain reference + destination address).
    /// @param hookData  The CCTP v2 hook payload to carry in the burn message (destination-executed, non-empty).
    function depositForBurnWithHook(uint256 amount, bytes calldata recipient, bytes calldata hookData) internal {
        if (hookData.length == 0) revert ICCTPBridgeAdapter.CCTPEmptyHookData();
        ReentrancyGuardLib.nonReentrantBefore();
        _burn(amount, recipient, hookData);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice Shared burn body for {depositForBurn} (empty `hookData`) and {depositForBurnWithHook}. Strict CEI
    ///         with exact-amount approval hygiene: parse recipient → registered-chain check → maxFee guard →
    ///         pull exactly `amount` → approve exactly `amount` → burn (7-arg plain, or 8-arg WITH hook when
    ///         `hookData` is non-empty) → reset the allowance to 0 → emit.
    /// @dev The caller (each public entrypoint) owns the `nonReentrant` frame — `_burn` runs INSIDE it.
    function _burn(uint256 amount, bytes calldata recipient, bytes calldata hookData) private {
        CCTPBridgeAdapterStorage storage $ = cctpBridgeAdapterStorage();

        // Parse the ERC-7930 recipient: chainReference -> destChainId; address field -> bytes32 recipient.
        (uint256 destChainId, uint32 domain, bytes32 mintRecipient) = _resolveRecipient($, recipient);

        // Guard + pull + exact-approve + burn + reset, isolated so the deep 8-arg CCTP call has a shallow stack.
        _settleBurn($, amount, domain, mintRecipient, hookData);

        if (hookData.length == 0) {
            emit ICCTPBridgeAdapter.DepositForBurn(msg.sender, destChainId, domain, mintRecipient, amount);
        } else {
            emit ICCTPBridgeAdapter.DepositForBurnWithHook(
                msg.sender, destChainId, domain, mintRecipient, amount, hookData
            );
        }
    }

    /// @notice Resolves an ERC-7930 `recipient` to its `(destChainId, domain, mintRecipient)`, reverting
    ///         {CCTPUnknownDestinationChain} if the decoded chain has no registered CCTP domain.
    /// @dev Split out of {_burn} to keep its stack shallow (no via-IR).
    function _resolveRecipient(CCTPBridgeAdapterStorage storage $, bytes calldata recipient)
        private
        view
        returns (uint256 destChainId, uint32 domain, bytes32 mintRecipient)
    {
        bytes memory chainReference;
        (, chainReference, mintRecipient) = NonEvmAddress.parseV1ToBytes32(recipient);
        destChainId = _chainIdFromReference(chainReference);
        if (!$._chainRegistered[destChainId]) revert ICCTPBridgeAdapter.CCTPUnknownDestinationChain(destChainId);
        domain = $._chainIdToDomain[destChainId];
    }

    /// @notice Applies the maxFee guard, pulls EXACTLY `amount` from the caller, approves the messenger for
    ///         EXACTLY `amount`, burns (plain 7-arg `depositForBurn`, or 8-arg `depositForBurnWithHook` when
    ///         `hookData` is non-empty), then resets the allowance to 0 (approval hygiene).
    /// @dev maxFee guard (before ANY token movement): CCTP's TokenMessengerV2 requires `amount > maxFee`; the
    ///      `>=` form also rejects a zero-amount burn. An unconfigured domain has `maxFee == 0`, mapping to
    ///      CCTP's free permissionless standard transfer (passes for any `amount > 0`). Split out of {_burn} so
    ///      the deep 8-arg external call has a shallow stack (no via-IR).
    function _settleBurn(
        CCTPBridgeAdapterStorage storage $,
        uint256 amount,
        uint32 domain,
        bytes32 mintRecipient,
        bytes calldata hookData
    ) private {
        address messenger = $._tokenMessenger;
        address token = $._usdc;
        DomainConfig memory cfg = $._domainConfig[domain];

        if (cfg.maxFee >= amount) revert ICCTPBridgeAdapter.CCTPMaxFeeExceedsAmount(cfg.maxFee, amount);

        BridgeFungibleLib.pullExact(token, msg.sender, amount);
        AdapterBaseLib.forceApprove(token, messenger, amount);
        _cctpBurn(
            CctpBurnCall({
                messenger: messenger,
                token: token,
                amount: amount,
                domain: domain,
                mintRecipient: mintRecipient,
                destinationCaller: cfg.destinationCaller,
                maxFee: cfg.maxFee,
                minFinalityThreshold: cfg.minFinalityThreshold,
                hookData: hookData
            })
        );
        AdapterBaseLib.forceApprove(token, messenger, 0);
    }

    /// @dev Forwards a resolved {CctpBurnCall} to CCTP: the plain 7-arg `depositForBurn` when `hookData` is
    ///      empty, else the 8-arg `depositForBurnWithHook`. The bundle is a single memory arg so each field is
    ///      an MLOAD at the call site — the deep call fits the legacy-codegen stack limit (no via-IR).
    function _cctpBurn(CctpBurnCall memory c) private {
        if (c.hookData.length == 0) {
            ITokenMessengerV2(c.messenger)
                .depositForBurn(
                    c.amount, c.domain, c.mintRecipient, c.token, c.destinationCaller, c.maxFee, c.minFinalityThreshold
                );
        } else {
            ITokenMessengerV2(c.messenger)
                .depositForBurnWithHook(
                    c.amount,
                    c.domain,
                    c.mintRecipient,
                    c.token,
                    c.destinationCaller,
                    c.maxFee,
                    c.minFinalityThreshold,
                    c.hookData
                );
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   RELAY
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice PERMISSIONLESS passthrough: forwards an Iris-attested CCTP message to the transmitter, which
    ///         mints USDC DIRECTLY to the recipient. Adds no authorization — trust is Circle's attester set +
    ///         denylist. Reverts {CCTPRelayFailed} if the transmitter reports failure.
    /// @param message     The CCTP message bytes emitted by the source-chain burn.
    /// @param attestation The Iris attestation over `message`.
    function relayMessage(bytes calldata message, bytes calldata attestation) internal {
        ReentrancyGuardLib.nonReentrantBefore();
        bool success = IReceiverV2(cctpBridgeAdapterStorage()._messageTransmitter).receiveMessage(message, attestation);
        if (!success) revert ICCTPBridgeAdapter.CCTPRelayFailed();
        emit ICCTPBridgeAdapter.RelayedMessage(msg.sender);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice PERMISSIONLESS relay that ALSO executes a Lattice hook envelope carried in the burn message.
    /// @dev SECURITY MODEL: `hookData` is 100% attacker-controlled — anyone on any CCTP chain can burn 1 uUSDC
    ///      toward this diamond with arbitrary `hookData`, and a valid Iris attestation authenticates only
    ///      "someone burned >= 1 uUSDC with these bytes", NOT intent. So the hook is executed through the
    ///      role-less, fund-less {CCTPHookExecutor} (the ONLY caller of the target) with a FIXED selector and
    ///      CONTEXT ARGS READ FROM THE ATTESTED MESSAGE (never from `hookData`). Order — ALL validation BEFORE
    ///      the external mint so a revert consumes nothing:
    ///        1. pure validation: length, header/body version, header recipient == this TokenMessenger, and a
    ///           well-formed Lattice envelope (length >= 24 && leading magic — never an abi.decode);
    ///        2. mint via `MessageTransmitterV2.receiveMessage` (revert {CCTPRelayFailed} on false);
    ///        3. LENIENT `executeHook` — a reverting/return-bombing target does NOT revert the relay (the mint
    ///           stands, the nonce is consumed). A hostile hook re-entering {relayMessage}/{depositForBurn}
    ///           hits the shared reentrancy guard → the inner call reverts → the executor reports `false` → this
    ///           outer relay still completes;
    ///        4. emit {HookExecuted} + {RelayedMessage}.
    /// @param message     The CCTP v2 `BurnMessageV2` bytes (must carry a Lattice hook envelope).
    /// @param attestation The Iris attestation over `message`.
    function relayMessageWithHook(bytes calldata message, bytes calldata attestation) internal {
        ReentrancyGuardLib.nonReentrantBefore();
        CCTPBridgeAdapterStorage storage $ = cctpBridgeAdapterStorage();

        // --- (1) Pure validation (BEFORE the external mint). Scoped so its temporaries drop off the stack. ---
        if (message.length < _MSG_MIN_HOOK_LENGTH) revert ICCTPBridgeAdapter.CCTPNotBurnMessage();
        {
            uint32 headerVersion;
            uint32 bodyVersion;
            bytes32 headerRecipient;
            assembly ("memory-safe") {
                headerVersion := shr(224, calldataload(add(message.offset, _MSG_VERSION)))
                bodyVersion := shr(224, calldataload(add(message.offset, _MSG_BODY)))
                headerRecipient := calldataload(add(message.offset, _MSG_RECIPIENT))
            }
            // Must be a CCTP v2 BurnMessageV2 addressed to THIS adapter's TokenMessenger.
            if (headerVersion != _CCTP_VERSION_V2 || bodyVersion != _CCTP_VERSION_V2) {
                revert ICCTPBridgeAdapter.CCTPNotBurnMessage();
            }
            if (headerRecipient != bytes32(uint256(uint160($._tokenMessenger)))) {
                revert ICCTPBridgeAdapter.CCTPNotBurnMessage();
            }
        }

        // Lattice hook envelope: `HOOK_MAGIC (4) ‖ target (20) ‖ payload`. TWO cheap comparisons only — never an
        // abi.decode that could revert on attacker garbage (the `||` short-circuits before slicing on < 24 B).
        bytes calldata hookData = message[_MSG_MIN_HOOK_LENGTH:];
        if (hookData.length < _HOOK_ENVELOPE_MIN || bytes4(hookData[0:4]) != HOOK_MAGIC) {
            revert ICCTPBridgeAdapter.CCTPInvalidHookData();
        }

        // --- (2) Mint via the transmitter (external). ---
        if (!IReceiverV2($._messageTransmitter).receiveMessage(message, attestation)) {
            revert ICCTPBridgeAdapter.CCTPRelayFailed();
        }

        // --- (3) LENIENT hook execution (isolated to keep the stack shallow); then (4) emit. ---
        _executeInboundHook(message, hookData);
        emit ICCTPBridgeAdapter.RelayedMessage(msg.sender);
        ReentrancyGuardLib.nonReentrantAfter();
    }

    /// @notice Reads the ATTESTED context from `message`, decodes the `target`/`payload` from the validated
    ///         Lattice `hookData` envelope, and calls the hook target through the {CCTPHookExecutor} LENIENTLY —
    ///         a reverting/return-bombing target yields `success == false`, never a revert.
    /// @dev Split out of {relayMessageWithHook} purely to keep that function's stack shallow (no via-IR). All
    ///      context is read from the message, not from `hookData`. Emits {HookExecuted}.
    function _executeInboundHook(bytes calldata message, bytes calldata hookData) private {
        InboundHook memory h = _readInboundContext(message, hookData);
        bool ok = _runExecutor(h, hookData[_HOOK_ENVELOPE_MIN:]);
        emit ICCTPBridgeAdapter.HookExecuted(h.nonce, h.target, ok);
    }

    /// @notice Reads the ATTESTED context (never from `hookData`) plus the envelope's `target` into an
    ///         {InboundHook}. Split out purely to keep {relayMessageWithHook}'s stack shallow (no via-IR).
    function _readInboundContext(bytes calldata message, bytes calldata hookData)
        private
        pure
        returns (InboundHook memory h)
    {
        uint32 sourceDomain;
        bytes32 nonce;
        bytes32 mintRecipient;
        uint256 amount;
        bytes32 sender;
        uint256 feeExecuted;
        assembly ("memory-safe") {
            sourceDomain := shr(224, calldataload(add(message.offset, _MSG_SOURCE_DOMAIN)))
            nonce := calldataload(add(message.offset, _MSG_NONCE))
            mintRecipient := calldataload(add(message.offset, add(_MSG_BODY, _BODY_MINT_RECIPIENT)))
            amount := calldataload(add(message.offset, add(_MSG_BODY, _BODY_AMOUNT)))
            sender := calldataload(add(message.offset, add(_MSG_BODY, _BODY_SENDER)))
            feeExecuted := calldataload(add(message.offset, add(_MSG_BODY, _BODY_FEE_EXECUTED)))
        }
        h.sourceDomain = sourceDomain;
        h.sender = sender;
        h.mintRecipient = mintRecipient;
        // The hook receives the amount ACTUALLY MINTED to `mintRecipient` (attested burn `amount` minus the
        // attested `feeExecuted`), not the gross burn amount — CCTP v2 nets the fee at mint time on fast
        // transfers. Checked subtraction is safe: this runs only after `receiveMessage` succeeded and CCTP
        // enforces `feeExecuted <= amount` for any attested burn.
        h.amount = amount - feeExecuted;
        h.nonce = nonce;
        h.target = address(bytes20(hookData[4:_HOOK_ENVELOPE_MIN]));
    }

    /// @notice Forwards the attested {InboundHook} + attacker `payload` to the {CCTPHookExecutor} LENIENTLY. The
    ///         bundle is one memory arg so the deep 7-arg `executeHook` call fits the legacy-codegen stack limit.
    function _runExecutor(InboundHook memory h, bytes calldata payload) private returns (bool ok) {
        ok = ICCTPHookExecutor(cctpBridgeAdapterStorage()._hookExecutor)
            .executeHook(h.sourceDomain, h.sender, h.mintRecipient, h.amount, h.nonce, h.target, payload);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Right-aligns an ERC-7930 chain-reference (<= 32 bytes, big-endian) into a uint256 chainId.
    /// @dev For eip-155 chains the reference IS the chainId. Reverts {CCTPChainReferenceTooLong} if > 32 bytes.
    function _chainIdFromReference(bytes memory ref) private pure returns (uint256 chainId) {
        uint256 len = ref.length;
        if (len > 32) revert ICCTPBridgeAdapter.CCTPChainReferenceTooLong(len);
        assembly ("memory-safe") {
            chainId := shr(mul(sub(32, len), 8), mload(add(ref, 0x20)))
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {BridgeFungibleLib} from "@lattice/crosschain/libraries/BridgeFungibleLib.sol";
import {NonEvmAddress} from "@lattice/crosschain/libraries/NonEvmAddress.sol";
import {AdapterBaseLib} from "@lattice/defi/libraries/AdapterBaseLib.sol";
import {ICCTPBridgeAdapter} from "@lattice/interfaces/crosschain/ICCTPBridgeAdapter.sol";
import {IReceiverV2} from "@lattice/interfaces/external/IReceiverV2.sol";
import {ITokenMessengerV2} from "@lattice/interfaces/external/ITokenMessengerV2.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.CCTPBridgeAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant CCTP_BRIDGE_ADAPTER_STORAGE_SLOT = 0x94bcfd23a6ef7deebf3dfac9da6ba8c390ae8a620c8a163523fd263b20958b00;

/// @dev 0xa777cf1b is `type(ICCTPBridgeAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xa777cf1b), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ICCTPBRIDGEADAPTER_SLOT =
    0x30c377002135d1e8af7caedae6ec2adb3221e5a36ce695d62defb43a35cd29eb;

/// @notice Per-CCTP-domain outbound config, all admin-registered. Used verbatim as the trailing args of
///         `ITokenMessengerV2.depositForBurn`. APPEND-ONLY.
struct DomainConfig {
    /// @notice Maximum fee (in USDC units) payable to CCTP for a burn toward this domain.
    uint256 maxFee;
    /// @notice Minimum finality threshold before Iris attests (e.g. 1000 standard / 2000 fast).
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
}

/// @title CCTPBridgeAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
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

    /// @notice Configures the deployed CCTP contracts + USDC and registers the ICCTPBridgeAdapter ERC-165 id.
    /// @dev Reverts {CCTPZeroAddress} if any address is zero. Called inside the diamond initializing window.
    function __CCTPBridgeAdapter_init(address tokenMessenger_, address messageTransmitter_, address usdc_) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        if (tokenMessenger_ == address(0) || messageTransmitter_ == address(0) || usdc_ == address(0)) {
            revert ICCTPBridgeAdapter.CCTPZeroAddress();
        }
        CCTPBridgeAdapterStorage storage $ = cctpBridgeAdapterStorage();
        $._tokenMessenger = tokenMessenger_;
        $._messageTransmitter = messageTransmitter_;
        $._usdc = usdc_;
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

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers `chainId` ⇒ CCTP `domain` (the domain table is caller-supplied, never inferred). Admin.
    function registerChainDomain(uint256 chainId, uint32 domain) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        CCTPBridgeAdapterStorage storage $ = cctpBridgeAdapterStorage();
        $._chainIdToDomain[chainId] = domain;
        $._chainRegistered[chainId] = true;
        emit ICCTPBridgeAdapter.RegisteredChainDomain(chainId, domain);
    }

    /// @notice Sets the per-domain outbound config (`maxFee`, `minFinalityThreshold`, `destinationCaller`). Admin.
    function configureDomain(uint32 domain, uint256 maxFee, uint32 minFinalityThreshold, bytes32 destinationCaller)
        internal
    {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
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
        CCTPBridgeAdapterStorage storage $ = cctpBridgeAdapterStorage();

        uint256 destChainId;
        uint32 domain;
        bytes32 mintRecipient;
        {
            // Parse the ERC-7930 recipient: chainReference -> destChainId; address field -> bytes32 recipient.
            (, bytes memory chainReference, bytes32 addr) = NonEvmAddress.parseV1ToBytes32(recipient);
            mintRecipient = addr;
            destChainId = _chainIdFromReference(chainReference);
            if (!$._chainRegistered[destChainId]) revert ICCTPBridgeAdapter.CCTPUnknownDestinationChain(destChainId);
            domain = $._chainIdToDomain[destChainId];
        }

        address messenger = $._tokenMessenger;
        address token = $._usdc;
        DomainConfig storage cfg = $._domainConfig[domain];

        // Pull EXACTLY `amount` from the caller, then approve the messenger for EXACTLY `amount`.
        BridgeFungibleLib.pullExact(token, msg.sender, amount);
        AdapterBaseLib.forceApprove(token, messenger, amount);

        ITokenMessengerV2(messenger)
            .depositForBurn(
                amount, domain, mintRecipient, token, cfg.destinationCaller, cfg.maxFee, cfg.minFinalityThreshold
            );

        // Approval hygiene: reset the messenger allowance to 0 (no residual approval left behind).
        AdapterBaseLib.forceApprove(token, messenger, 0);

        emit ICCTPBridgeAdapter.DepositForBurn(msg.sender, destChainId, domain, mintRecipient, amount);
        ReentrancyGuardLib.nonReentrantAfter();
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

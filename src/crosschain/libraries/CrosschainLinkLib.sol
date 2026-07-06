// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {ICrosschainLink} from "@lattice/interfaces/crosschain/ICrosschainLink.sol";
import {IERC7786MessageHandler} from "@lattice/interfaces/crosschain/IERC7786MessageHandler.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/IERC7786.sol";
import {Bytes} from "@lattice/utils/libraries/Bytes.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.CrosschainLink")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant CROSSCHAIN_LINK_STORAGE_SLOT = 0x018a2157cdb5adbb1b39e614b18b4d8eae2cba40cdae1a4ba3100cc857e64900;

/// @dev 0xe1805ff8 is `type(ICrosschainLink).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xe1805ff8), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ICROSSCHAINLINK_SLOT = 0x9ddc11a88c7ecd9ccccbcd59cd7f34c709ebe70b4507cbaed74ad8b1267235ef;

/// @notice A registered link to a remote chain.
struct Link {
    /// @notice The ERC-7786 gateway trusted for this chain (sends and receives).
    address gateway;
    /// @notice The full ERC-7930 interoperable address of the remote counterpart (chain ref + address).
    bytes counterpart;
}

/// @notice ERC-7201 namespaced storage for CrosschainLink.
/// @custom:storage-location erc7201:lattice.storage.CrosschainLink
struct CrosschainLinkStorage {
    /// @notice Per source-chain link, keyed by a "chain-only" interoperable address. APPEND-ONLY.
    mapping(bytes chain => Link) _links;
    /// @notice Inbound message handler per 4-byte payload tag. APPEND-ONLY.
    mapping(bytes4 tag => address handler) _handlers;
    /// @notice De-duplication set, keyed by `keccak256(abi.encode(gateway, receiveId))` — ERC-7786 only
    ///         guarantees receiveId uniqueness per-gateway, so the key is gateway-scoped. APPEND-ONLY.
    mapping(bytes32 usedKey => bool used) _used;
}

/// @title CrosschainLinkLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin `CrosschainLinked` + `ERC7786Recipient` v5.6.1 (https://github.com/OpenZeppelin/openzeppelin-contracts)
///         (https://github.com/OpenZeppelin/openzeppelin-contracts/tree/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/crosschain).
/// @notice Logic + ERC-7201 storage for the {CrosschainLink} facet: an ERC-7786 send + receive endpoint
///         with a per-chain `(gateway, counterpart)` link registry and tag-routed inbound handlers.
/// @dev Divergence from OZ: ERC-7786's `receiveMessage` is a single Diamond selector, so this one library
///      authenticates AND dispatches (OZ leaves `_processMessage` to a subclass). Dispatch is by the
///      payload's leading 4-byte tag → a registered handler. Unlike OZ's `ERC7786Recipient` (which trusts
///      the gateway for at-most-once delivery), this adds defensive `receiveId` replay protection because
///      a Diamond may authorize more than one gateway (uniqueness is only guaranteed per-gateway).
library CrosschainLinkLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                                  STORAGE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the ERC-7201 storage struct for CrosschainLink.
    function crosschainLinkStorage() internal pure returns (CrosschainLinkStorage storage $) {
        assembly {
            $.slot := CROSSCHAIN_LINK_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALISATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the ICrosschainLink ERC-165 interface.
    /// @dev Must be called between `preInitializer` / `postInitializer`.
    function __CrosschainLink_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for ICrosschainLink.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ICROSSCHAINLINK_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the gateway and counterpart registered for a chain-only interoperable address.
    function getLink(bytes memory chain) internal view returns (address gateway, bytes memory counterpart) {
        Link storage l = crosschainLinkStorage()._links[chain];
        return (l.gateway, l.counterpart);
    }

    /// @notice Returns the handler registered for a message tag (zero if none).
    function getHandler(bytes4 tag) internal view returns (address) {
        return crosschainLinkStorage()._handlers[tag];
    }

    /// @notice Returns whether a `receiveId` from a given `gateway` has already been processed.
    /// @dev Keyed per-gateway (ERC-7786 only guarantees receiveId uniqueness for the calling gateway).
    function isProcessed(address gateway, bytes32 receiveId) internal view returns (bool) {
        return crosschainLinkStorage()._used[keccak256(abi.encode(gateway, receiveId))];
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 RECEIVE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Authenticates, de-duplicates, and dispatches an inbound ERC-7786 message.
    /// @dev Checks-effects-interactions: `receiveId` is marked used (effect) BEFORE the handler call
    ///      (interaction); a reverting handler rolls that back, keeping the message retryable.
    /// @return The ERC-7786 magic value `IERC7786Recipient.receiveMessage.selector` (0x2432ef26).
    function receiveMessage(bytes32 receiveId, bytes calldata sender, bytes calldata payload)
        internal
        returns (bytes4)
    {
        if (!_isAuthorizedGateway(msg.sender, sender)) {
            revert ICrosschainLink.CrosschainUnauthorizedGateway(msg.sender, sender);
        }

        CrosschainLinkStorage storage $ = crosschainLinkStorage();
        // Gateway-scoped replay key: ERC-7786 only guarantees receiveId uniqueness per-gateway, so a
        // Diamond linked to multiple gateways must not let identical ids collide into a global namespace
        // (which would falsely reject an authentic message whose source funds are already burned/locked).
        bytes32 usedKey = keccak256(abi.encode(msg.sender, receiveId));
        if ($._used[usedKey]) revert ICrosschainLink.CrosschainMessageAlreadyProcessed(receiveId);
        $._used[usedKey] = true;

        if (payload.length < 4) revert ICrosschainLink.CrosschainInvalidPayload();
        bytes4 tag = bytes4(payload[0:4]);

        address handler = $._handlers[tag];
        if (handler == address(0)) revert ICrosschainLink.CrosschainHandlerNotRegistered(tag);

        IERC7786MessageHandler(handler).processMessage(receiveId, sender, payload[4:]);

        emit ICrosschainLink.MessageProcessed(receiveId, tag, handler);
        return IERC7786Recipient.receiveMessage.selector;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers (or overrides) the gateway + counterpart for the counterpart's source chain.
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE.
    function setLink(address gateway, bytes calldata counterpart, bool allowOverride) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (gateway == address(0)) revert ICrosschainLink.CrosschainZeroGateway();
        // Sanity check: reverts if `gateway` is not an ERC-7786 source (an EOA returns no data and fails).
        IERC7786GatewaySource(gateway).supportsAttribute(bytes4(0));

        bytes memory chain = _extractChain(counterpart);
        CrosschainLinkStorage storage $ = crosschainLinkStorage();
        if (allowOverride || $._links[chain].gateway == address(0)) {
            $._links[chain] = Link(gateway, counterpart);
            emit ICrosschainLink.LinkRegistered(gateway, counterpart);
        } else {
            revert ICrosschainLink.CrosschainLinkAlreadyRegistered(chain);
        }
    }

    /// @notice Registers a handler for inbound messages whose payload starts with `tag` (zero to clear).
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE.
    function setHandler(bytes4 tag, address handler) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        crosschainLinkStorage()._handlers[tag] = handler;
        emit ICrosschainLink.HandlerRegistered(tag, handler);
    }

    /// @notice Sends a message to the counterpart registered for `chain` via its ERC-7786 gateway.
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE. Admin entrypoint for ad-hoc messages (e.g. governance
    ///      signalling); handler/bridge logic uses the un-gated {sendToCounterpart} directly.
    function sendMessage(bytes calldata chain, bytes calldata payload, bytes[] calldata attributes)
        internal
        returns (bytes32)
    {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        return sendToCounterpart(chain, payload, attributes);
    }

    /// @notice Sends a message to the counterpart registered for `chain` via its ERC-7786 gateway.
    /// @dev NO access control — callable only from in-Diamond facet logic (it is `internal`). Bridge
    ///      handlers call this; their own token mechanics (burn/lock the caller's funds) are the gate.
    ///      External callers can only reach the gated {sendMessage} selector, never this directly.
    function sendToCounterpart(bytes memory chain, bytes memory payload, bytes[] memory attributes)
        internal
        returns (bytes32)
    {
        (address gateway, bytes memory counterpart) = getLink(chain);
        return IERC7786GatewaySource(gateway).sendMessage(counterpart, payload, attributes);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Whether `instance` is the registered gateway AND `sender` is the registered counterpart for
    ///         the source chain encoded in `sender`.
    function _isAuthorizedGateway(address instance, bytes calldata sender) private view returns (bool) {
        (address gateway, bytes memory counterpart) = getLink(_extractChain(sender));
        return instance == gateway && Bytes.equal(sender, counterpart);
    }

    /// @notice Reduces a full interoperable address to its "chain-only" form (drops the address part).
    function _extractChain(bytes memory self) private pure returns (bytes memory) {
        (bytes2 chainType, bytes memory chainReference,) = InteroperableAddress.parseV1(self);
        return InteroperableAddress.formatV1(chainType, chainReference, hex"");
    }
}

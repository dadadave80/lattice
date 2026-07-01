// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IZetaChainGatewayAdapter} from "@lattice/interfaces/crosschain/IZetaChainGatewayAdapter.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/IERC7786.sol";
import {IGatewayEVM, MessageContext, RevertOptions} from "@lattice/interfaces/external/IGatewayEVM.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ZetaChainGatewayAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ZETACHAIN_GATEWAY_ADAPTER_STORAGE_SLOT =
    0x7529f1b714a55f00ea95d180ad0c2a53651f18a834ecec0ff1f9af59ddf74000;

/// @dev ERC-165 map slot for `IERC7786GatewaySource` (`0x11967553`). SHARED by all gateway adapters —
///      `keccak256(abi.encode(bytes4(0x11967553), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC7786GATEWAYSOURCE_SLOT =
    0x3c75b8ea75c097979221eb9302e2f0f6009b4ffe0a7198db5dc29979e09ea0e3;

/// @notice ERC-7201 namespaced storage for the ZetaChain gateway adapter.
/// @custom:storage-location erc7201:lattice.storage.ZetaChainGatewayAdapter
struct ZetaChainGatewayAdapterStorage {
    /// @notice The ZetaChain `GatewayEVM` (a DEPLOYED contract, address varies per connected chain). APPEND-ONLY.
    address _gateway;
    /// @notice The default `onRevertGasLimit` used to build per-message `RevertOptions`. APPEND-ONLY.
    uint256 _defaultOnRevertGasLimit;
    /// @notice Forward map: hub chainId => trusted remote ZEVM universal app (0 = unset). APPEND-ONLY.
    mapping(uint256 chainId => address remoteApp) _remoteApps;
    /// @notice Reverse map: trusted remote ZEVM universal app => hub chainId (0 = unset). APPEND-ONLY.
    ///         `onCall` yields `context.sender = the app` (NOT a chainId); this recovers the source chainId for
    ///         auth + the delivery-id namespace.
    mapping(address remoteApp => uint256 chainId) _appToChainId;
    /// @notice Replay guard: per source chainId, the set of consumed delivery ids. APPEND-ONLY.
    mapping(uint256 chainId => mapping(bytes32 id => bool used)) _executed;
    /// @notice Monotonic outbound counter. The ZetaChain gateway exposes no per-message id to the delivery hook,
    ///         so each dispatched message carries this source-minted nonce, giving a globally-unique (source,
    ///         nonce) id on delivery (matching the unique-id semantics of the CCIP/LayerZero/OP siblings).
    uint256 _outboundNonce;
}

/// @title ZetaChainGatewayAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Logic + ERC-7201 storage for the ZetaChain `GatewayEVM` ERC-7786 gateway adapter. `sendMessage` builds
///         the ERC-7930 envelope and dispatches it via `gateway.call` to the destination's ZEVM universal app
///         (the hub), forwarding `msg.value` as the native messaging fee; `onCall` is the gateway-invoked delivery
///         hook that authenticates the source out-of-band via the reverse app⇒chainId map, de-duplicates per
///         (source, id), and delivers to the ERC-7930 recipient. EVM chains only.
/// @dev HUB-ROUTED: a "remote" is the ZEVM UNIVERSAL APP for a hub `chainId`, not a direct peer adapter. Both a
///      forward (`chainId => app`) and a reverse (`app => chainId`) map are kept because inbound `onCall` only
///      exposes `context.sender = the app`. INVERTED/HUB INBOUND AUTH: `onCall`'s `msg.sender` is the `GatewayEVM`
///      (driven by the ZetaChain TSS/observer set), so trust is established by matching `context.sender` to a
///      registered app and recovering its source chainId. Wire message (envelope) =
///      `abi.encode(senderInterop, recipientInterop, payload, nonce)`.
library ZetaChainGatewayAdapterLib {
    function zetaChainGatewayAdapterStorage() internal pure returns (ZetaChainGatewayAdapterStorage storage $) {
        assembly {
            $.slot := ZETACHAIN_GATEWAY_ADAPTER_STORAGE_SLOT
        }
    }

    /// @notice Stores the gateway + default revert gas, registers the hub route in BOTH maps, and registers the
    ///         gateway-source ERC-165 id.
    /// @param gateway_ The ZetaChain `GatewayEVM` (deployed contract, per-connected-chain address).
    /// @param hubChainId The hub chainId whose ZEVM universal app terminates the route.
    /// @param hubRemoteApp The trusted ZEVM universal app for `hubChainId`.
    /// @param defaultOnRevertGasLimit_ The default `onRevertGasLimit` for per-message `RevertOptions`.
    function __ZetaChainGatewayAdapter_init(
        address gateway_,
        uint256 hubChainId,
        address hubRemoteApp,
        uint256 defaultOnRevertGasLimit_
    ) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        ZetaChainGatewayAdapterStorage storage $ = zetaChainGatewayAdapterStorage();
        if (gateway_ == address(0)) revert IZetaChainGatewayAdapter.InvalidGateway();
        $._gateway = gateway_;
        emit IZetaChainGatewayAdapter.GatewaySet(gateway_);
        $._defaultOnRevertGasLimit = defaultOnRevertGasLimit_;
        emit IZetaChainGatewayAdapter.DefaultOnRevertGasLimitSet(defaultOnRevertGasLimit_);
        _registerRemote($, hubChainId, hubRemoteApp);
        registerInterface();
    }

    /// @notice Writes `true` to the SHARED IERC7786GatewaySource ERC-165 map slot (0x11967553 → ...). Same slot
    ///         the CCIP/LayerZero/OP/Axelar adapters register; a Diamond mounts at most one gateway.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC7786GATEWAYSOURCE_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function gateway() internal view returns (address) {
        return zetaChainGatewayAdapterStorage()._gateway;
    }

    function getRemoteApp(uint256 chainId) internal view returns (address) {
        return zetaChainGatewayAdapterStorage()._remoteApps[chainId];
    }

    function getChainIdForApp(address remoteApp) internal view returns (uint256) {
        return zetaChainGatewayAdapterStorage()._appToChainId[remoteApp];
    }

    function defaultOnRevertGasLimit() internal view returns (uint256) {
        return zetaChainGatewayAdapterStorage()._defaultOnRevertGasLimit;
    }

    /// @notice No `sendMessage` attributes are supported: surfacing `RevertOptions` as a per-message ERC-7786
    ///         attribute is #77 open question #8 (DEFERRED) — an admin-configured default is used instead.
    function supportsAttribute(bytes4) internal pure returns (bool) {
        return false;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    function setGateway(address gateway_) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (gateway_ == address(0)) revert IZetaChainGatewayAdapter.InvalidGateway();
        zetaChainGatewayAdapterStorage()._gateway = gateway_;
        emit IZetaChainGatewayAdapter.GatewaySet(gateway_);
    }

    function registerRemote(uint256 chainId, address remoteApp) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        _registerRemote(zetaChainGatewayAdapterStorage(), chainId, remoteApp);
    }

    function setDefaultOnRevertGasLimit(uint256 onRevertGasLimit) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        zetaChainGatewayAdapterStorage()._defaultOnRevertGasLimit = onRevertGasLimit;
        emit IZetaChainGatewayAdapter.DefaultOnRevertGasLimitSet(onRevertGasLimit);
    }

    /// @notice One-shot registration of a trusted remote ZEVM universal app for `chainId` in BOTH maps.
    /// @dev Rejects zero app; rejects a chainId already mapped OR an app already mapped (either direction).
    function _registerRemote(ZetaChainGatewayAdapterStorage storage $, uint256 chainId, address remoteApp) private {
        // Reject a zero remote app or chain 0 (chain 0 is the "unregistered" sentinel in the reverse map).
        if (remoteApp == address(0) || chainId == 0) revert IZetaChainGatewayAdapter.InvalidRemote();
        if ($._remoteApps[chainId] != address(0) || $._appToChainId[remoteApp] != 0) {
            revert IZetaChainGatewayAdapter.RemoteAlreadyRegistered(chainId);
        }
        $._remoteApps[chainId] = remoteApp;
        $._appToChainId[remoteApp] = chainId;
        emit IZetaChainGatewayAdapter.RegisteredRemote(chainId, remoteApp);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   SEND
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice ERC-7786 source. Parses the ERC-7930 `recipient` into `(destChainId, target)`, resolves the
    ///         destination's trusted ZEVM universal app (the hub route terminus), wraps the ERC-7930 envelope with
    ///         a source-minted monotonic nonce, and dispatches it via `gateway.call`. Forwards `msg.value` as the
    ///         native messaging fee (there is NO on-chain quote or refund from the gateway). Returns the
    ///         globally-unique `keccak256(abi.encode(block.chainid, nonce))` as the ERC-7786 `sendId`.
    /// @dev No attributes are supported — any attribute reverts {UnsupportedAttribute}. The `RevertOptions` are an
    ///      admin-configured default (`revertAddress = msg.sender`, `callOnRevert = false`); surfacing them
    ///      per-message is #77 open question #8 (DEFERRED). `remote = forward[destChainId]` is the ZEVM universal
    ///      app / hub-terminated route; an unset route reverts {UnknownDestinationChain}.
    function sendMessage(bytes calldata recipient, bytes calldata payload, bytes[] calldata attributes)
        internal
        returns (bytes32)
    {
        if (attributes.length != 0) revert IERC7786GatewaySource.UnsupportedAttribute(bytes4(attributes[0]));

        // Envelope carries a source-owned monotonic nonce (`$._outboundNonce++`) so the delivery id is globally
        // unique per (source, nonce) rather than envelope content — otherwise two byte-identical-but-distinct
        // messages would collide on delivery (one permanently dropped) and the recipient would see a non-unique id.
        // Dispatch is block-scoped so the routing locals free before the emit (non-via-IR stack budget).
        uint256 nonce;
        {
            (uint256 destChainId,) = InteroperableAddress.parseEvmV1(recipient);
            ZetaChainGatewayAdapterStorage storage $ = zetaChainGatewayAdapterStorage();
            address remote = $._remoteApps[destChainId];
            if (remote == address(0)) revert IZetaChainGatewayAdapter.UnknownDestinationChain(destChainId);

            nonce = $._outboundNonce++;
            RevertOptions memory revertOptions = RevertOptions({
                revertAddress: msg.sender,
                callOnRevert: false,
                // Direct funds on ZetaChain's terminal abort path back to the caller (not address(0), which burns).
                abortAddress: msg.sender,
                revertMessage: "",
                onRevertGasLimit: $._defaultOnRevertGasLimit
            });
            bytes memory envelope =
                abi.encode(InteroperableAddress.formatEvmV1(block.chainid, msg.sender), recipient, payload, nonce);
            // Forward msg.value as the native messaging fee (no on-chain quote/refund from the gateway).
            IGatewayEVM($._gateway).call{value: msg.value}(remote, envelope, revertOptions);
        }

        bytes32 id = keccak256(abi.encode(block.chainid, nonce));
        emit IERC7786GatewaySource.MessageSent(
            id, InteroperableAddress.formatEvmV1(block.chainid, msg.sender), recipient, payload, msg.value, attributes
        );
        return id;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  RECEIVE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Gateway-invoked delivery hook (INVERTED/HUB AUTH). Authenticates: (1) `msg.sender` is the configured
    ///         `GatewayEVM`; (2) `context.sender` is a registered trusted ZEVM universal app, recovering the source
    ///         chainId from the reverse map. De-dups per (source, delivery id) marking BEFORE delivery (strict
    ///         CEI), then delivers to the ERC-7930 recipient after asserting it targets THIS chain. Returns empty
    ///         bytes.
    /// @dev The delivery id is derived from the authenticated source + the source-minted nonce (NOT envelope
    ///      content), so two byte-identical-but-distinct messages get distinct ids (neither dropped).
    function onCall(MessageContext calldata context, bytes calldata message) internal returns (bytes memory) {
        ZetaChainGatewayAdapterStorage storage $ = zetaChainGatewayAdapterStorage();
        if (msg.sender != $._gateway) revert IZetaChainGatewayAdapter.NotGateway(msg.sender);

        // Recover the source chainId from the reverse app⇒chainId map; an unregistered app (chainId 0) fails auth.
        uint256 chainId = $._appToChainId[context.sender];
        if (chainId == 0) revert IZetaChainGatewayAdapter.InvalidOriginApp(context.sender);

        (bytes memory sender, bytes memory recipient, bytes memory payload, uint256 nonce) =
            abi.decode(message, (bytes, bytes, bytes, uint256));

        // Defense-in-depth: the reverse map recovers the source chain from the ZEVM app, which assumes ONE app per
        // source corridor. Cross-check the envelope's self-declared source chain against the app's registered chain
        // so a shared/misconfigured app fronting the wrong corridor is rejected (fail-closed) rather than
        // misattributed into a colliding (chainId, nonce) namespace. Scoped so the local frees before delivery.
        {
            (uint256 declaredSource,) = InteroperableAddress.parseEvmV1(sender);
            if (declaredSource != chainId) {
                revert IZetaChainGatewayAdapter.SourceChainMismatch(declaredSource, chainId);
            }
        }

        // CEI replay guard on the globally-unique (source, nonce) delivery id; marked BEFORE delivery.
        bytes32 id = keccak256(abi.encode(chainId, nonce));
        if ($._executed[chainId][id]) revert IZetaChainGatewayAdapter.MessageAlreadyExecuted(chainId, id);
        $._executed[chainId][id] = true;

        // A well-behaved remote only ever routes messages whose recipient targets THIS chain; reject anything else
        // so a rogue/misconfigured remote cannot misdirect delivery. Scoped so only `target` survives.
        address target;
        {
            (uint256 recipientChainId, address target_) = InteroperableAddress.parseEvmV1(recipient);
            if (recipientChainId != block.chainid) {
                revert IZetaChainGatewayAdapter.WrongDestinationChain(recipientChainId);
            }
            target = target_;
        }

        // onCall is payable (the gateway may forward native value); forward it so nothing is trapped in the Diamond.
        if (
            IERC7786Recipient(target).receiveMessage{value: msg.value}(id, sender, payload)
                != IERC7786Recipient.receiveMessage.selector
        ) {
            revert IZetaChainGatewayAdapter.RecipientExecutionFailed();
        }
        return "";
    }
}

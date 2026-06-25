// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {BridgeFungibleLib} from "@lattice/crosschain/libraries/BridgeFungibleLib.sol";
import {AdapterBaseLib} from "@lattice/defi/libraries/AdapterBaseLib.sol";
import {ICCIPGatewayAdapter} from "@lattice/interfaces/ICCIPGatewayAdapter.sol";
import {Client} from "@lattice/interfaces/external/CCIPClient.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/IERC7786.sol";
import {IRouterClient} from "@lattice/interfaces/external/IRouterClient.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.CCIPGatewayAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant CCIP_GATEWAY_ADAPTER_STORAGE_SLOT = 0xfc37dafbf0181d0474cf94e236f0ede0d369aab52659fb134d4be3b15fbb8e00;

/// @dev ERC-165 map slot for `IERC7786GatewaySource` (`0x11967553`). SHARED by all gateway adapters —
///      `keccak256(abi.encode(bytes4(0x11967553), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC7786GATEWAYSOURCE_SLOT =
    0x3c75b8ea75c097979221eb9302e2f0f6009b4ffe0a7198db5dc29979e09ea0e3;

/// @dev ERC-165 map slot for `IAny2EVMMessageReceiver` (`0x85572ffb`). UNIQUE to CCIP — the router calls
///      `supportsInterface(0x85572ffb)` before delivery; if false it drops the message and delivers only
///      tokens. `keccak256(abi.encode(bytes4(0x85572ffb), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IANY2EVMMESSAGERECEIVER_SLOT =
    0x800eb085c0ca5e4523c112cc053bae87b4696eb6a3bf735b4b8b0a9d09be1465;

/// @notice ERC-7201 namespaced storage for the CCIP gateway adapter.
/// @custom:storage-location erc7201:lattice.storage.CCIPGatewayAdapter
struct CCIPGatewayAdapterStorage {
    /// @notice The Chainlink CCIP router (OZ-style immutable → Diamond storage). APPEND-ONLY.
    address _router;
    /// @notice Fee token: `address(0)` ⇒ native (`msg.value`), else an ERC-20 (e.g. LINK). APPEND-ONLY.
    address _feeToken;
    /// @notice EVM chainId => CCIP chain selector (0 = unset). APPEND-ONLY.
    mapping(uint256 chainId => uint64 selector) _chainIdToSelector;
    /// @notice CCIP chain selector => EVM chainId (0 = unset). APPEND-ONLY.
    mapping(uint64 selector => uint256 chainId) _selectorToChainId;
    /// @notice Trusted remote gateway adapter per EVM chainId. APPEND-ONLY.
    mapping(uint256 chainId => address remote) _remoteGateways;
    /// @notice Per-destination delivery gas limit (0 = unconfigured). APPEND-ONLY.
    mapping(uint256 chainId => uint256 gasLimit) _destGasLimit;
    /// @notice Per-destination `allowOutOfOrderExecution` flag. APPEND-ONLY.
    mapping(uint256 chainId => bool allowOutOfOrder) _destAllowOutOfOrder;
    /// @notice Replay guard: per source chainId, the set of consumed CCIP messageIds. APPEND-ONLY.
    mapping(uint256 chainId => mapping(bytes32 messageId => bool used)) _executed;
}

/// @title CCIPGatewayAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Logic + ERC-7201 storage for the Chainlink CCIP ERC-7786 gateway adapter. `sendMessage` builds a
///         CCIP `EVM2AnyMessage`, quotes `getFee`, and submits via `ccipSend` (native or ERC-20 fee);
///         `ccipReceive` is the router-gated delivery callback that validates the source selector + trusted
///         remote gateway, de-duplicates per (chainId, CCIP messageId), and delivers to the ERC-7930
///         recipient. EVM chains only. CCIP routes by `uint64` chain selector, not EVM chainId.
/// @dev Wire payload = `abi.encode(senderInteropAddr, recipientInteropAddr, innerPayload)`; the CCIP
///      `receiver` field targets the trusted remote adapter, which forwards to the final recipient.
library CCIPGatewayAdapterLib {
    function ccipGatewayAdapterStorage() internal pure returns (CCIPGatewayAdapterStorage storage $) {
        assembly {
            $.slot := CCIP_GATEWAY_ADAPTER_STORAGE_SLOT
        }
    }

    /// @notice Configures the router + fee token and registers the gateway-source + CCIP-receiver ERC-165 ids.
    function __CCIPGatewayAdapter_init(address router_, address feeToken_) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        CCIPGatewayAdapterStorage storage $ = ccipGatewayAdapterStorage();
        $._router = router_;
        $._feeToken = feeToken_;
        emit ICCIPGatewayAdapter.SetFeeToken(feeToken_);
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slots for `IERC7786GatewaySource` (shared) and
    ///         `IAny2EVMMessageReceiver` (CCIP-specific; required for the router to deliver messages).
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC7786GATEWAYSOURCE_SLOT, true)
            sstore(ERC165_MAP_IANY2EVMMESSAGERECEIVER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function router() internal view returns (address) {
        return ccipGatewayAdapterStorage()._router;
    }

    function feeToken() internal view returns (address) {
        return ccipGatewayAdapterStorage()._feeToken;
    }

    function getChainSelector(uint256 chainId) internal view returns (uint64) {
        return ccipGatewayAdapterStorage()._chainIdToSelector[chainId];
    }

    function getChainId(uint64 selector) internal view returns (uint256) {
        return ccipGatewayAdapterStorage()._selectorToChainId[selector];
    }

    function getRemoteGateway(uint256 chainId) internal view returns (address) {
        return ccipGatewayAdapterStorage()._remoteGateways[chainId];
    }

    function getDestinationGasLimit(uint256 chainId) internal view returns (uint256) {
        return ccipGatewayAdapterStorage()._destGasLimit[chainId];
    }

    function getAllowOutOfOrderExecution(uint256 chainId) internal view returns (bool) {
        return ccipGatewayAdapterStorage()._destAllowOutOfOrder[chainId];
    }

    /// @notice No `sendMessage` attributes are supported by this adapter (per-dest gas is admin-configured).
    function supportsAttribute(bytes4) internal pure returns (bool) {
        return false;
    }

    function quoteFee(bytes calldata recipient, bytes calldata payload) internal view returns (uint256) {
        (Client.EVM2AnyMessage memory message, uint64 selector) = _buildMessage(recipient, payload);
        return IRouterClient(ccipGatewayAdapterStorage()._router).getFee(selector, message);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    function registerChainSelector(uint256 chainId, uint64 selector) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        CCIPGatewayAdapterStorage storage $ = ccipGatewayAdapterStorage();
        if ($._chainIdToSelector[chainId] != 0 || $._selectorToChainId[selector] != 0) {
            revert ICCIPGatewayAdapter.ChainSelectorAlreadyRegistered(chainId);
        }
        $._chainIdToSelector[chainId] = selector;
        $._selectorToChainId[selector] = chainId;
        emit ICCIPGatewayAdapter.RegisteredChainSelector(chainId, selector);
    }

    function registerRemoteGateway(uint256 chainId, address remote) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        CCIPGatewayAdapterStorage storage $ = ccipGatewayAdapterStorage();
        if ($._remoteGateways[chainId] != address(0)) {
            revert ICCIPGatewayAdapter.RemoteGatewayAlreadyRegistered(chainId);
        }
        $._remoteGateways[chainId] = remote;
        emit ICCIPGatewayAdapter.RegisteredRemoteGateway(chainId, remote);
    }

    function configureDestination(uint256 chainId, uint256 gasLimit, bool allowOutOfOrderExecution) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        CCIPGatewayAdapterStorage storage $ = ccipGatewayAdapterStorage();
        $._destGasLimit[chainId] = gasLimit;
        $._destAllowOutOfOrder[chainId] = allowOutOfOrderExecution;
        emit ICCIPGatewayAdapter.ConfiguredDestination(chainId, gasLimit, allowOutOfOrderExecution);
    }

    function setFeeToken(address feeToken_) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ccipGatewayAdapterStorage()._feeToken = feeToken_;
        emit ICCIPGatewayAdapter.SetFeeToken(feeToken_);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   SEND
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice ERC-7786 source. Quotes the CCIP fee and submits the message immediately (synchronous, no
    ///         further action required), so it returns `bytes32(0)` per ERC-7786. The CCIP `messageId` is
    ///         emitted by the router's own event. The fee is paid by `msg.sender`: native via `msg.value`
    ///         (excess refunded), or an ERC-20 fee token pulled from the caller — never from Diamond funds.
    /// @dev No attributes are supported — any attribute reverts {UnsupportedAttribute}.
    function sendMessage(bytes calldata recipient, bytes calldata payload, bytes[] calldata attributes)
        internal
        returns (bytes32)
    {
        if (attributes.length != 0) revert IERC7786GatewaySource.UnsupportedAttribute(bytes4(attributes[0]));

        (Client.EVM2AnyMessage memory message, uint64 selector) = _buildMessage(recipient, payload);
        address router_ = ccipGatewayAdapterStorage()._router;
        uint256 fee = IRouterClient(router_).getFee(selector, message);

        if (message.feeToken == address(0)) {
            if (msg.value < fee) revert ICCIPGatewayAdapter.InsufficientFee(msg.value, fee);
            IRouterClient(router_).ccipSend{value: fee}(selector, message);
        } else {
            // Caller-funded: pull exactly `fee` of the fee token from the sender, then approve the router.
            BridgeFungibleLib.pullExact(message.feeToken, msg.sender, fee);
            AdapterBaseLib.forceApprove(message.feeToken, router_, fee);
            IRouterClient(router_).ccipSend(selector, message);
        }

        // Refund any native not consumed by the fee (all of it on the ERC-20 path).
        uint256 spent = message.feeToken == address(0) ? fee : 0;
        if (msg.value > spent) {
            (bool ok,) = msg.sender.call{value: msg.value - spent}("");
            if (!ok) revert ICCIPGatewayAdapter.RefundFailed();
        }

        emit IERC7786GatewaySource.MessageSent(
            bytes32(0),
            InteroperableAddress.formatEvmV1(block.chainid, msg.sender),
            recipient,
            payload,
            msg.value,
            attributes
        );
        return bytes32(0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  RECEIVE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice CCIP delivery callback: validate router + source selector + trusted remote gateway, de-dup
    ///         per (chainId, messageId), then deliver to the ERC-7930 recipient encoded in the payload.
    function ccipReceive(Client.Any2EVMMessage calldata message) internal {
        CCIPGatewayAdapterStorage storage $ = ccipGatewayAdapterStorage();
        if (msg.sender != $._router) revert ICCIPGatewayAdapter.NotRouter(msg.sender);

        // `message.sender` is `abi.encode(address)` (32 bytes) on EVM sources; guard the length so a
        // malformed/non-EVM sender surfaces the typed InvalidOriginGateway rather than a bare decode revert.
        uint256 chainId = $._selectorToChainId[message.sourceChainSelector];
        if (
            chainId == 0 || message.sender.length != 32
                || abi.decode(message.sender, (address)) != $._remoteGateways[chainId]
        ) {
            revert ICCIPGatewayAdapter.InvalidOriginGateway(message.sourceChainSelector, message.sender);
        }

        if ($._executed[chainId][message.messageId]) {
            revert ICCIPGatewayAdapter.MessageAlreadyExecuted(chainId, message.messageId);
        }
        $._executed[chainId][message.messageId] = true;

        (bytes memory sender, bytes memory recipient, bytes memory inner) =
            abi.decode(message.data, (bytes, bytes, bytes));

        // CCIP's `ccipReceive` is non-payable (data-only delivery; native value is never carried as msg.value),
        // so no value is forwarded to the recipient — unlike the payable Wormhole relayer callback.
        (, address target) = InteroperableAddress.parseEvmV1(recipient);
        if (
            IERC7786Recipient(target).receiveMessage(message.messageId, sender, inner)
                != IERC7786Recipient.receiveMessage.selector
        ) {
            revert ICCIPGatewayAdapter.RecipientExecutionFailed();
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Builds the CCIP `EVM2AnyMessage` for `recipient`/`payload` and returns the dest chain selector.
    /// @dev Reverts {UnknownDestinationChain} if the selector/remote is unset, {DestinationNotConfigured} if
    ///      the delivery gas limit is unset. Wraps the final ERC-7930 recipient inside the wire payload.
    function _buildMessage(bytes calldata recipient, bytes calldata payload)
        private
        view
        returns (Client.EVM2AnyMessage memory message, uint64 selector)
    {
        (uint256 chainId,) = InteroperableAddress.parseEvmV1(recipient);
        CCIPGatewayAdapterStorage storage $ = ccipGatewayAdapterStorage();
        address remote = $._remoteGateways[chainId];
        selector = $._chainIdToSelector[chainId];
        if (selector == 0 || remote == address(0)) revert ICCIPGatewayAdapter.UnknownDestinationChain(chainId);
        uint256 gasLimit = $._destGasLimit[chainId];
        if (gasLimit == 0) revert ICCIPGatewayAdapter.DestinationNotConfigured(chainId);

        message = Client.EVM2AnyMessage({
            receiver: abi.encode(remote),
            data: abi.encode(InteroperableAddress.formatEvmV1(block.chainid, msg.sender), recipient, payload),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            feeToken: $._feeToken,
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({
                    gasLimit: gasLimit, allowOutOfOrderExecution: $._destAllowOutOfOrder[chainId]
                })
            )
        });
    }
}

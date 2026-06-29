// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAxelarGatewayAdapter} from "@lattice/interfaces/crosschain/IAxelarGatewayAdapter.sol";
import {IAxelarGateway} from "@lattice/interfaces/external/IAxelarGateway.sol";
import {IERC7786GatewaySource, IERC7786Recipient} from "@lattice/interfaces/external/IERC7786.sol";
import {Bytes} from "@lattice/utils/libraries/Bytes.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";
import {Strings} from "@lattice/utils/libraries/Strings.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.AxelarGatewayAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant AXELAR_GATEWAY_ADAPTER_STORAGE_SLOT =
    0xeb5bee64b500c298be8b1e9f77b8505f5c8c9cdd4c45b490c069ffc446e8fd00;

/// @dev 0x11967553 is `type(IERC7786GatewaySource).interfaceId`. Shared by all gateway adapters.
/// `keccak256(abi.encode(bytes4(0x11967553), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC7786GATEWAYSOURCE_SLOT =
    0x3c75b8ea75c097979221eb9302e2f0f6009b4ffe0a7198db5dc29979e09ea0e3;

/// @notice ERC-7201 namespaced storage for the Axelar gateway adapter.
/// @custom:storage-location erc7201:lattice.storage.AxelarGatewayAdapter
struct AxelarGatewayAdapterStorage {
    /// @notice The Axelar gateway (OZ uses an immutable; a Diamond must use storage). APPEND-ONLY.
    address _gateway;
    /// @notice Trusted remote gateway adapter per chain: chainType => chainReference => address-bytes. APPEND-ONLY.
    mapping(bytes2 chainType => mapping(bytes chainReference => bytes addr)) _remoteGateways;
    /// @notice CAIP-2 (chain-only ERC-7930) => Axelar chain name. APPEND-ONLY.
    mapping(bytes chain => string axelar) _erc7930ToAxelar;
    /// @notice Axelar chain name => CAIP-2 (chain-only ERC-7930). APPEND-ONLY.
    mapping(string axelar => bytes chain) _axelarToErc7930;
}

/// @title AxelarGatewayAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin community-contracts `AxelarGatewayAdapter` (commit f7e5f08).
/// @notice Dual-mode ERC-7786 gateway over Axelar GMP: `sendMessage` (source) calls the Axelar gateway's
///         `callContract`; `execute` (destination) validates an approved call + the trusted source gateway,
///         then delivers to the ERC-7786 recipient. EVM chains only. Gas is handled off-band (no gas service).
library AxelarGatewayAdapterLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                                  STORAGE
    //////////////////////////////////////////////////////////////////////////*//

    function axelarGatewayAdapterStorage() internal pure returns (AxelarGatewayAdapterStorage storage $) {
        assembly {
            $.slot := AXELAR_GATEWAY_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALISATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Configures the Axelar gateway and registers the IERC7786GatewaySource ERC-165 interface.
    function __AxelarGatewayAdapter_init(address gateway_) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        axelarGatewayAdapterStorage()._gateway = gateway_;
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for IERC7786GatewaySource (shared by gateway adapters).
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC7786GATEWAYSOURCE_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function gateway() internal view returns (address) {
        return axelarGatewayAdapterStorage()._gateway;
    }

    function supportsAttribute(bytes4) internal pure returns (bool) {
        return false;
    }

    function getAxelarChain(bytes memory chain) internal view returns (string memory) {
        return axelarGatewayAdapterStorage()._erc7930ToAxelar[chain];
    }

    function getErc7930Chain(string memory axelar) internal view returns (bytes memory) {
        return axelarGatewayAdapterStorage()._axelarToErc7930[axelar];
    }

    function getRemoteGateway(bytes memory chain) internal view returns (bytes memory) {
        (bytes2 chainType, bytes memory chainReference,) = InteroperableAddress.parseV1(chain);
        return axelarGatewayAdapterStorage()._remoteGateways[chainType][chainReference];
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers a CAIP-2 ↔ Axelar chain-name equivalence (both directions). Admin only.
    function registerChainEquivalence(bytes calldata chain, string calldata axelar) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        AxelarGatewayAdapterStorage storage $ = axelarGatewayAdapterStorage();
        if (bytes($._erc7930ToAxelar[chain]).length != 0 || $._axelarToErc7930[axelar].length != 0) {
            revert IAxelarGatewayAdapter.ChainEquivalenceAlreadyRegistered(chain);
        }
        $._erc7930ToAxelar[chain] = axelar;
        $._axelarToErc7930[axelar] = chain;
        emit IAxelarGatewayAdapter.RegisteredChainEquivalence(chain, axelar);
    }

    /// @notice Registers a trusted remote gateway adapter (full ERC-7930 address). Admin only.
    function registerRemoteGateway(bytes calldata remote) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        (bytes2 chainType, bytes memory chainReference, bytes memory addr) = InteroperableAddress.parseV1(remote);
        AxelarGatewayAdapterStorage storage $ = axelarGatewayAdapterStorage();
        if ($._remoteGateways[chainType][chainReference].length != 0) {
            revert IAxelarGatewayAdapter.RemoteGatewayAlreadyRegistered(InteroperableAddress.formatV1(
                    chainType, chainReference, hex""
                ));
        }
        $._remoteGateways[chainType][chainReference] = addr;
        emit IAxelarGatewayAdapter.RegisteredRemoteGateway(remote);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  MESSAGING
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice ERC-7786 source: emits the message to the trusted remote gateway via Axelar `callContract`.
    /// @dev Fire-and-forget — returns `bytes32(0)`. Rejects native value and any attribute. Gas is off-band.
    function sendMessage(bytes calldata recipient, bytes calldata payload, bytes[] calldata attributes)
        internal
        returns (bytes32)
    {
        if (msg.value != 0) revert IAxelarGatewayAdapter.UnsupportedNativeTransfer();
        if (attributes.length > 0) revert IERC7786GatewaySource.UnsupportedAttribute(bytes4(attributes[0]));

        bytes memory sender = InteroperableAddress.formatEvmV1(block.chainid, msg.sender);
        emit IERC7786GatewaySource.MessageSent(bytes32(0), sender, recipient, payload, 0, attributes);

        // Build the wire payload before resolving, then resolve in a helper, to stay under the stack limit.
        bytes memory adapterPayload = abi.encode(sender, recipient, payload);
        (string memory axelarDestination, string memory axelarTarget) = _resolveDestination(recipient);

        IAxelarGateway(gateway()).callContract(axelarDestination, axelarTarget, adapterPayload);
        return bytes32(0);
    }

    /// @notice Axelar destination: validate the approved call + the trusted source gateway, then deliver.
    function execute(
        bytes32 commandId,
        string calldata sourceChain,
        string calldata sourceAddress,
        bytes calldata adapterPayload
    ) internal {
        AxelarGatewayAdapterStorage storage $ = axelarGatewayAdapterStorage();
        if (!IAxelarGateway($._gateway)
                .validateContractCall(commandId, sourceChain, sourceAddress, keccak256(adapterPayload))) {
            revert IAxelarGatewayAdapter.NotApprovedByGateway();
        }

        // Source authentication: the Axelar source address must equal the registered remote gateway for the
        // source chain. Split into a helper to keep this frame below the (non-via-IR) stack limit.
        _checkOriginGateway($, sourceChain, sourceAddress);

        (bytes memory sender, bytes memory recipient, bytes memory payload) =
            abi.decode(adapterPayload, (bytes, bytes, bytes));
        (, address target) = InteroperableAddress.parseEvmV1(recipient);
        if (
            IERC7786Recipient(target).receiveMessage(commandId, sender, payload)
                != IERC7786Recipient.receiveMessage.selector
        ) {
            revert IAxelarGatewayAdapter.RecipientExecutionFailed();
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Reverts unless `sourceAddress` equals the registered remote gateway for `sourceChain`
    ///         (checksummed-string compare, Axelar's address form).
    function _checkOriginGateway(
        AxelarGatewayAdapterStorage storage $,
        string calldata sourceChain,
        string calldata sourceAddress
    ) private view {
        (bytes2 chainType, bytes memory chainReference,) = InteroperableAddress.parseV1($._axelarToErc7930[sourceChain]);
        if (
            keccak256(bytes(_stringifyAddress(chainType, $._remoteGateways[chainType][chainReference])))
                != keccak256(bytes(sourceAddress))
        ) {
            revert IAxelarGatewayAdapter.InvalidOriginGateway(sourceChain, sourceAddress);
        }
    }

    /// @notice Resolves a recipient's chain into the Axelar destination chain name + the trusted remote
    ///         gateway's Axelar address string. Split out to keep {sendMessage} below the stack limit.
    function _resolveDestination(bytes calldata recipient)
        private
        view
        returns (string memory axelarDestination, string memory axelarTarget)
    {
        (bytes2 chainType, bytes memory chainReference,) = InteroperableAddress.parseV1(recipient);
        AxelarGatewayAdapterStorage storage $ = axelarGatewayAdapterStorage();
        axelarDestination = $._erc7930ToAxelar[InteroperableAddress.formatV1(chainType, chainReference, hex"")];
        axelarTarget = _stringifyAddress(chainType, $._remoteGateways[chainType][chainReference]);
    }

    /// @notice Stringifies an interoperable address part for Axelar (EVM only → EIP-55 checksummed hex).
    function _stringifyAddress(bytes2 chainType, bytes memory addr) internal pure returns (string memory) {
        if (chainType != 0x0000) revert IAxelarGatewayAdapter.UnsupportedChainType(chainType);
        return Strings.toChecksumHexString(address(bytes20(addr)));
    }
}

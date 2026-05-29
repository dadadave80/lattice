// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ContextLib} from "@diamond/libraries/ContextLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IERC1155, IERC1155Receiver} from "@lattice/interfaces/IERC1155.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC1155")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC1155_STORAGE_SLOT = 0xe39704fe713bf9d011ae08177a1e99cc7df74d40063bba4426aeb9d10e274c00;

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC1155_ERC165_STORAGE_LOCATION = 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0xd9b67a26 is `type(IERC1155).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xd9b67a26), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC1155_SLOT = 0xa10754813726d67c8d4e4553f74a520d6623216a67c6c4a53860c47e2ccde594;

/// @dev 0x0e89341c is `type(IERC1155MetadataURI).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x0e89341c), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC1155METADATAURI_SLOT =
    0x16223e323116e54e339612437d2478d553a51948c039066bf3354fac71c5ef6c;

/// @notice Storage struct for ERC-1155 module.
/// @custom:storage-location erc7201:lattice.storage.ERC1155
struct ERC1155Storage {
    mapping(uint256 id => mapping(address account => uint256)) _balances;
    mapping(address account => mapping(address operator => bool)) _operatorApprovals;
    string _uri;
}

/// @title ERC1155Lib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Library implementing the ERC-1155 Multi-Token Standard.
/// @dev Mirrors OpenZeppelin v5 ERC1155 logic. All state lives in an ERC-7201 slot.
library ERC1155Lib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function erc1155Storage() internal pure returns (ERC1155Storage storage $) {
        assembly {
            $.slot := ERC1155_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the ERC-1155 module with a URI template.
    /// @dev Must be called inside a pre/postInitializer block.
    function __ERC1155_init(string memory uri_) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);

        erc1155Storage()._uri = uri_;
        registerInterfaces();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for IERC1155 and IERC1155MetadataURI interfaces via ERC-165.
    function registerInterfaces() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC1155_SLOT, true)
            sstore(ERC165_MAP_IERC1155METADATAURI_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the URI for token type `id`.
    /// @dev Consumers can override to substitute `{id}` in the template.
    function uri(uint256 /*id*/ ) internal view returns (string memory) {
        return erc1155Storage()._uri;
    }

    /// @notice Returns the balance of `account` for token type `id`.
    function balanceOf(address account, uint256 id) internal view returns (uint256) {
        return erc1155Storage()._balances[id][account];
    }

    /// @notice Batched version of {balanceOf}.
    function balanceOfBatch(address[] memory accounts, uint256[] memory ids)
        internal
        view
        returns (uint256[] memory)
    {
        if (accounts.length != ids.length) {
            revert IERC1155.ERC1155InvalidArrayLength(ids.length, accounts.length);
        }
        uint256[] memory batchBalances = new uint256[](accounts.length);
        for (uint256 i = 0; i < accounts.length; ++i) {
            batchBalances[i] = balanceOf(accounts[i], ids[i]);
        }
        return batchBalances;
    }

    /// @notice Returns true if `operator` is approved to transfer `account`'s tokens.
    function isApprovedForAll(address account, address operator) internal view returns (bool) {
        return erc1155Storage()._operatorApprovals[account][operator];
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           MUTATION OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Grants or revokes permission to `operator`.
    function setApprovalForAll(address operator, bool approved) internal {
        address owner = ContextLib.msgSender();
        if (operator == address(0)) revert IERC1155.ERC1155InvalidOperator(address(0));
        erc1155Storage()._operatorApprovals[owner][operator] = approved;
        emit IERC1155.ApprovalForAll(owner, operator, approved);
    }

    /// @notice Transfers `value` of token `id` from `from` to `to`.
    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes memory data) internal {
        address sender = ContextLib.msgSender();
        if (from != sender && !isApprovedForAll(from, sender)) {
            revert IERC1155.ERC1155MissingApprovalForAll(sender, from);
        }
        _safeTransferFrom(from, to, id, value, data);
    }

    /// @notice Batch transfers tokens.
    function safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    ) internal {
        address sender = ContextLib.msgSender();
        if (from != sender && !isApprovedForAll(from, sender)) {
            revert IERC1155.ERC1155MissingApprovalForAll(sender, from);
        }
        _safeBatchTransferFrom(from, to, ids, values, data);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Internal safe single transfer. Validates receiver.
    function _safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes memory data) internal {
        if (to == address(0)) revert IERC1155.ERC1155InvalidReceiver(address(0));
        if (from == address(0)) revert IERC1155.ERC1155InvalidSender(address(0));
        uint256[] memory ids = _asSingletonArray(id);
        uint256[] memory values = _asSingletonArray(value);
        address operator = ContextLib.msgSender();
        _update(from, to, ids, values);
        _doSafeTransferAcceptanceCheck(operator, from, to, id, value, data);
    }

    /// @notice Internal safe batch transfer. Validates receiver.
    function _safeBatchTransferFrom(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    ) internal {
        if (to == address(0)) revert IERC1155.ERC1155InvalidReceiver(address(0));
        if (from == address(0)) revert IERC1155.ERC1155InvalidSender(address(0));
        address operator = ContextLib.msgSender();
        _update(from, to, ids, values);
        _doSafeBatchTransferAcceptanceCheck(operator, from, to, ids, values, data);
    }

    /// @notice Central state mutation. Validates array lengths, adjusts balances, emits events.
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal {
        if (ids.length != values.length) {
            revert IERC1155.ERC1155InvalidArrayLength(ids.length, values.length);
        }

        address operator = ContextLib.msgSender();
        ERC1155Storage storage $ = erc1155Storage();

        for (uint256 i = 0; i < ids.length; ++i) {
            uint256 id = ids[i];
            uint256 value = values[i];

            if (from != address(0)) {
                uint256 fromBalance = $._balances[id][from];
                if (fromBalance < value) {
                    revert IERC1155.ERC1155InsufficientBalance(from, fromBalance, value, id);
                }
                unchecked {
                    $._balances[id][from] = fromBalance - value;
                }
            }

            if (to != address(0)) {
                unchecked {
                    $._balances[id][to] += value;
                }
            }
        }

        if (ids.length == 1) {
            emit IERC1155.TransferSingle(operator, from, to, ids[0], values[0]);
        } else {
            emit IERC1155.TransferBatch(operator, from, to, ids, values);
        }
    }

    /// @notice Mints `value` of token `id` to `to`.
    function _mint(address to, uint256 id, uint256 value, bytes memory data) internal {
        if (to == address(0)) revert IERC1155.ERC1155InvalidReceiver(address(0));
        uint256[] memory ids = _asSingletonArray(id);
        uint256[] memory values = _asSingletonArray(value);
        _update(address(0), to, ids, values);
        _doSafeTransferAcceptanceCheck(ContextLib.msgSender(), address(0), to, id, value, data);
    }

    /// @notice Batch mints tokens to `to`.
    function _mintBatch(address to, uint256[] memory ids, uint256[] memory values, bytes memory data) internal {
        if (to == address(0)) revert IERC1155.ERC1155InvalidReceiver(address(0));
        _update(address(0), to, ids, values);
        _doSafeBatchTransferAcceptanceCheck(ContextLib.msgSender(), address(0), to, ids, values, data);
    }

    /// @notice Burns `value` of token `id` from `from`.
    function _burn(address from, uint256 id, uint256 value) internal {
        if (from == address(0)) revert IERC1155.ERC1155InvalidSender(address(0));
        uint256[] memory ids = _asSingletonArray(id);
        uint256[] memory values = _asSingletonArray(value);
        _update(from, address(0), ids, values);
    }

    /// @notice Batch burns tokens from `from`.
    function _burnBatch(address from, uint256[] memory ids, uint256[] memory values) internal {
        if (from == address(0)) revert IERC1155.ERC1155InvalidSender(address(0));
        _update(from, address(0), ids, values);
    }

    /// @notice Updates balances then performs the ERC-1155 receiver acceptance check.
    /// @dev Provides the OZ _updateWithAcceptanceCheck override hook layer. Extensions that
    ///      need to intercept both state-update and receiver-check in one virtual point can
    ///      wrap this function at the facet layer.
    function _updateWithAcceptanceCheck(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    ) internal {
        _update(from, to, ids, values);
        if (to != address(0)) {
            address operator = ContextLib.msgSender();
            if (ids.length == 1) {
                _doSafeTransferAcceptanceCheck(operator, from, to, ids[0], values[0], data);
            } else {
                _doSafeBatchTransferAcceptanceCheck(operator, from, to, ids, values, data);
            }
        }
    }

    /// @notice Calls IERC1155Receiver.onERC1155Received if `to` is a contract.
    /// @dev Distinguishes between a non-implementor (empty revert) and a deliberate
    ///      revert from the receiver (non-empty reason). Non-empty reasons are re-bubbled
    ///      verbatim so callers see the actual error from the receiver contract.
    function _doSafeTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256 id,
        uint256 value,
        bytes memory data
    ) internal {
        if (to.code.length > 0) {
            try IERC1155Receiver(to).onERC1155Received(operator, from, id, value, data) returns (bytes4 response) {
                if (response != IERC1155Receiver.onERC1155Received.selector) {
                    revert IERC1155.ERC1155InvalidReceiver(to);
                }
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert IERC1155.ERC1155InvalidReceiver(to);
                } else {
                    assembly ("memory-safe") {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        }
    }

    /// @notice Calls IERC1155Receiver.onERC1155BatchReceived if `to` is a contract.
    /// @dev Distinguishes between a non-implementor (empty revert) and a deliberate
    ///      revert from the receiver (non-empty reason). Non-empty reasons are re-bubbled
    ///      verbatim so callers see the actual error from the receiver contract.
    function _doSafeBatchTransferAcceptanceCheck(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data
    ) internal {
        if (to.code.length > 0) {
            try IERC1155Receiver(to).onERC1155BatchReceived(operator, from, ids, values, data) returns (
                bytes4 response
            ) {
                if (response != IERC1155Receiver.onERC1155BatchReceived.selector) {
                    revert IERC1155.ERC1155InvalidReceiver(to);
                }
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert IERC1155.ERC1155InvalidReceiver(to);
                } else {
                    assembly ("memory-safe") {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            ARRAY UTILITY
    //////////////////////////////////////////////////////////////////////////*//

    function _asSingletonArray(uint256 element) internal pure returns (uint256[] memory arr) {
        arr = new uint256[](1);
        arr[0] = element;
    }
}

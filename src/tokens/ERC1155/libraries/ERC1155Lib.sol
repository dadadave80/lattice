// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC1155, IERC1155Receiver} from "@lattice/interfaces/tokens/IERC1155.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC1155")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC1155_STORAGE_SLOT = 0xe39704fe713bf9d011ae08177a1e99cc7df74d40063bba4426aeb9d10e274c00;

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC1155_ERC165_STORAGE_LOCATION = 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0xd9b67a26 is the canonical EIP-1155 id, NOT `type(IERC1155).interfaceId`: Lattice's {IERC1155} bundles
///      the metadata URI extension, so its derived id is 0xd73f4e3a. ERC-165 callers query the canonical id.
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
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC1155/ERC1155.sol)
/// @notice Library implementing the ERC-1155 Multi-Token Standard.
/// @dev Mirrors OpenZeppelin v5.6.1 ERC1155 logic. All state lives in an ERC-7201 slot. Differences: no
///      `_setApprovalForAll(owner, ...)` variant (approval always uses `msg.sender`, so OZ's owner-zero check
///      cannot fire) and no five-argument `_updateWithAcceptanceCheck` overload.
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
    function uri(
        uint256 /*id*/
    )
        internal
        view
        returns (string memory)
    {
        return erc1155Storage()._uri;
    }

    /// @notice Returns the balance of `account` for token type `id`.
    function balanceOf(address account, uint256 id) internal view returns (uint256) {
        return erc1155Storage()._balances[id][account];
    }

    /// @notice Batched version of {balanceOf}.
    function balanceOfBatch(address[] memory accounts, uint256[] memory ids) internal view returns (uint256[] memory) {
        if (accounts.length != ids.length) {
            revert IERC1155.ERC1155InvalidArrayLength(ids.length, accounts.length);
        }
        uint256[] memory batchBalances = new uint256[](accounts.length);
        for (uint256 i; i < accounts.length; ++i) {
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
        address owner = msg.sender;
        if (operator == address(0)) revert IERC1155.ERC1155InvalidOperator(address(0));
        erc1155Storage()._operatorApprovals[owner][operator] = approved;
        emit IERC1155.ApprovalForAll(owner, operator, approved);
    }

    /// @notice Transfers `value` of token `id` from `from` to `to`.
    function safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes memory data) internal {
        _checkAuthorized(msg.sender, from);
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
        _checkAuthorized(msg.sender, from);
        _safeBatchTransferFrom(from, to, ids, values, data);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Reverts with {IERC1155.ERC1155MissingApprovalForAll} unless `operator` is `owner` or an
    ///         approved operator of `owner`.
    function _checkAuthorized(address operator, address owner) internal view {
        if (owner != operator && !isApprovedForAll(owner, operator)) {
            revert IERC1155.ERC1155MissingApprovalForAll(operator, owner);
        }
    }

    /// @notice Internal safe single transfer. Validates receiver.
    function _safeTransferFrom(address from, address to, uint256 id, uint256 value, bytes memory data) internal {
        if (to == address(0)) revert IERC1155.ERC1155InvalidReceiver(address(0));
        if (from == address(0)) revert IERC1155.ERC1155InvalidSender(address(0));
        _updateWithAcceptanceCheck(from, to, _asSingletonArray(id), _asSingletonArray(value), data, false);
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
        _updateWithAcceptanceCheck(from, to, ids, values, data, true);
    }

    /// @notice Central state mutation. Validates array lengths, adjusts balances, emits events.
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal {
        if (ids.length != values.length) {
            revert IERC1155.ERC1155InvalidArrayLength(ids.length, values.length);
        }

        address operator = msg.sender;
        ERC1155Storage storage $ = erc1155Storage();

        for (uint256 i; i < ids.length; ++i) {
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
                $._balances[id][to] += value;
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
        _updateWithAcceptanceCheck(address(0), to, _asSingletonArray(id), _asSingletonArray(value), data, false);
    }

    /// @notice Batch mints tokens to `to`.
    function _mintBatch(address to, uint256[] memory ids, uint256[] memory values, bytes memory data) internal {
        if (to == address(0)) revert IERC1155.ERC1155InvalidReceiver(address(0));
        _updateWithAcceptanceCheck(address(0), to, ids, values, data, true);
    }

    /// @notice Burns `value` of token `id` from `from`.
    function _burn(address from, uint256 id, uint256 value) internal {
        if (from == address(0)) revert IERC1155.ERC1155InvalidSender(address(0));
        _updateWithAcceptanceCheck(from, address(0), _asSingletonArray(id), _asSingletonArray(value), "", false);
    }

    /// @notice Batch burns tokens from `from`.
    function _burnBatch(address from, uint256[] memory ids, uint256[] memory values) internal {
        if (from == address(0)) revert IERC1155.ERC1155InvalidSender(address(0));
        _updateWithAcceptanceCheck(from, address(0), ids, values, "", true);
    }

    /// @notice Updates balances, then runs the ERC-1155 receiver acceptance check when `to` is not the zero
    ///         address. Every transfer, mint and burn path routes through here, as in OpenZeppelin v5.6.1.
    /// @dev `batch` names the operation type and alone picks the receiver hook: a batch operation calls
    ///      `onERC1155BatchReceived` even with a single id, and a single operation calls `onERC1155Received`.
    ///      OpenZeppelin v5.6.1 also keeps a five-argument overload that infers `batch` from `ids.length != 1`
    ///      for backwards compatibility; it is not ported, so no caller can pick the hook by array length.
    /// @param batch True for `safeBatchTransferFrom`, `_mintBatch` and `_burnBatch`.
    function _updateWithAcceptanceCheck(
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory values,
        bytes memory data,
        bool batch
    ) internal {
        _update(from, to, ids, values);
        if (to != address(0)) {
            address operator = msg.sender;
            if (batch) {
                _doSafeBatchTransferAcceptanceCheck(operator, from, to, ids, values, data);
            } else {
                _doSafeTransferAcceptanceCheck(operator, from, to, ids[0], values[0], data);
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

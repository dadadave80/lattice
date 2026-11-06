// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC20TemporaryApproval} from "@lattice/interfaces/tokens/IERC20TemporaryApproval.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

/// @dev Transient mapping root, not persistent storage. Derived with ERC-7201's formula:
/// `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC20TemporaryApproval")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC20_TEMPORARY_APPROVAL_STORAGE_SLOT =
    0xaa382fcf0bf54b576b3f55eb526cf1114e476579e700b2c0450079831fe05700;

/// @dev 0x42232a4c is `type(IERC20TemporaryApproval).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x42232a4c), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC20TEMPORARYAPPROVAL_SLOT =
    0xac7c974adc1627494c05d38379885274843f8308973f1cb430861ef9696b24b5;

/// @title ERC20TemporaryApprovalLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/token/ERC20/extensions/draft-ERC20TemporaryApproval.sol)
/// @notice ERC-7674 allowance logic shared by every ERC20Lib spender, without movement hooks.
/// @dev Matches OpenZeppelin v5.6.1 temporary-first, infinite and overflow semantics. Differences:
///      a stateless initializer registers ERC-165; msg.sender replaces _msgSender; native TLOAD/TSTORE use
///      a Lattice transient namespace. No events or persistent activation state. The shared ERC20Lib always
///      reads this mapping; the new facet opts into the public grant API without replacing base selectors.
///      Requires EIP-1153 on the execution chain. State belongs to the diamond under delegatecall.
library ERC20TemporaryApprovalLib {
    function __ERC20TemporaryApproval_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    function registerInterface() internal {
        assembly ("memory-safe") { sstore(ERC165_MAP_IERC20TEMPORARYAPPROVAL_SLOT, true) }
    }

    function temporaryApprove(address spender, uint256 value) internal returns (bool) {
        _temporaryApprove(msg.sender, spender, value);
        return true;
    }

    function temporaryAllowance(address owner, address spender) internal view returns (uint256 value) {
        bytes32 slot = _allowanceSlot(owner, spender);
        assembly ("memory-safe") { value := tload(slot) }
    }

    function _temporaryApprove(address owner, address spender, uint256 value) internal {
        if (owner == address(0)) revert IERC20.ERC20InvalidApprover(address(0));
        if (spender == address(0)) revert IERC20.ERC20InvalidSpender(address(0));
        bytes32 slot = _allowanceSlot(owner, spender);
        assembly ("memory-safe") { tstore(slot, value) }
    }

    /// @dev Returns the remainder to consume from persistent allowance. A covered spend never reads it.
    function spendTemporaryAllowance(address owner, address spender, uint256 value) internal returns (uint256) {
        uint256 available = temporaryAllowance(owner, spender);
        if (available == type(uint256).max) return 0;
        uint256 consumed = available < value ? available : value;
        if (consumed != 0) {
            _temporaryApprove(owner, spender, available - consumed);
            value -= consumed;
        }
        return value;
    }

    function _allowanceSlot(address owner, address spender) private pure returns (bytes32) {
        return keccak256(abi.encode(spender, keccak256(abi.encode(owner, ERC20_TEMPORARY_APPROVAL_STORAGE_SLOT))));
    }
}

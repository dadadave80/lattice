// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC1363, IERC1363Receiver, IERC1363Spender} from "@lattice/interfaces/tokens/IERC1363.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev 0xb0202a11 is `type(IERC1363).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xb0202a11), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC1363_SLOT = 0x0ebeb7a78f222e08be2c2d80a20fcc22cbe5dd2ddf53005dc602c88dd66185a1;

/// @title ERC1363Lib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC1363.sol)
/// @notice Library implementing ERC-1363 `transferAndCall`, `transferFromAndCall` and `approveAndCall` over the
///         {ERC20Lib} balances and allowances. Adds no own storage.
/// @dev Ports OpenZeppelin v5.6.1 `ERC1363` and `ERC1363Utils`. Differences from OpenZeppelin:
///      - The movement runs through {ERC20Lib.transfer}, {ERC20Lib.transferFrom} and {ERC20Lib.approve}, not the
///        diamond's `transfer`/`transferFrom`/`approve` selectors. OpenZeppelin calls the virtual functions, so an
///        override such as ERC20Pausable or ERC20Votes applies to `*AndCall` too. Here it does not: a facet that
///        `Replace`s the base transfer selectors (ERC20Pausable, ERC20Votes, GovernedVault) never sees these
///        movements. Decision D25 on #234 declares ERC1363 mutually exclusive with them.
///      - The caller is `msg.sender`, not `_msgSender()`; Lattice has no ERC-2771 context.
///      - {ERC20Lib} returns true or reverts, so the three `*Failed` errors are kept for parity but never fire.
///      - The `*Failed` and `Invalid*` errors live on {IERC1363} instead of the contract and `ERC1363Utils`.
library ERC1363Lib {
    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the IERC1363 interface for ERC-165 discovery.
    /// @dev Must be called inside a pre/postInitializer block. No own storage to initialize.
    function __ERC1363_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IERC1363 interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC1363_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            PAYABLE OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Moves `value` tokens from the caller to `to`, then calls {IERC1363Receiver-onTransferReceived}.
    function transferAndCall(address to, uint256 value, bytes memory data) internal returns (bool) {
        if (!ERC20Lib.transfer(to, value)) revert IERC1363.ERC1363TransferFailed(to, value);
        checkOnERC1363TransferReceived(msg.sender, msg.sender, to, value, data);
        return true;
    }

    /// @notice Moves `value` tokens from `from` to `to` using the caller's allowance, then calls
    ///         {IERC1363Receiver-onTransferReceived}.
    function transferFromAndCall(address from, address to, uint256 value, bytes memory data) internal returns (bool) {
        // slither-disable-next-line arbitrary-send-erc20 ERC20Lib spends msg.sender's allowance first
        if (!ERC20Lib.transferFrom(from, to, value)) revert IERC1363.ERC1363TransferFromFailed(from, to, value);
        checkOnERC1363TransferReceived(msg.sender, from, to, value, data);
        return true;
    }

    /// @notice Sets `value` as `spender`'s allowance over the caller's tokens, then calls
    ///         {IERC1363Spender-onApprovalReceived}.
    function approveAndCall(address spender, uint256 value, bytes memory data) internal returns (bool) {
        if (!ERC20Lib.approve(spender, value)) revert IERC1363.ERC1363ApproveFailed(spender, value);
        checkOnERC1363ApprovalReceived(msg.sender, spender, value, data);
        return true;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             RECIPIENT CHECKS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Calls {IERC1363Receiver-onTransferReceived} on `to` and requires it to accept.
    /// @dev Reverts {IERC1363.ERC1363InvalidReceiver} when `to` has no code, returns another value, or reverts with
    ///      no data. A revert with data is bubbled up unchanged.
    function checkOnERC1363TransferReceived(
        address operator,
        address from,
        address to,
        uint256 value,
        bytes memory data
    ) internal {
        if (to.code.length == 0) revert IERC1363.ERC1363InvalidReceiver(to);

        try IERC1363Receiver(to).onTransferReceived(operator, from, value, data) returns (bytes4 retval) {
            if (retval != IERC1363Receiver.onTransferReceived.selector) revert IERC1363.ERC1363InvalidReceiver(to);
        } catch (bytes memory reason) {
            if (reason.length == 0) revert IERC1363.ERC1363InvalidReceiver(to);
            assembly ("memory-safe") {
                revert(add(reason, 0x20), mload(reason))
            }
        }
    }

    /// @notice Calls {IERC1363Spender-onApprovalReceived} on `spender` and requires it to accept.
    /// @dev Reverts {IERC1363.ERC1363InvalidSpender} when `spender` has no code, returns another value, or reverts
    ///      with no data. A revert with data is bubbled up unchanged.
    function checkOnERC1363ApprovalReceived(address operator, address spender, uint256 value, bytes memory data)
        internal
    {
        if (spender.code.length == 0) revert IERC1363.ERC1363InvalidSpender(spender);

        try IERC1363Spender(spender).onApprovalReceived(operator, value, data) returns (bytes4 retval) {
            if (retval != IERC1363Spender.onApprovalReceived.selector) revert IERC1363.ERC1363InvalidSpender(spender);
        } catch (bytes memory reason) {
            if (reason.length == 0) revert IERC1363.ERC1363InvalidSpender(spender);
            assembly ("memory-safe") {
                revert(add(reason, 0x20), mload(reason))
            }
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC1155} from "@lattice/interfaces/tokens/IERC1155.sol";
import {ERC1155Lib} from "@lattice/tokens/ERC1155/libraries/ERC1155Lib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC1155Supply")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC1155SUPPLY_STORAGE_SLOT = 0x587745c63b1b33029f813b403978fa83db2954e4dd333c28aeae4b4e067ade00;

/// @dev 0xeac6339d is `type(IERC1155Supply).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xeac6339d), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC1155SUPPLY_SLOT = 0x1c1760c9fb8bc6a2feef129121ee2d30637b318349bcc0156b579ab5b5af6f16;

/// @notice Storage struct for the ERC-1155 supply-tracking module.
/// @custom:storage-location erc7201:lattice.storage.ERC1155Supply
struct ERC1155SupplyStorage {
    mapping(uint256 id => uint256) _totalSupply;
    uint256 _totalSupplyAll;
}

/// @title ERC1155SupplyLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC1155/extensions/ERC1155Supply.sol)
/// @notice Library implementing per-id and all-ids total supply tracking for ERC-1155 tokens.
/// @dev OpenZeppelin v5.6.1 overrides `_update`, so every mint and burn updates the counters. Lattice's base
///      {ERC1155Lib} has no hook (decision D25(a) on #234), so this library carries its own mint and burn paths:
///      {_update} runs {ERC1155Lib._update}, then the OpenZeppelin supply arithmetic, and {_updateWithAcceptanceCheck}
///      runs the receiver check after both, in OpenZeppelin's order. Differences from OpenZeppelin v5.6.1:
///      - Only mints and burns that go through this library are counted. A facet that mints or burns through
///        {ERC1155Lib} directly (including {ERC1155Burnable}'s `burn`) leaves the counters behind, and a later
///        burn through this library then wraps the unchecked subtraction. A mint facet on a supply-tracked diamond
///        must call {_mint}/{_mintBatch}, and the {ERC1155Supply} facet serves `burn`/`burnBatch` in place of
///        {ERC1155Burnable}'s.
///      - OpenZeppelin warns against adding this extension in an upgrade to a deployed token. On a diamond that
///        means: never cut {ERC1155Supply} into a diamond that already holds balances, since those balances are
///        not in the counters and burning them wraps.
///      - The supply views and burns are exported by a facet (OpenZeppelin's `burn`/`burnBatch` live in
///        `ERC1155Burnable`), and the views are advertised through ERC-165 as {IERC1155Supply}.
///      Overflow is as in OpenZeppelin: the mint arithmetic is checked, per id and across all ids (a global limit of
///      `type(uint256).max` tokens), and the burn arithmetic is unchecked. All state lives in its own ERC-7201 slot.
library ERC1155SupplyLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function erc1155SupplyStorage() internal pure returns (ERC1155SupplyStorage storage $) {
        assembly {
            $.slot := ERC1155SUPPLY_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the ERC-1155 supply module: registers IERC1155Supply via ERC-165.
    /// @dev Must be called inside a pre/postInitializer block. The counters start at zero, so the diamond must not
    ///      hold balances yet.
    function __ERC1155Supply_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IERC1155Supply interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC1155SUPPLY_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Total value of tokens of type `id`.
    function totalSupply(uint256 id) internal view returns (uint256) {
        return erc1155SupplyStorage()._totalSupply[id];
    }

    /// @notice Total value of tokens across every id.
    function totalSupply() internal view returns (uint256) {
        return erc1155SupplyStorage()._totalSupplyAll;
    }

    /// @notice Whether any token of type `id` exists.
    function exists(uint256 id) internal view returns (bool) {
        return totalSupply(id) > 0;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             BURN OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Destroys `value` tokens of type `id` from `account`, lowering the supply. The caller must be
    ///         `account` or an approved operator of `account` (as {ERC1155BurnableLib.burn}).
    function burn(address account, uint256 id, uint256 value) internal {
        ERC1155Lib._checkAuthorized(msg.sender, account);
        _burn(account, id, value);
    }

    /// @notice Batched version of {burn}.
    function burnBatch(address account, uint256[] memory ids, uint256[] memory values) internal {
        ERC1155Lib._checkAuthorized(msg.sender, account);
        _burnBatch(account, ids, values);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         SUPPLY-TRACKING INTERNALS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Mints `value` of token `id` to `to`, raising the supply. Supply-tracking {ERC1155Lib._mint}.
    function _mint(address to, uint256 id, uint256 value, bytes memory data) internal {
        if (to == address(0)) revert IERC1155.ERC1155InvalidReceiver(address(0));
        _updateWithAcceptanceCheck(
            address(0), to, ERC1155Lib._asSingletonArray(id), ERC1155Lib._asSingletonArray(value), data, false
        );
    }

    /// @notice Batch mints tokens to `to`, raising the supply. Supply-tracking {ERC1155Lib._mintBatch}.
    function _mintBatch(address to, uint256[] memory ids, uint256[] memory values, bytes memory data) internal {
        if (to == address(0)) revert IERC1155.ERC1155InvalidReceiver(address(0));
        _updateWithAcceptanceCheck(address(0), to, ids, values, data, true);
    }

    /// @notice Burns `value` of token `id` from `from`, lowering the supply. Supply-tracking {ERC1155Lib._burn}.
    function _burn(address from, uint256 id, uint256 value) internal {
        if (from == address(0)) revert IERC1155.ERC1155InvalidSender(address(0));
        _updateWithAcceptanceCheck(
            from, address(0), ERC1155Lib._asSingletonArray(id), ERC1155Lib._asSingletonArray(value), "", false
        );
    }

    /// @notice Batch burns tokens from `from`, lowering the supply. Supply-tracking {ERC1155Lib._burnBatch}.
    function _burnBatch(address from, uint256[] memory ids, uint256[] memory values) internal {
        if (from == address(0)) revert IERC1155.ERC1155InvalidSender(address(0));
        _updateWithAcceptanceCheck(from, address(0), ids, values, "", true);
    }

    /// @notice {_update}, then the receiver acceptance check when `to` is not the zero address. Mirrors
    ///         {ERC1155Lib._updateWithAcceptanceCheck}, so the receiver sees the updated supply.
    /// @param batch True for a batch operation: picks `onERC1155BatchReceived` over `onERC1155Received`.
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
                ERC1155Lib._doSafeBatchTransferAcceptanceCheck(operator, from, to, ids, values, data);
            } else {
                ERC1155Lib._doSafeTransferAcceptanceCheck(operator, from, to, ids[0], values[0], data);
            }
        }
    }

    /// @notice {ERC1155Lib._update}, then the supply counters: a mint (`from == 0`) raises them with checked
    ///         arithmetic, a burn (`to == 0`) lowers them unchecked. Port of OpenZeppelin v5.6.1
    ///         `ERC1155Supply._update`.
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values) internal {
        ERC1155Lib._update(from, to, ids, values);
        ERC1155SupplyStorage storage $ = erc1155SupplyStorage();

        if (from == address(0)) {
            uint256 totalMintValue = 0;
            for (uint256 i; i < ids.length; ++i) {
                uint256 value = values[i];
                // Overflow check required: the rest of the code assumes that totalSupply never overflows.
                $._totalSupply[ids[i]] += value;
                totalMintValue += value;
            }
            // Overflow check required: the rest of the code assumes that totalSupplyAll never overflows.
            $._totalSupplyAll += totalMintValue;
        }

        if (to == address(0)) {
            uint256 totalBurnValue = 0;
            for (uint256 i; i < ids.length; ++i) {
                uint256 value = values[i];
                unchecked {
                    // Overflow not possible: values[i] <= balanceOf(from, ids[i]) <= totalSupply(ids[i]).
                    $._totalSupply[ids[i]] -= value;
                    // Overflow not possible: sum_i(values[i]) <= sum_i(totalSupply(ids[i])) <= totalSupplyAll.
                    totalBurnValue += value;
                }
            }
            unchecked {
                // Overflow not possible: totalBurnValue = sum_i(values[i]) <= sum_i(totalSupply(ids[i])) <= totalSupplyAll.
                $._totalSupplyAll -= totalBurnValue;
            }
        }
    }
}

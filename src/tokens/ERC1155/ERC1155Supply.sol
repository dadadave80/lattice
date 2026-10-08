// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC1155Burnable} from "@lattice/interfaces/tokens/IERC1155Burnable.sol";
import {IERC1155Supply} from "@lattice/interfaces/tokens/IERC1155Supply.sol";
import {ERC1155SupplyLib} from "@lattice/tokens/ERC1155/libraries/ERC1155SupplyLib.sol";

/// @title ERC1155Supply
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC1155/extensions/ERC1155Supply.sol)
/// @notice Stateless Diamond facet tracking the total supply of each ERC-1155 id and of all ids.
/// @dev Owns ONLY its own selectors: the supply views `totalSupply(uint256)`, `totalSupply()` and `exists(uint256)`,
///      and supply-tracking `burn`/`burnBatch`. Under decision D25(a) on #234 the base {ERC1155Lib} has no hook, so
///      the burns that must lower the supply are served here, with {ERC1155Burnable}'s signatures and
///      authorization. That makes this facet MUTUALLY EXCLUSIVE with {ERC1155Burnable} and {ERC1155Pausable},
///      which export the same `burn`/`burnBatch` selectors: cut exactly one of the three. Transfers do not change
///      the supply, so the base {ERC1155} transfers stay. Mints come from an app-specific facet, which must mint
///      through {ERC1155SupplyLib._mint}/{ERC1155SupplyLib._mintBatch}. To track supply without burning, cut this
///      facet without its `burn`/`burnBatch` selectors. {DeployERC1155Supply} composes it with the base facet.
///      See {ERC1155SupplyLib} for every difference from OpenZeppelin v5.6.1. Pure delegator.
/// @custom:lattice-version 0.5.0
/// @custom:lattice-source OpenZeppelin v5.6.1
contract ERC1155Supply is IERC1155Supply, IERC1155Burnable {
    /// @inheritdoc IERC1155Supply
    function totalSupply(uint256 id) public view virtual returns (uint256) {
        return ERC1155SupplyLib.totalSupply(id);
    }

    /// @inheritdoc IERC1155Supply
    function totalSupply() public view virtual returns (uint256) {
        return ERC1155SupplyLib.totalSupply();
    }

    /// @inheritdoc IERC1155Supply
    function exists(uint256 id) public view virtual returns (bool) {
        return ERC1155SupplyLib.exists(id);
    }

    /// @notice Destroys `value` tokens of type `id` from `account` and lowers the supply.
    /// @dev The caller must be `account` or an operator approved by `account`.
    function burn(address account, uint256 id, uint256 value) public virtual {
        ERC1155SupplyLib.burn(account, id, value);
    }

    /// @notice Batched version of {burn}.
    /// @dev The caller must be `account` or an operator approved by `account`.
    function burnBatch(address account, uint256[] calldata ids, uint256[] calldata values) public virtual {
        ERC1155SupplyLib.burnBatch(account, ids, values);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC1155Supply methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `burn(address,uint256,uint256)` 0xf5298aca
    ///      `burnBatch(address,uint256[],uint256[])` 0x6b20c454
    ///      `exists(uint256)` 0x4f558e79
    ///      `totalSupply()` 0x18160ddd
    ///      `totalSupply(uint256)` 0xbd85b039
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"f5298aca6b20c4544f558e7918160dddbd85b039";
    }
}

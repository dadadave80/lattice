// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC1155Burnable} from "@lattice/interfaces/tokens/IERC1155Burnable.sol";
import {ERC1155BurnableLib} from "@lattice/tokens/ERC1155/libraries/ERC1155BurnableLib.sol";

/// @title ERC1155Burnable
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC1155/extensions/ERC1155Burnable.sol)
/// @notice Stateless Diamond facet adding burn operations to ERC-1155: holders and their approved operators can
///         destroy tokens.
/// @dev Owns ONLY its own selectors; the ERC-1155 base surface comes from a separately cut {ERC1155} facet, and
///      {DeployERC1155Burnable} composes both. Pure delegator to {ERC1155BurnableLib}. Under decision D25(a) on #234
///      this facet is MUTUALLY EXCLUSIVE with {ERC1155Supply} and {ERC1155Pausable}, which export the same
///      `burn`/`burnBatch` selectors: cut exactly one of the three. Its burns go through {ERC1155Lib} directly, so on a
///      diamond that tracks supply through {ERC1155SupplyLib} they would desync the supply counters, and on a pausable
///      diamond they would ignore the pause.
/// @custom:lattice-version 0.5.0
/// @custom:lattice-source OpenZeppelin v5.6.1
contract ERC1155Burnable is IERC1155Burnable {
    /// @inheritdoc IERC1155Burnable
    function burn(address account, uint256 id, uint256 value) public virtual {
        ERC1155BurnableLib.burn(account, id, value);
    }

    /// @inheritdoc IERC1155Burnable
    function burnBatch(address account, uint256[] calldata ids, uint256[] calldata values) public virtual {
        ERC1155BurnableLib.burnBatch(account, ids, values);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC1155Burnable methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `burn(address,uint256,uint256)` 0xf5298aca
    ///      `burnBatch(address,uint256[],uint256[])` 0x6b20c454
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"f5298aca6b20c454";
    }
}

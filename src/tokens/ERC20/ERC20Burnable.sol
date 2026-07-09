// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20Burnable} from "@lattice/interfaces/tokens/IERC20Burnable.sol";
import {ERC20BurnableLib} from "@lattice/tokens/ERC20/libraries/ERC20BurnableLib.sol";

/// @title ERC20Burnable
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Burnable.sol)
/// @notice Stateless Diamond facet adding burn operations to ERC-20.
/// @dev Inherits ERC20 and delegates burn/burnFrom to ERC20BurnableLib.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract ERC20Burnable is IERC20Burnable {
    /// @inheritdoc IERC20Burnable
    function burn(uint256 value) public virtual {
        ERC20BurnableLib.burn(value);
    }

    /// @inheritdoc IERC20Burnable
    function burnFrom(address account, uint256 value) public virtual {
        ERC20BurnableLib.burnFrom(account, value);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC20Burnable methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `burn(uint256)` 0x42966c68
    ///      `burnFrom(address,uint256)` 0x79cc6790
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"42966c6879cc6790";
    }
}

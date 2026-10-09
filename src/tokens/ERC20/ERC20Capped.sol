// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20Capped} from "@lattice/interfaces/tokens/IERC20Capped.sol";
import {ERC20CappedLib} from "@lattice/tokens/ERC20/libraries/ERC20CappedLib.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";

/// @title ERC20Capped
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Capped.sol)
/// @notice Stateless Diamond facet for ERC-20 tokens with a capped total supply.
/// @dev Exports only `cap()`. The internal `_mint` helper applies {ERC20CappedLib._checkCap} for a composing
///      facet that inherits it; it is not reachable through a diamond. {ERC20CappedLib} lists the differences
///      from OpenZeppelin.
///      Hook model (D25, #234): this is a mint-gating extension, and the cap holds only on that `_mint`. Unlike
///      OpenZeppelin, whose cap check runs in `_update`, every shipped facet that mints through {ERC20Lib} directly
///      skips it: ERC7802 `crosschainMint`, ERC20Crosschain `processMessage`, ERC20Wrapper `depositFor` (and the
///      library's internal `recover`), ERC4626, VaultCore and GovernedVault `deposit`/`mint`, the vote-aware
///      {ERC20VotesLib._mint}, and ERC20FlashMint `flashLoan` for the length of the loan. Each is mutually exclusive
///      with this facet. A facet that exposes `_mint` is in turn a direct mover for ERC20Pausable and ERC20Votes unless
///      it applies their checks too. See docs/guides/selector-compatibility.md#token-extension-hook-model.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.6.1
contract ERC20Capped is IERC20Capped {
    /// @inheritdoc IERC20Capped
    function cap() public view virtual returns (uint256) {
        return ERC20CappedLib.cap();
    }

    /// @notice Mints `value` tokens to `to`, reverting if the cap would be exceeded.
    /// @dev Callers are responsible for access control.
    function _mint(address to, uint256 value) internal virtual {
        ERC20CappedLib._checkCap(ERC20Lib.totalSupply() + value);
        ERC20Lib._mint(to, value);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC20Capped methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `cap()` 0x355274ea
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"355274ea";
    }
}

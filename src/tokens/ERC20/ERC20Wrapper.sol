// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20Wrapper} from "@lattice/interfaces/tokens/IERC20Wrapper.sol";
import {ERC20WrapperLib} from "@lattice/tokens/ERC20/libraries/ERC20WrapperLib.sol";

/// @title ERC20Wrapper
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Wrapper.sol)
/// @notice Stateless Diamond facet — wraps an underlying ERC-20 1:1. Pure delegator to {ERC20WrapperLib}.
/// @dev `recover()` is intentionally NOT exposed here: exposing it requires access control, so a deriving facet
///      adds it. `decimals()` overrides the base 18 to mirror the underlying.
///      CUSTODY: the internal `recover` mints the diamond's WHOLE underlying balance above total supply, so a
///      facet that exposes it also mints any other module's escrow of the underlying (an ERC-4626 vault,
///      VestingWallet, BridgeERC20 or ShieldedPool). One custodian per asset per diamond (issue #240).
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.6.1
contract ERC20Wrapper is IERC20Wrapper {
    /// @notice The wrapper decimals, mirroring the underlying token (replaces the base 18).
    function decimals() public view virtual returns (uint8) {
        return ERC20WrapperLib.decimals();
    }

    /// @inheritdoc IERC20Wrapper
    function underlying() public view virtual returns (address) {
        return ERC20WrapperLib.underlying();
    }

    /// @inheritdoc IERC20Wrapper
    function depositFor(address account, uint256 value) public virtual returns (bool) {
        return ERC20WrapperLib.depositFor(account, value);
    }

    /// @inheritdoc IERC20Wrapper
    function withdrawTo(address account, uint256 value) public virtual returns (bool) {
        return ERC20WrapperLib.withdrawTo(account, value);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC20Wrapper methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `decimals()` 0x313ce567
    ///      `depositFor(address,uint256)` 0x2f4f21e2
    ///      `underlying()` 0x6f307dc3
    ///      `withdrawTo(address,uint256)` 0x205c2878
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"313ce5672f4f21e26f307dc3205c2878";
    }
}

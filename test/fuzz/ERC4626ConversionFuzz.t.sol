// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC4626Lib, Rounding} from "@lattice/tokens/ERC4626/libraries/ERC4626Lib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Exposes the pure ERC-4626 conversion helpers, which take the totals explicitly.
contract ConversionHarness {
    function toShares(uint256 assets, uint256 supply, uint256 nav, uint8 offset, Rounding r)
        external
        pure
        returns (uint256)
    {
        return ERC4626Lib._convertToSharesFromTotals(assets, supply, nav, offset, r);
    }

    function toAssets(uint256 shares, uint256 supply, uint256 nav, uint8 offset, Rounding r)
        external
        pure
        returns (uint256)
    {
        return ERC4626Lib._convertToAssetsFromTotals(shares, supply, nav, offset, r);
    }
}

/// @title ERC4626ConversionFuzz
/// @notice Properties of `_convertToSharesFromTotals` / `_convertToAssetsFromTotals`, the pure share math every
///         ERC-4626 converter, preview and mutator feeds the vault's NAV into.
contract ERC4626ConversionFuzz is Test {
    ConversionHarness internal h;

    uint256 internal constant MAX = type(uint120).max;

    function setUp() public {
        h = new ConversionHarness();
    }

    function _bound(uint256 amount, uint256 supply, uint256 nav, uint8 offset)
        internal
        pure
        returns (uint256, uint256, uint256, uint8)
    {
        return (bound(amount, 0, MAX), bound(supply, 0, MAX), bound(nav, 0, MAX), uint8(bound(offset, 0, 18)));
    }

    /// @notice Ceil rounding is floor rounding plus at most one unit, in both directions.
    function testFuzz_CeilIsFloorPlusAtMostOne(uint256 amount, uint256 supply, uint256 nav, uint8 offset) public view {
        (amount, supply, nav, offset) = _bound(amount, supply, nav, offset);

        uint256 sf = h.toShares(amount, supply, nav, offset, Rounding.Floor);
        uint256 sc = h.toShares(amount, supply, nav, offset, Rounding.Ceil);
        assertLe(sf, sc, "shares: floor > ceil");
        assertLe(sc, sf + 1, "shares: ceil > floor + 1");

        uint256 af = h.toAssets(amount, supply, nav, offset, Rounding.Floor);
        uint256 ac = h.toAssets(amount, supply, nav, offset, Rounding.Ceil);
        assertLe(af, ac, "assets: floor > ceil");
        assertLe(ac, af + 1, "assets: ceil > floor + 1");
    }

    /// @notice Floor round trips never create value: assets -> shares -> assets and shares -> assets -> shares.
    ///         This also bounds `maxRedeem`: shares floored from the idle balance redeem for at most that idle.
    function testFuzz_FloorRoundTripsNeverInflate(uint256 amount, uint256 supply, uint256 nav, uint8 offset)
        public
        view
    {
        (amount, supply, nav, offset) = _bound(amount, supply, nav, offset);

        uint256 shares = h.toShares(amount, supply, nav, offset, Rounding.Floor);
        assertLe(h.toAssets(shares, supply, nav, offset, Rounding.Floor), amount, "assets->shares->assets inflated");

        uint256 assets = h.toAssets(amount, supply, nav, offset, Rounding.Floor);
        assertLe(h.toShares(assets, supply, nav, offset, Rounding.Floor), amount, "shares->assets->shares inflated");
    }

    /// @notice `withdraw` burns ceil shares: those shares are always worth at least the assets withdrawn.
    function testFuzz_CeilSharesCoverWithdrawnAssets(uint256 assets, uint256 supply, uint256 nav, uint8 offset)
        public
        view
    {
        (assets, supply, nav, offset) = _bound(assets, supply, nav, offset);

        uint256 burned = h.toShares(assets, supply, nav, offset, Rounding.Ceil);
        assertGe(h.toAssets(burned, supply, nav, offset, Rounding.Floor), assets, "burned shares undervalue assets");
    }

    /// @notice The dilution direction: a larger NAV never mints MORE shares for the same deposit, and never
    ///         values the same shares at fewer assets. Pricing on idle (a smaller NAV) over-mints.
    function testFuzz_LargerNavNeverOverMints(uint256 amount, uint256 supply, uint256 navA, uint256 navB, uint8 offset)
        public
        view
    {
        (amount, supply, navA, offset) = _bound(amount, supply, navA, offset);
        navB = bound(navB, navA, MAX);

        assertLe(
            h.toShares(amount, supply, navB, offset, Rounding.Floor),
            h.toShares(amount, supply, navA, offset, Rounding.Floor),
            "larger NAV minted more shares"
        );
        assertGe(
            h.toAssets(amount, supply, navB, offset, Rounding.Floor),
            h.toAssets(amount, supply, navA, offset, Rounding.Floor),
            "larger NAV valued shares lower"
        );
    }

    /// @notice An empty vault prices 1 asset at 10**offset shares (the OZ virtual-offset baseline).
    function testFuzz_EmptyVaultUsesVirtualOffset(uint256 assets, uint8 offset) public view {
        assets = bound(assets, 0, MAX);
        offset = uint8(bound(offset, 0, 18));
        assertEq(h.toShares(assets, 0, 0, offset, Rounding.Floor), assets * 10 ** offset, "virtual shares");
    }
}

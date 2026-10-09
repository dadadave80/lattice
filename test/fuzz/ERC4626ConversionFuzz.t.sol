// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FullMathReference} from "@lattice-test/helpers/FullMathReference.sol";
import {ERC4626Lib} from "@lattice/tokens/ERC4626/libraries/ERC4626Lib.sol";
import {Math} from "@lattice/utils/libraries/math/Math.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Exposes the pure ERC-4626 conversion helpers, which take the totals explicitly.
contract ConversionHarness {
    function toShares(uint256 assets, uint256 supply, uint256 nav, uint8 offset, Math.Rounding r)
        external
        pure
        returns (uint256)
    {
        return ERC4626Lib._convertToSharesFromTotals(assets, supply, nav, offset, r);
    }

    function toAssets(uint256 shares, uint256 supply, uint256 nav, uint8 offset, Math.Rounding r)
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

        uint256 sf = h.toShares(amount, supply, nav, offset, Math.Rounding.Floor);
        uint256 sc = h.toShares(amount, supply, nav, offset, Math.Rounding.Ceil);
        assertLe(sf, sc, "shares: floor > ceil");
        assertLe(sc, sf + 1, "shares: ceil > floor + 1");

        uint256 af = h.toAssets(amount, supply, nav, offset, Math.Rounding.Floor);
        uint256 ac = h.toAssets(amount, supply, nav, offset, Math.Rounding.Ceil);
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

        uint256 shares = h.toShares(amount, supply, nav, offset, Math.Rounding.Floor);
        assertLe(
            h.toAssets(shares, supply, nav, offset, Math.Rounding.Floor), amount, "assets->shares->assets inflated"
        );

        uint256 assets = h.toAssets(amount, supply, nav, offset, Math.Rounding.Floor);
        assertLe(
            h.toShares(assets, supply, nav, offset, Math.Rounding.Floor), amount, "shares->assets->shares inflated"
        );
    }

    /// @notice `withdraw` burns ceil shares: those shares are always worth at least the assets withdrawn.
    function testFuzz_CeilSharesCoverWithdrawnAssets(uint256 assets, uint256 supply, uint256 nav, uint8 offset)
        public
        view
    {
        (assets, supply, nav, offset) = _bound(assets, supply, nav, offset);

        uint256 burned = h.toShares(assets, supply, nav, offset, Math.Rounding.Ceil);
        assertGe(
            h.toAssets(burned, supply, nav, offset, Math.Rounding.Floor), assets, "burned shares undervalue assets"
        );
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
            h.toShares(amount, supply, navB, offset, Math.Rounding.Floor),
            h.toShares(amount, supply, navA, offset, Math.Rounding.Floor),
            "larger NAV minted more shares"
        );
        assertGe(
            h.toAssets(amount, supply, navB, offset, Math.Rounding.Floor),
            h.toAssets(amount, supply, navA, offset, Math.Rounding.Floor),
            "larger NAV valued shares lower"
        );
    }

    /// @notice An empty vault prices 1 asset at 10**offset shares (the OZ virtual-offset baseline).
    function testFuzz_EmptyVaultUsesVirtualOffset(uint256 assets, uint8 offset) public view {
        assets = bound(assets, 0, MAX);
        offset = uint8(bound(offset, 0, 18));
        assertEq(h.toShares(assets, 0, 0, offset, Math.Rounding.Floor), assets * 10 ** offset, "virtual shares");
    }

    /// @notice Differential: over all of uint256 and at offsets 0, 6 and 18, both converters equal the EIP-4626
    ///         virtual-offset formula evaluated by the independent 512-bit oracle, in every `Math.Rounding` mode —
    ///         and revert exactly where it has no uint256 answer (a 512-bit overflow, or `totalSupply + 10**offset`
    ///         / `totalAssets + 1` overflowing). Large operands drive `Math.mulDiv`'s 512-bit branch.
    /// forge-config: default.fuzz.runs = 512
    function testFuzz_ConvertersMatchEip4626Formula(
        uint256 amount,
        uint256 supply,
        uint256 nav,
        uint256 offsetIndex,
        uint8 mode
    ) public view {
        uint8 offset = [0, 6, 18][offsetIndex % 3];
        Math.Rounding r = Math.Rounding(mode % 4);
        bool roundUp = r == Math.Rounding.Ceil || r == Math.Rounding.Expand;

        // shares = amount * (supply + 10**offset) / (nav + 1); assets = amount * (nav + 1) / (supply + 10**offset).
        // A zero stands in for an overflowing virtual total; the oracle rejects a zero denominator, and the AND
        // with `totalsFit` covers the numerator side.
        bool totalsFit = supply <= type(uint256).max - 10 ** offset && nav < type(uint256).max;
        uint256 virtualSupply = totalsFit ? supply + 10 ** offset : 0;
        uint256 virtualAssets = totalsFit ? nav + 1 : 0;

        _assertConverter(
            abi.encodeCall(h.toShares, (amount, supply, nav, offset, r)),
            totalsFit,
            amount,
            virtualSupply,
            virtualAssets,
            roundUp,
            "toShares"
        );
        _assertConverter(
            abi.encodeCall(h.toAssets, (amount, supply, nav, offset, r)),
            totalsFit,
            amount,
            virtualAssets,
            virtualSupply,
            roundUp,
            "toAssets"
        );
    }

    /// @notice A floor of exactly `type(uint256).max` with a non-zero remainder: the round-up modes revert with
    ///         `Panic(0x11)` rather than wrap to 0 (which would price a `mint` at zero assets).
    /// @dev Offset 0 makes each converter `mulDiv(x, y, d)` with `y` and `d` passed as `total - 1`. Inputs are shaped
    ///      as in `MulDivDifferentialFuzz.testFuzz_MulDiv_CeilOverflowsAtMaxFloor`.
    function testFuzz_CeilPanicsAtMaxFloor(uint256 y) public view {
        y = bound(y, 3, type(uint256).max);
        uint256 r = type(uint256).max % y;
        vm.assume(r != 0 && r < y - 1);
        uint256 x = type(uint256).max - (type(uint256).max - r) / y;
        uint256 d = y - 1;

        for (uint8 mode; mode < 4; ++mode) {
            Math.Rounding rounding = Math.Rounding(mode);
            _assertMaxFloor(abi.encodeCall(h.toShares, (x, y - 1, d - 1, 0, rounding)), rounding, "toShares");
            _assertMaxFloor(abi.encodeCall(h.toAssets, (x, d - 1, y - 1, 0, rounding)), rounding, "toAssets");
        }
    }

    /// @dev Floor and Trunc return `type(uint256).max`; Ceil and Expand revert with exactly `Panic(0x11)`.
    function _assertMaxFloor(bytes memory data, Math.Rounding rounding, string memory label) internal view {
        (bool ok, bytes memory ret) = address(h).staticcall(data);
        if (rounding == Math.Rounding.Floor || rounding == Math.Rounding.Trunc) {
            assertTrue(ok, string.concat(label, ": floor reverted"));
            assertEq(abi.decode(ret, (uint256)), type(uint256).max, string.concat(label, ": floor"));
        } else {
            assertFalse(ok, string.concat(label, ": ceil did not revert"));
            assertEq(ret, abi.encodeWithSignature("Panic(uint256)", 0x11), string.concat(label, ": revert data"));
        }
    }

    /// @dev The converter call returns `amount * num / den` per the oracle, or reverts where it has no answer.
    function _assertConverter(
        bytes memory data,
        bool totalsFit,
        uint256 amount,
        uint256 num,
        uint256 den,
        bool roundUp,
        string memory label
    ) internal view {
        (bool okRef, uint256 expected) = FullMathReference.mulDiv(amount, num, den, roundUp);
        (bool ok, bytes memory ret) = address(h).staticcall(data);
        assertEq(ok, totalsFit && okRef, string.concat(label, ": revert domain"));
        if (ok) assertEq(abi.decode(ret, (uint256)), expected, string.concat(label, ": result"));
    }
}

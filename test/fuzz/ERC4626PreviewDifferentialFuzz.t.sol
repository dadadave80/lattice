// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployVaultCore} from "@lattice-script/base/defi/DeployVaultCore.s.sol";
import {ERC4626TestBase} from "@lattice-test/base/ERC4626TestBase.sol";
import {StrategyManagerTestBase} from "@lattice-test/base/StrategyManagerTestBase.sol";
import {VaultCoreTestBase} from "@lattice-test/base/VaultCoreTestBase.sol";
import {FullMathReference} from "@lattice-test/helpers/FullMathReference.sol";
import {IMintableToken} from "@lattice-test/helpers/IMintableToken.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {StrategyManager} from "@lattice/defi/StrategyManager.sol";
import {IVaultCore} from "@lattice/interfaces/defi/IVaultCore.sol";
import {IStrategy} from "@lattice/interfaces/external/yearn/IStrategy.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";
import {Test} from "forge-std/Test.sol";

/// @title Eip4626FormulaOracle
/// @notice The EIP-4626 virtual-offset formula evaluated by the independent 512-bit oracle over a test-side tally:
///         `shares = assets * (supply + 10**offset) / (nav + 1)` and its inverse, floored for `convertTo*` /
///         `previewDeposit` / `previewRedeem` and ceiled for `previewMint` / `previewWithdraw`. The tally (`Ref`) is
///         built from the deposits, donations and strategy flows the test itself makes and is never read back from
///         the vault, so a vault pricing on the wrong total fails `_assertTallies` and every preview.
abstract contract Eip4626FormulaOracle is Test {
    struct Ref {
        uint256 nav; // the total the vault must price on
        uint256 supply; // the share supply
        uint8 offset; // the vault's decimals offset
    }

    enum Kind {
        ToShares,
        ToAssets
    }

    function _toShares(Ref memory r, uint256 assets, bool roundUp) internal pure returns (bool, uint256) {
        return FullMathReference.mulDiv(assets, r.supply + 10 ** r.offset, r.nav + 1, roundUp);
    }

    function _toAssets(Ref memory r, uint256 shares, bool roundUp) internal pure returns (bool, uint256) {
        return FullMathReference.mulDiv(shares, r.nav + 1, r.supply + 10 ** r.offset, roundUp);
    }

    /// @dev The vault's reported totals equal the independent tally.
    function _assertTallies(IERC4626 v, Ref memory r) internal view {
        assertEq(v.totalAssets(), r.nav, "totalAssets differs from the tally");
        assertEq(v.totalSupply(), r.supply, "totalSupply differs from the tally");
    }

    /// @dev Every converter and preview equals the formula, or reverts exactly where it has no uint256 answer.
    ///      `query` is unbounded, so 512-bit products and overflow reverts are both exercised.
    function _assertPreviews(IERC4626 v, Ref memory r, uint256 query) internal view {
        _assertView(v, r, abi.encodeCall(IERC4626.convertToShares, (query)), Kind.ToShares, query, false);
        _assertView(v, r, abi.encodeCall(IERC4626.previewDeposit, (query)), Kind.ToShares, query, false);
        _assertView(v, r, abi.encodeCall(IERC4626.previewWithdraw, (query)), Kind.ToShares, query, true);
        _assertView(v, r, abi.encodeCall(IERC4626.convertToAssets, (query)), Kind.ToAssets, query, false);
        _assertView(v, r, abi.encodeCall(IERC4626.previewRedeem, (query)), Kind.ToAssets, query, false);
        _assertView(v, r, abi.encodeCall(IERC4626.previewMint, (query)), Kind.ToAssets, query, true);
    }

    /// @dev Makes the first deposit into an empty vault and credits it to the tally.
    function _seedDeposit(IERC4626 v, IMintableToken token, Ref memory r, uint256 assets) internal {
        if (assets == 0) return;
        (, uint256 shares) = _toShares(r, assets, false);
        token.mint(address(this), assets);
        token.approve(address(v), assets);
        assertEq(v.deposit(assets, address(this)), shares, "seed deposit mints formula shares");
        r.nav += assets;
        r.supply += shares;
    }

    /// @dev Deposits `assets` for `who`, then redeems the minted shares: both settle at the formula.
    function _assertDepositThenRedeem(IERC4626 v, IMintableToken token, Ref memory r, address who, uint256 assets)
        internal
    {
        (, uint256 shares) = _toShares(r, assets, false);
        token.mint(who, assets);
        vm.startPrank(who);
        token.approve(address(v), assets);
        assertEq(v.deposit(assets, who), shares, "deposit mints floor shares");
        r.nav += assets;
        r.supply += shares;
        _assertTallies(v, r);

        (, uint256 expectedAssets) = _toAssets(r, shares, false);
        assertEq(v.redeem(shares, who, who), expectedAssets, "redeem pays floor assets");
        vm.stopPrank();
    }

    function _assertView(IERC4626 v, Ref memory r, bytes memory data, Kind kind, uint256 query, bool roundUp)
        private
        view
    {
        (bool expectOk, uint256 expected) =
            kind == Kind.ToShares ? _toShares(r, query, roundUp) : _toAssets(r, query, roundUp);
        (bool ok, bytes memory ret) = address(v).staticcall(data);
        assertEq(ok, expectOk, "revert domain differs from the formula");
        if (ok) assertEq(abi.decode(ret, (uint256)), expected, "differs from the formula");
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                       ERC4626 RECIPE (NAV = IDLE)
//////////////////////////////////////////////////////////////////////////*//

/// @title ERC4626PreviewDifferentialFuzz
/// @notice Differential test of the ERC-4626 views and mutators on the PRODUCTION {DeployERC4626} vault diamond at
///         decimals offsets 0, 6 and 18 against {Eip4626FormulaOracle}. A fuzzed donation decouples the NAV from
///         the supply so the exchange rate is not 1:1. This diamond has no strategy, so its NAV is the idle
///         balance: the full-NAV (#214) path is covered by {VaultFullNavPreviewDifferentialFuzz} below.
contract ERC4626PreviewDifferentialFuzz is ERC4626TestBase, Eip4626FormulaOracle {
    IERC4626[3] internal vaults;
    uint8[3] internal offsets = [0, 6, 18];

    address internal depositor = address(0xD3);
    address internal donor = address(0xD0);

    function setUp() public override {
        super.setUp();
        vaults[0] = vault;
        vaults[1] = IERC4626(_deployVault(underlyingAddr, "Vault Token", "vVTK6", 6));
        vaults[2] = IERC4626(_deployVault(underlyingAddr, "Vault Token", "vVTK18", 18));
    }

    function testFuzz_PreviewsMatchEip4626Formula(
        uint256 vaultIndex,
        uint256 seedDeposit,
        uint256 donation,
        uint256 query
    ) public {
        (IERC4626 v, Ref memory r) = _seed(vaultIndex, seedDeposit, donation);
        _assertPreviews(v, r, query);
    }

    function testFuzz_DepositAndRedeemMatchEip4626Formula(
        uint256 vaultIndex,
        uint256 seedDeposit,
        uint256 donation,
        uint256 assets
    ) public {
        (IERC4626 v, Ref memory r) = _seed(vaultIndex, seedDeposit, donation);
        _assertDepositThenRedeem(v, underlying, r, depositor, bound(assets, 1, 1e36));
    }

    /// @dev Seeds a first deposit, then a direct donation so the NAV differs from the supply.
    function _seed(uint256 vaultIndex, uint256 seedDeposit, uint256 donation)
        internal
        returns (IERC4626 v, Ref memory r)
    {
        v = vaults[vaultIndex % 3];
        r.offset = offsets[vaultIndex % 3];
        _seedDeposit(v, underlying, r, bound(seedDeposit, 0, 1e36));

        donation = bound(donation, 0, 1e36);
        underlying.mint(donor, donation);
        vm.prank(donor);
        underlying.transfer(address(v), donation);
        r.nav += donation;
        _assertTallies(v, r);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//             VAULTCORE + STRATEGYMANAGER RECIPE (NAV = IDLE + STRATEGY)
//////////////////////////////////////////////////////////////////////////*//

/// @notice Strategy that holds the vault's allocated tokens and reports its live balance.
contract PreviewNavStrategy is IStrategy {
    IMintableToken public immutable token;

    constructor(IMintableToken token_) {
        token = token_;
    }

    function asset() external view override returns (address) {
        return address(token);
    }

    function totalAssetsManaged() external view override returns (uint256) {
        return token.balanceOf(address(this));
    }

    function withdraw(uint256 amount, address to) external override returns (uint256) {
        token.transfer(to, amount);
        return amount;
    }
}

/// @title VaultFullNavPreviewDifferentialFuzz
/// @notice The same differential on the PRODUCTION {DeployVaultCore} + {DeployStrategyManager} diamonds at decimals
///         offsets 0, 6 and 18, with a strategy holding a fuzzed share of the funds plus a nonzero yield, so the
///         pricing NAV (idle + strategy) always differs from the idle balance. The tally adds the seed deposit,
///         the idle donation and the strategy yield; a vault pricing on idle only (the #214 bug) fails it.
contract VaultFullNavPreviewDifferentialFuzz is VaultCoreTestBase, StrategyManagerTestBase, Eip4626FormulaOracle {
    IERC4626[3] internal vaults;
    StrategyManager[3] internal managers;
    PreviewNavStrategy[3] internal strategies;
    uint8[3] internal offsets = [0, 6, 18];

    address internal depositor = address(0xD3);
    address internal donor = address(0xD0);

    function setUp() public override {
        super.setUp();
        for (uint256 i; i < 3; ++i) {
            vaultDeployer = new DeployVaultCore();
            (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
                vaultDeployer.buildCuts(underlyingAddr, "Vault Share", "vSHARE", admin, offsets[i]);
            Lattice d = new Lattice();
            d.initialize(cuts, init, initCalldata);
            vaults[i] = IERC4626(address(d));

            managers[i] = StrategyManager(_deployStrategyManager(admin));
            strategies[i] = new PreviewNavStrategy(underlying);

            vm.startPrank(admin);
            IVaultCore(address(d)).setStrategyManager(address(managers[i]));
            managers[i].setVault(address(d));
            managers[i].addStrategy(address(strategies[i]), 5_000);
            vm.stopPrank();
        }
    }

    function testFuzz_PreviewsMatchEip4626Formula_FullNav(
        uint256 vaultIndex,
        uint256 seedDeposit,
        uint16 bps,
        uint256 yield_,
        uint256 donation,
        uint256 query
    ) public {
        (IERC4626 v, Ref memory r) = _seed(vaultIndex, seedDeposit, bps, yield_, donation);
        _assertPreviews(v, r, query);
    }

    function testFuzz_DepositAndRedeemMatchEip4626Formula_FullNav(
        uint256 vaultIndex,
        uint256 seedDeposit,
        uint16 bps,
        uint256 yield_,
        uint256 donation,
        uint256 assets
    ) public {
        (IERC4626 v, Ref memory r) = _seed(vaultIndex, seedDeposit, bps, yield_, donation);
        _assertDepositThenRedeem(v, underlying, r, depositor, bound(assets, 1, 1e36));
    }

    /// @dev Seeds a first deposit, allocates a fuzzed share of it to the strategy, accrues a nonzero strategy
    ///      yield and donates to the idle balance. Rebalancing moves funds without changing the NAV tally.
    function _seed(uint256 vaultIndex, uint256 seedDeposit, uint16 bps, uint256 yield_, uint256 donation)
        internal
        returns (IERC4626 v, Ref memory r)
    {
        uint256 i = vaultIndex % 3;
        v = vaults[i];
        r.offset = offsets[i];
        _seedDeposit(v, underlying, r, bound(seedDeposit, 1, 1e36));

        vm.prank(admin);
        managers[i].updateStrategyTarget(address(strategies[i]), uint16(bound(bps, 0, 10_000)));
        managers[i].rebalance();

        yield_ = bound(yield_, 1, 1e36);
        underlying.mint(address(strategies[i]), yield_);
        r.nav += yield_;

        donation = bound(donation, 0, 1e36);
        underlying.mint(donor, donation);
        vm.prank(donor);
        underlying.transfer(address(v), donation);
        r.nav += donation;

        assertGt(r.nav, underlying.balanceOf(address(v)), "NAV must exceed idle for this differential");
        _assertTallies(v, r);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {AaveV3Adapter} from "@lattice/defi/AaveV3Adapter.sol";
import {AaveV3AdapterLib} from "@lattice/defi/libraries/AaveV3AdapterLib.sol";
import {IAaveV3Adapter} from "@lattice/interfaces/defi/IAaveV3Adapter.sol";
import {IProtocolAdapter} from "@lattice/interfaces/defi/IProtocolAdapter.sol";
import {IAaveV3Pool} from "@lattice/interfaces/external/aave/IAaveV3Pool.sol";
import {ReentrancyGuardLib} from "@lattice/security/libraries/ReentrancyGuardLib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                          MOCK ASSET + ATOKEN
//////////////////////////////////////////////////////////////////////////*//

contract MockAsset {
    string public name = "USD Coin";
    string public symbol = "USDC";
    uint8 public decimals = 6;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 a) external {
        balanceOf[to] += a;
    }

    function transfer(address to, uint256 a) external returns (bool) {
        require(balanceOf[msg.sender] >= a, "bal");
        balanceOf[msg.sender] -= a;
        balanceOf[to] += a;
        return true;
    }

    function transferFrom(address f, address t, uint256 a) external returns (bool) {
        require(balanceOf[f] >= a, "bal");
        require(allowance[f][msg.sender] >= a, "allow");
        allowance[f][msg.sender] -= a;
        balanceOf[f] -= a;
        balanceOf[t] += a;
        return true;
    }

    function approve(address s, uint256 a) external returns (bool) {
        allowance[msg.sender][s] = a;
        return true;
    }
}

/// @notice Rebasing aToken: 1:1 with the supplied underlying. The mock Pool mints/burns it.
contract MockAToken {
    MockAsset public immutable underlying;
    mapping(address => uint256) public balanceOf;

    constructor(MockAsset u) {
        underlying = u;
    }

    function mint(address to, uint256 a) external {
        balanceOf[to] += a;
    }

    function burn(address from, uint256 a) external {
        balanceOf[from] -= a;
    }

    function scaledBalanceOf(address u) external view returns (uint256) {
        return balanceOf[u];
    }

    function UNDERLYING_ASSET_ADDRESS() external view returns (address) {
        return address(underlying);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                            MOCK AAVE V3 POOL
//////////////////////////////////////////////////////////////////////////*//

/// @notice Minimal Aave v3 Pool + AddressesProvider for supply/withdraw/borrow/repay/HF.
///         Holds supplied underlying; mints/burns the mock aToken 1:1. Tracks per-user debt so
///         the leverage tests (Task 8) reuse it. Health factor and account data are computed
///         from a configurable price + liquidation threshold.
contract MockAaveV3Pool {
    MockAsset public asset;
    MockAToken public aToken;

    mapping(address => uint256) public debt; // underlying-denominated variable debt

    // Account-data knobs (Task 8 sets these; supply-only tests leave price=1e8, lt=8000).
    uint256 public priceBase8 = 1e8; // asset price in base ccy (8 decimals) — $1
    uint256 public liqThresholdBps = 8_000; // 80% liquidation threshold
    uint8 public eMode;

    function setAToken(MockAsset a, MockAToken at) external {
        asset = a;
        aToken = at;
    }

    function setPrice(uint256 p8) external {
        priceBase8 = p8;
    }

    function setLiqThreshold(uint256 bps) external {
        liqThresholdBps = bps;
    }

    // --- IPoolAddressesProvider (this contract doubles as the provider) ---
    function getPool() external view returns (address) {
        return address(this);
    }

    function getPriceOracle() external view returns (address) {
        return address(this);
    }

    // --- IAaveOracle (this contract doubles as the price oracle) ---
    // Returns the asset price in base ccy (8 decimals) — the SAME `priceBase8` that drives
    // getUserAccountData, so the adapter's Aave-oracle net-equity path is self-consistent.
    function getAssetPrice(address) external view returns (uint256) {
        return priceBase8;
    }

    // --- IAaveV3Pool ---
    function getReserveData(address) external view returns (IAaveV3Pool.ReserveData memory d) {
        d.aTokenAddress = address(aToken);
        d.variableDebtTokenAddress = address(0xDEB7);
    }

    function supply(address, uint256 amount, address onBehalfOf, uint16) external {
        require(asset.transferFrom(msg.sender, address(this), amount), "pull");
        aToken.mint(onBehalfOf, amount);
    }

    function withdraw(address, uint256 amount, address to) external returns (uint256) {
        uint256 bal = aToken.balanceOf(msg.sender);
        uint256 amt = amount > bal ? bal : amount;
        aToken.burn(msg.sender, amt);
        require(asset.transfer(to, amt), "send");
        return amt;
    }

    function borrow(address, uint256 amount, uint256, uint16, address onBehalfOf) external {
        debt[onBehalfOf] += amount;
        require(asset.transfer(msg.sender, amount), "borrow-send");
    }

    function repay(address, uint256 amount, uint256, address onBehalfOf) external returns (uint256) {
        uint256 d = debt[onBehalfOf];
        uint256 amt = amount > d ? d : amount;
        require(asset.transferFrom(msg.sender, address(this), amt), "repay-pull");
        debt[onBehalfOf] -= amt;
        return amt;
    }

    function setUserEMode(uint8 c) external {
        eMode = c;
    }

    function getUserEMode(address) external view returns (uint256) {
        return eMode;
    }

    /// @dev base-ccy amounts (8 decimals): value = balance(6d) * price(8d) / 1e6.
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        uint256 collat = aToken.balanceOf(user) * priceBase8 / 1e6;
        uint256 d = debt[user] * priceBase8 / 1e6;
        totalCollateralBase = collat;
        totalDebtBase = d;
        currentLiquidationThreshold = liqThresholdBps;
        ltv = liqThresholdBps;
        availableBorrowsBase = collat * liqThresholdBps / 10_000 > d ? collat * liqThresholdBps / 10_000 - d : 0;
        // HF = collateral * liqThreshold / debt, WAD. No debt => max.
        healthFactor = d == 0 ? type(uint256).max : (collat * liqThresholdBps / 10_000) * 1e18 / d;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                          MOCK ADAPTER FACET
//////////////////////////////////////////////////////////////////////////*//

contract MockAaveAdapter is AaveV3Adapter, Initializable {
    function initialize(
        address admin_,
        address provider_,
        address asset_,
        address vault_,
        address rewardRecipient_,
        bytes32 feedKey_,
        uint256 minHf_
    ) external initializer {
        AccessControlLib.__AccessControl_init(admin_);
        ReentrancyGuardLib.__ReentrancyGuard_init();
        AaveV3AdapterLib.__AaveV3Adapter_init(provider_, asset_, vault_, rewardRecipient_, feedKey_, minHf_);
    }

    function supportsInterface(bytes4 id) external view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                              TEST SUITE
//////////////////////////////////////////////////////////////////////////*//

contract AaveV3AdapterSupplyTest is Test {
    MockAsset asset;
    MockAToken aToken;
    MockAaveV3Pool pool;
    MockAaveAdapter adapter;

    address admin = address(0xAD);
    address vault = address(0x7A17);
    address treasury = address(0x7E0);
    bytes32 constant FEED_KEY = keccak256("USDC/USD");

    function setUp() public {
        asset = new MockAsset();
        aToken = new MockAToken(asset);
        pool = new MockAaveV3Pool();
        pool.setAToken(asset, aToken);

        adapter = new MockAaveAdapter();
        // provider == pool (the mock doubles as the provider).
        adapter.initialize(admin, address(pool), address(asset), vault, treasury, FEED_KEY, 1.05e18);
        // Authorize this test contract as the operator so the direct deploy/withdraw/harvest calls
        // (which the StrategyManager would make in production) pass the operator gate.
        vm.prank(admin);
        adapter.setOperator(address(this));
    }

    function test_AssetAndConfig() public view {
        assertEq(adapter.asset(), address(asset));
        assertEq(adapter.vault(), vault);
        assertEq(adapter.addressesProvider(), address(pool));
        assertEq(adapter.aToken(), address(aToken));
        assertEq(adapter.rewardRecipient(), treasury);
        assertEq(adapter.minHealthFactor(), 1.05e18);
    }

    function test_Deploy_SuppliesIdleBalance() public {
        asset.mint(address(adapter), 1_000e6);
        uint256 deployed = adapter.deploy();
        assertEq(deployed, 1_000e6, "deployed full idle");
        assertEq(aToken.balanceOf(address(adapter)), 1_000e6, "aToken minted 1:1");
        assertEq(asset.balanceOf(address(adapter)), 0, "idle swept");
    }

    function test_TotalAssetsManaged_IsAtokenBalanceWhenNoDebt() public {
        asset.mint(address(adapter), 500e6);
        adapter.deploy();
        assertEq(adapter.totalAssetsManaged(), 500e6, "1:1 supply valuation");
    }

    function test_Deploy_RevertsWhenNothingToDeploy() public {
        vm.expectRevert(IProtocolAdapter.ProtocolAdapterNothingToDeploy.selector);
        adapter.deploy();
    }

    function test_Withdraw_ReturnsRealAmountToVault() public {
        asset.mint(address(adapter), 1_000e6);
        adapter.deploy();

        // Manager pulls 400 back to the vault.
        uint256 got = adapter.withdraw(400e6, vault);
        assertEq(got, 400e6, "real withdrawn");
        assertEq(asset.balanceOf(vault), 400e6, "vault received");
        assertEq(adapter.totalAssetsManaged(), 600e6, "remaining supplied");
    }

    function test_Withdraw_ShortfallHonest_WhenRequestExceedsSupply() public {
        asset.mint(address(adapter), 200e6);
        adapter.deploy();

        // Ask for more than supplied; adapter returns the real (capped) amount.
        uint256 got = adapter.withdraw(1_000e6, vault);
        assertEq(got, 200e6, "honest: capped at supplied");
        assertEq(asset.balanceOf(vault), 200e6, "vault got available");
    }

    function test_HealthFactor_MaxWhenNoDebt() public {
        asset.mint(address(adapter), 100e6);
        adapter.deploy();
        assertEq(adapter.healthFactor(), type(uint256).max, "no debt => max HF");
    }

    function test_SupportsInterface_ProtocolAndAaveAdapter() public view {
        assertTrue(adapter.supportsInterface(type(IProtocolAdapter).interfaceId), "IProtocolAdapter");
        assertTrue(adapter.supportsInterface(type(IAaveV3Adapter).interfaceId), "IAaveV3Adapter");
    }
}

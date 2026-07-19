// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title AMMVaultTest
/// @notice Integration test composing ChainlinkAdapter + an oracle-aware ERC-4626 vault.
///
/// Design choice: "Oracle-aware vault" composition.
///
/// The spec offered two options:
///   A) ConstantProduct AMM + ERC4626 over LP shares (complex: AMM LP tokens are
///      tracked internally and have no separate ERC-20, requiring extra bridge logic).
///   B) ChainlinkAdapter + ERC4626 vault where totalAssets() is priced by the oracle.
///
/// Option B is chosen because it cleanly composes two Lattice modules without requiring
/// any out-of-scope bridge contracts. The test demonstrates:
///   1. Deploy MockAggregator returning an initial price.
///   2. Deploy MockOracleVault (ERC4626 + ChainlinkAdapter + AccessControl).
///   3. Register the feed; deposit idle tokens.
///   4. totalAssets() = idleBalance * price / 1e18.
///   5. Price doubles → totalAssets doubles → new depositor gets fewer shares.
///   6. Price halves → new depositor gets more shares.
///   7. Stale feed reverts latestAnswer.

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAggregatorV3} from "@lattice/interfaces/external/chainlink/IAggregatorV3.sol";
import {IChainlinkAdapter} from "@lattice/interfaces/oracles/IChainlinkAdapter.sol";
import {ChainlinkAdapter} from "@lattice/oracles/ChainlinkAdapter.sol";
import {ChainlinkAdapterLib} from "@lattice/oracles/libraries/ChainlinkAdapterLib.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                         MOCK AGGREGATOR V3
//////////////////////////////////////////////////////////////////////////*//

/// @notice Minimal mock AggregatorV3 with settable price data.
contract MockPriceAggregator is IAggregatorV3 {
    uint8 public decimals = 8; // typical Chainlink USD feed
    string public description = "MOCK/USD";

    int256 public latestPrice;
    uint256 public latestUpdatedAt;
    uint80 public latestRoundId = 1;

    constructor(int256 initialPrice) {
        latestPrice = initialPrice;
        latestUpdatedAt = block.timestamp;
    }

    function setPrice(int256 price) external {
        latestPrice = price;
        latestUpdatedAt = block.timestamp;
        latestRoundId++;
    }

    function setUpdatedAt(uint256 updatedAt) external {
        latestUpdatedAt = updatedAt;
    }

    function latestRoundData() external view override returns (uint80, int256, uint256, uint256, uint80) {
        return (latestRoundId, latestPrice, block.timestamp, latestUpdatedAt, latestRoundId);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                         SIMPLE UNDERLYING TOKEN
//////////////////////////////////////////////////////////////////////////*//

/// @notice Minimal ERC-20 used as the vault's underlying asset.
contract OracleAssetToken {
    string public name = "Oracle Asset";
    string public symbol = "OAT";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        require(allowance[from][msg.sender] >= amount, "allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                       ORACLE-AWARE VAULT MOCK
//////////////////////////////////////////////////////////////////////////*//

/// @notice ERC-4626-style vault that uses a Chainlink feed to value its idle assets.
///
/// @dev Architecture note: ERC4626Lib.totalAssets() is hardcoded to `asset.balanceOf(this)`
///      and cannot be overridden in the library-based Diamond pattern (there is no virtual
///      dispatch from library internal calls). This vault therefore implements its own
///      share-pricing math on top of ChainlinkAdapter and ERC20Lib, demonstrating the
///      composition: oracle-priced assets drive deposit/withdraw share calculations.
///
///      totalAssets() = idleBalance * priceWad / 1e18.
///      Shares are minted proportionally to the oracle-valued totalAssets.
contract MockOracleVault is AccessControl, ChainlinkAdapter {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(AccessControl, ChainlinkAdapter) returns (bytes memory) {}
    bytes32 public immutable PRICE_KEY;
    OracleAssetToken private _assetToken;

    // ERC-20 share token state (minimal, for testing).
    mapping(address => uint256) private _shares;
    uint256 private _totalShares;

    uint256 private constant VIRTUAL_SHARES = 1; // inflation-attack guard
    uint256 private constant VIRTUAL_ASSETS = 1;

    constructor(bytes32 priceKey) {
        PRICE_KEY = priceKey;
    }

    function initialize(address asset_, address admin_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin_);
        ChainlinkAdapterLib.__ChainlinkAdapter_init();
        _assetToken = OracleAssetToken(asset_);
        InitializableLib.postInitializer(s);
    }

    // --- View functions ---

    function asset() external view returns (address) {
        return address(_assetToken);
    }

    /// @notice Oracle-priced total assets.
    function totalAssets() public view returns (uint256) {
        uint256 idleBalance = _assetToken.balanceOf(address(this));
        int256 priceWad = ChainlinkAdapterLib.latestAnswer(PRICE_KEY);
        if (priceWad <= 0) return idleBalance;
        return (idleBalance * uint256(priceWad)) / 1e18;
    }

    function totalSupply() external view returns (uint256) {
        return _totalShares;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _shares[account];
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = _totalShares + VIRTUAL_SHARES;
        uint256 total = totalAssets() + VIRTUAL_ASSETS;
        return (assets * supply) / total;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = _totalShares + VIRTUAL_SHARES;
        uint256 total = totalAssets() + VIRTUAL_ASSETS;
        return (shares * total) / supply;
    }

    // --- State-changing functions ---

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        shares = convertToShares(assets);
        require(shares > 0, "zero shares");
        _assetToken.transferFrom(msg.sender, address(this), assets);
        _shares[receiver] += shares;
        _totalShares += shares;
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        require(_shares[owner] >= shares, "insufficient shares");
        assets = convertToAssets(shares);
        _shares[owner] -= shares;
        _totalShares -= shares;
        _assetToken.transfer(receiver, assets);
    }

    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                              TEST SUITE
//////////////////////////////////////////////////////////////////////////*//

contract AMMVaultTest is Test {
    bytes32 constant PRICE_KEY = keccak256("MOCK/USD");
    uint48 constant MAX_STALENESS = 3600; // 1 hour
    int256 constant INITIAL_PRICE_8DEC = 1e8; // 1.00 (8 decimals — typical Chainlink)

    OracleAssetToken asset;
    MockPriceAggregator feed;
    MockOracleVault vault;

    address admin = address(0xAD);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    uint256 constant DEPOSIT = 1_000e18;

    function setUp() public {
        vm.warp(10_000);

        // 1. Deploy mock aggregator at $1 (8-decimal feed → 1e8).
        feed = new MockPriceAggregator(INITIAL_PRICE_8DEC);

        // 2. Deploy asset token.
        asset = new OracleAssetToken();

        // 3. Deploy oracle vault.
        vault = new MockOracleVault(PRICE_KEY);
        vault.initialize(address(asset), admin);

        // 4. Register the price feed.
        vm.prank(admin);
        vault.registerFeed(PRICE_KEY, address(feed), MAX_STALENESS);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         FEED CONFIGURATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Feed is registered and returns the correct address.
    function test_OracleVault_FeedRegistered() public view {
        (address registeredFeed, uint48 staleness) = vault.getFeed(PRICE_KEY);
        assertEq(registeredFeed, address(feed));
        assertEq(staleness, MAX_STALENESS);
    }

    /// @notice latestAnswer returns the 8-decimal price scaled to WAD.
    function test_OracleVault_InitialPriceScaledToWad() public view {
        int256 answerWad = vault.latestAnswer(PRICE_KEY);
        // 1e8 with 8 decimals → 1e18 after scaling.
        assertEq(answerWad, 1e18);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         TOTAL ASSETS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice totalAssets = idle * price (at price=1 the result equals the balance).
    function test_OracleVault_TotalAssetsAtParPrice() public {
        asset.mint(address(vault), DEPOSIT);

        // price = 1e18 (WAD), so totalAssets = DEPOSIT * 1e18 / 1e18 = DEPOSIT.
        assertEq(vault.totalAssets(), DEPOSIT);
    }

    /// @notice When the price doubles, totalAssets doubles.
    function test_OracleVault_TotalAssetsDoubleWhenPriceDoubles() public {
        asset.mint(address(vault), DEPOSIT);

        // Advance time by 1 second so the feed update is fresh.
        vm.warp(block.timestamp + 1);
        feed.setPrice(2 * INITIAL_PRICE_8DEC); // price = $2

        // totalAssets should now be 2 × DEPOSIT.
        assertEq(vault.totalAssets(), 2 * DEPOSIT);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         SHARE PRICING
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice First depositor at price=1 gets shares 1:1.
    function test_OracleVault_FirstDepositAtParGets1to1Shares() public {
        asset.mint(alice, DEPOSIT);
        vm.startPrank(alice);
        asset.approve(address(vault), DEPOSIT);
        uint256 shares = vault.deposit(DEPOSIT, alice);
        vm.stopPrank();

        // At initial price (1:1), alice gets DEPOSIT shares.
        assertEq(shares, DEPOSIT, "1:1 share ratio at par");
        assertEq(vault.balanceOf(alice), DEPOSIT);
    }

    /// @notice When price doubles AFTER first deposit, a new depositor gets fewer shares.
    function test_OracleVault_HigherPriceResultsInFewerShares() public {
        // Alice deposits at price = $1.
        asset.mint(alice, DEPOSIT);
        vm.startPrank(alice);
        asset.approve(address(vault), DEPOSIT);
        vault.deposit(DEPOSIT, alice);
        vm.stopPrank();

        // Price doubles.
        vm.warp(block.timestamp + 1);
        feed.setPrice(2 * INITIAL_PRICE_8DEC);

        // Bob deposits the same DEPOSIT amount at price = $2.
        // Vault totalAssets was DEPOSIT * 1 = DEPOSIT when alice deposited.
        // Now totalAssets = DEPOSIT * 2 (idle) + incoming.
        // Wait — the vault recalculates totalAssets using the *current* oracle price,
        // which includes existing idle assets at the new price.
        // shares_bob = DEPOSIT * totalSupply / totalAssets_before_deposit
        //            = DEPOSIT * DEPOSIT / (DEPOSIT * 2) = DEPOSIT / 2.
        asset.mint(bob, DEPOSIT);
        vm.startPrank(bob);
        asset.approve(address(vault), DEPOSIT);
        uint256 bobShares = vault.deposit(DEPOSIT, bob);
        vm.stopPrank();

        // Bob should receive fewer shares than alice (half, since price doubled).
        assertLt(bobShares, vault.balanceOf(alice), "bob gets fewer shares at higher price");
        // At exactly 2x price: bob gets DEPOSIT/2 shares.
        assertApproxEqAbs(bobShares, DEPOSIT / 2, 1, "bob gets half the shares at 2x price");
    }

    /// @notice When price halves, a new depositor gets more shares for the same asset amount.
    function test_OracleVault_LowerPriceResultsInMoreShares() public {
        // Alice deposits at price = $1.
        asset.mint(alice, DEPOSIT);
        vm.startPrank(alice);
        asset.approve(address(vault), DEPOSIT);
        vault.deposit(DEPOSIT, alice);
        vm.stopPrank();

        uint256 aliceShares = vault.balanceOf(alice);

        // Price halves.
        vm.warp(block.timestamp + 1);
        feed.setPrice(INITIAL_PRICE_8DEC / 2); // $0.50

        // Bob deposits at price = $0.50.
        // totalAssets = DEPOSIT * 0.5 = DEPOSIT/2.
        // totalSupply = DEPOSIT (alice's shares).
        // bobShares = DEPOSIT * DEPOSIT / (DEPOSIT/2) = DEPOSIT * 2.
        asset.mint(bob, DEPOSIT);
        vm.startPrank(bob);
        asset.approve(address(vault), DEPOSIT);
        uint256 bobShares = vault.deposit(DEPOSIT, bob);
        vm.stopPrank();

        // Bob receives more shares than alice.
        assertGt(bobShares, aliceShares, "bob gets more shares at lower price");
        // Allow rounding tolerance from virtual share / virtual asset anti-inflation guards.
        assertApproxEqAbs(bobShares, 2 * DEPOSIT, 10, "bob gets double the shares at 0.5x price");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         STALENESS CHECK
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice latestAnswer reverts when the feed data is stale.
    function test_OracleVault_StaleDataReverts() public {
        uint256 updatedAt = block.timestamp; // recorded when setUp ran
        // Warp forward past the max staleness window without updating the feed.
        vm.warp(block.timestamp + MAX_STALENESS + 1);

        vm.expectRevert(
            abi.encodeWithSelector(IChainlinkAdapter.ChainlinkStaleData.selector, PRICE_KEY, updatedAt, MAX_STALENESS)
        );
        vault.latestAnswer(PRICE_KEY);
    }

    /// @notice After staleness, updating the feed makes latestAnswer valid again.
    function test_OracleVault_StaleDataClearedByNewPrice() public {
        vm.warp(block.timestamp + MAX_STALENESS + 1);

        // Feed is stale — update with fresh data.
        feed.setPrice(3 * INITIAL_PRICE_8DEC);

        // Now the feed should be fresh.
        int256 answerWad = vault.latestAnswer(PRICE_KEY);
        assertEq(answerWad, 3e18);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                     FEED MANAGEMENT
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Only admin can register a feed.
    function test_OracleVault_RegisterFeedRequiresAdmin() public {
        bytes32 newKey = keccak256("NEW/USD");
        MockPriceAggregator newFeed = new MockPriceAggregator(1e8);

        vm.prank(alice);
        vm.expectRevert(); // AccessControlUnauthorizedAccount
        vault.registerFeed(newKey, address(newFeed), MAX_STALENESS);
    }

    /// @notice Admin can unregister a feed; subsequent queries revert.
    function test_OracleVault_UnregisterFeed() public {
        vm.prank(admin);
        vault.unregisterFeed(PRICE_KEY);

        vm.expectRevert(abi.encodeWithSelector(IChainlinkAdapter.ChainlinkFeedNotRegistered.selector, PRICE_KEY));
        vault.latestAnswer(PRICE_KEY);
    }
}

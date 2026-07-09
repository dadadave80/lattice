// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {ERC4626TestBase} from "@lattice-test/base/ERC4626TestBase.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";

//*//////////////////////////////////////////////////////////////////////////
//                    MOCK USDT-STYLE TOKEN (no return value)
//////////////////////////////////////////////////////////////////////////*//

/// @notice Mimics USDT / BNB: transferFrom and transfer do NOT return a bool.
/// The ABI omits the return value so the encoded returndata length is 0.
/// @dev An EXTERNAL weird-token fixture (not the facet under test) — the vault itself still runs in a real
///      diamond. Kept to prove the vault's SafeERC20 handling and oversize-decimals fallback.
contract MockNoReturnERC20 {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    /// @dev Intentionally has no return value — just like USDT.
    function transfer(address to, uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
    }

    /// @dev Intentionally has no return value — just like USDT.
    function transferFrom(address from, address to, uint256 amount) external {
        require(balanceOf[from] >= amount, "insufficient");
        require(allowance[from][msg.sender] >= amount, "allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
    }

    /// @dev Returns a uint256 larger than type(uint8).max so naive uint8-cast truncates.
    function decimals() external pure returns (uint256) {
        return 300;
    }

    function name() external pure returns (string memory) {
        return "NoReturn";
    }

    function symbol() external pure returns (string memory) {
        return "NRT";
    }

    function totalSupply() external pure returns (uint256) {
        return 0;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                                 TESTS
//////////////////////////////////////////////////////////////////////////*//

/// @title ERC4626Test
/// @notice Comprehensive tests for the ERC-4626 tokenized vault module, exercised through a REAL {Diamond}
///         assembled by the ready-to-deploy {DeployERC4626} script (see {ERC4626TestBase}). The underlying
///         asset is itself a real base ERC-20 diamond ({DeployERC20} + {TokenTestFacet}); every vault call
///         routes through the diamond's `delegatecall` dispatch, not a flattened inheritance mock.
///         `supportsInterface` comes from the cut-in `ERC165Facet`.
contract ERC4626Test is ERC4626TestBase {
    address alice = address(0xA1);
    address bob = address(0xB0B);
    address charlie = address(0xC4);

    uint256 constant INITIAL_MINT = 1_000e18;

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    function setUp() public override {
        super.setUp(); // deploys the underlying ERC-20 diamond + the ERC-4626 vault diamond, wires handles

        // Mint initial supply to alice and bob.
        underlying.mint(alice, INITIAL_MINT);
        underlying.mint(bob, INITIAL_MINT);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           INITIAL STATE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_AssetReturnsUnderlying() public view {
        assertEq(vault.asset(), underlyingAddr);
    }

    function test_TotalAssetsStartsAtZero() public view {
        assertEq(vault.totalAssets(), 0);
    }

    function test_TotalSupplyStartsAtZero() public view {
        assertEq(vault.totalSupply(), 0);
    }

    function test_DecimalsEqualsUnderlyingPlusOffset() public view {
        // underlying has 18 decimals, offset is 0 → vault decimals = 18
        assertEq(vault.decimals(), 18);
    }

    function test_NameAndSymbol() public view {
        assertEq(vault.name(), "Vault Token");
        assertEq(vault.symbol(), "vVTK");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           MAX FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_MaxDepositReturnsUint256Max() public view {
        assertEq(vault.maxDeposit(alice), type(uint256).max);
    }

    function test_MaxMintReturnsUint256Max() public view {
        assertEq(vault.maxMint(alice), type(uint256).max);
    }

    function test_MaxWithdrawReturnsZeroBeforeDeposit() public view {
        assertEq(vault.maxWithdraw(alice), 0);
    }

    function test_MaxRedeemReturnsZeroBeforeDeposit() public view {
        assertEq(vault.maxRedeem(alice), 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         CONVERT FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_ConvertToSharesEmptyVault() public view {
        // Empty vault: 1 asset → 1 share (virtual denominator = 1)
        assertEq(vault.convertToShares(1e18), 1e18);
    }

    function test_ConvertToAssetsEmptyVault() public view {
        assertEq(vault.convertToAssets(1e18), 1e18);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           PREVIEW FUNCTIONS TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_PreviewDepositMatchesConvertToShares() public view {
        assertEq(vault.previewDeposit(1e18), vault.convertToShares(1e18));
    }

    function test_PreviewRedeemMatchesConvertToAssets() public view {
        assertEq(vault.previewRedeem(1e18), vault.convertToAssets(1e18));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              DEPOSIT TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_DepositTransfersUnderlyingAndMintsShares() public {
        uint256 assets = 100e18;

        vm.prank(alice);
        underlying.approve(vaultAddr, assets);

        vm.prank(alice);
        uint256 shares = vault.deposit(assets, alice);

        // 1:1 at first deposit
        assertEq(shares, assets);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalAssets(), assets);
        assertEq(vault.totalSupply(), shares);
        assertEq(underlying.balanceOf(vaultAddr), assets);
        assertEq(underlying.balanceOf(alice), INITIAL_MINT - assets);
    }

    function test_DepositEmitsEvent() public {
        uint256 assets = 100e18;

        vm.prank(alice);
        underlying.approve(vaultAddr, assets);

        vm.expectEmit(true, true, false, true, vaultAddr);
        emit Deposit(alice, alice, assets, assets);

        vm.prank(alice);
        vault.deposit(assets, alice);
    }

    function test_DepositMintsToDifferentReceiver() public {
        uint256 assets = 100e18;

        vm.prank(alice);
        underlying.approve(vaultAddr, assets);

        vm.prank(alice);
        uint256 shares = vault.deposit(assets, bob);

        assertEq(vault.balanceOf(bob), shares);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_PreviewDepositMatchesActualDeposit() public {
        uint256 assets = 100e18;
        uint256 expectedShares = vault.previewDeposit(assets);

        vm.prank(alice);
        underlying.approve(vaultAddr, assets);

        vm.prank(alice);
        uint256 actualShares = vault.deposit(assets, alice);

        assertEq(actualShares, expectedShares);
    }

    function test_SecondDepositSharesProportional() public {
        // Alice deposits 100 first
        vm.prank(alice);
        underlying.approve(vaultAddr, type(uint256).max);
        vm.prank(alice);
        vault.deposit(100e18, alice);

        // Bob deposits 100 after — should get equal shares since rate is 1:1
        vm.prank(bob);
        underlying.approve(vaultAddr, type(uint256).max);
        vm.prank(bob);
        uint256 bobShares = vault.deposit(100e18, bob);

        assertEq(bobShares, 100e18);
    }

    function test_SecondDepositAfterYieldAdjustsShares() public {
        // Alice deposits 100
        vm.prank(alice);
        underlying.approve(vaultAddr, type(uint256).max);
        vm.prank(alice);
        vault.deposit(100e18, alice);

        // Simulate yield: donate 100 underlying to vault (totalAssets doubles to 200, supply stays 100)
        underlying.mint(vaultAddr, 100e18);

        // Bob deposits 100 — rate is now 100/200 so he should get 50 shares
        vm.prank(bob);
        underlying.approve(vaultAddr, type(uint256).max);
        vm.prank(bob);
        uint256 bobShares = vault.deposit(100e18, bob);

        assertEq(bobShares, 50e18);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               MINT TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_MintSpecifiedShares() public {
        uint256 shares = 100e18;
        uint256 expectedAssets = vault.previewMint(shares);

        vm.prank(alice);
        underlying.approve(vaultAddr, expectedAssets);

        vm.prank(alice);
        uint256 assets = vault.mint(shares, alice);

        assertEq(assets, expectedAssets);
        assertEq(vault.balanceOf(alice), shares);
        assertEq(vault.totalAssets(), assets);
    }

    function test_PreviewMintMatchesActualMint() public {
        uint256 shares = 100e18;
        uint256 expectedAssets = vault.previewMint(shares);

        vm.prank(alice);
        underlying.approve(vaultAddr, expectedAssets);

        vm.prank(alice);
        uint256 actualAssets = vault.mint(shares, alice);

        assertEq(actualAssets, expectedAssets);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             WITHDRAW TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_WithdrawBurnsSharesAndTransfersAssets() public {
        uint256 depositAmount = 100e18;

        vm.prank(alice);
        underlying.approve(vaultAddr, depositAmount);
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 withdrawAmount = 50e18;
        uint256 expectedShares = vault.previewWithdraw(withdrawAmount);

        vm.prank(alice);
        uint256 burnedShares = vault.withdraw(withdrawAmount, alice, alice);

        assertEq(burnedShares, expectedShares);
        assertEq(underlying.balanceOf(alice), INITIAL_MINT - depositAmount + withdrawAmount);
        assertEq(vault.totalAssets(), depositAmount - withdrawAmount);
    }

    function test_WithdrawEmitsEvent() public {
        uint256 depositAmount = 100e18;
        vm.prank(alice);
        underlying.approve(vaultAddr, depositAmount);
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 withdrawAmount = 50e18;
        uint256 expectedShares = vault.previewWithdraw(withdrawAmount);

        vm.expectEmit(true, true, true, true, vaultAddr);
        emit Withdraw(alice, alice, alice, withdrawAmount, expectedShares);

        vm.prank(alice);
        vault.withdraw(withdrawAmount, alice, alice);
    }

    function test_PreviewWithdrawMatchesActualWithdraw() public {
        uint256 depositAmount = 100e18;
        vm.prank(alice);
        underlying.approve(vaultAddr, depositAmount);
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 withdrawAmount = 50e18;
        uint256 previewedShares = vault.previewWithdraw(withdrawAmount);

        vm.prank(alice);
        uint256 actualShares = vault.withdraw(withdrawAmount, alice, alice);

        assertEq(actualShares, previewedShares);
    }

    function test_WithdrawToSendToDifferentReceiver() public {
        uint256 depositAmount = 100e18;
        vm.prank(alice);
        underlying.approve(vaultAddr, depositAmount);
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 withdrawAmount = 50e18;
        vm.prank(alice);
        vault.withdraw(withdrawAmount, bob, alice);

        assertEq(underlying.balanceOf(bob), INITIAL_MINT + withdrawAmount);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              REDEEM TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_RedeemBurnsSharesAndTransfersAssets() public {
        uint256 depositAmount = 100e18;
        vm.prank(alice);
        underlying.approve(vaultAddr, depositAmount);
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 redeemShares = 100e18;
        uint256 expectedAssets = vault.previewRedeem(redeemShares);

        vm.prank(alice);
        uint256 assets = vault.redeem(redeemShares, alice, alice);

        assertEq(assets, expectedAssets);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.totalAssets(), 0);
    }

    function test_PreviewRedeemMatchesActualRedeem() public {
        uint256 depositAmount = 100e18;
        vm.prank(alice);
        underlying.approve(vaultAddr, depositAmount);
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 shares = 100e18;
        uint256 previewedAssets = vault.previewRedeem(shares);

        vm.prank(alice);
        uint256 actualAssets = vault.redeem(shares, alice, alice);

        assertEq(actualAssets, previewedAssets);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           MAX AFTER DEPOSIT TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_MaxWithdrawAfterDeposit() public {
        uint256 depositAmount = 100e18;
        vm.prank(alice);
        underlying.approve(vaultAddr, depositAmount);
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        assertEq(vault.maxWithdraw(alice), depositAmount);
    }

    function test_MaxRedeemAfterDeposit() public {
        uint256 depositAmount = 100e18;
        vm.prank(alice);
        underlying.approve(vaultAddr, depositAmount);
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        assertEq(vault.maxRedeem(alice), depositAmount);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        ALLOWANCE / OPERATOR TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_WithdrawByNonOwnerWithoutAllowanceReverts() public {
        uint256 depositAmount = 100e18;
        vm.prank(alice);
        underlying.approve(vaultAddr, depositAmount);
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Charlie tries to withdraw on behalf of alice without allowance
        vm.prank(charlie);
        vm.expectRevert(abi.encodeWithSelector(IERC20.ERC20InsufficientAllowance.selector, charlie, 0, depositAmount));
        vault.withdraw(depositAmount, charlie, alice);
    }

    function test_RedeemByNonOwnerWithoutAllowanceReverts() public {
        uint256 depositAmount = 100e18;
        vm.prank(alice);
        underlying.approve(vaultAddr, depositAmount);
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        vm.prank(charlie);
        vm.expectRevert(abi.encodeWithSelector(IERC20.ERC20InsufficientAllowance.selector, charlie, 0, depositAmount));
        vault.redeem(depositAmount, charlie, alice);
    }

    function test_WithdrawByNonOwnerWithAllowanceSucceeds() public {
        uint256 depositAmount = 100e18;
        vm.prank(alice);
        underlying.approve(vaultAddr, depositAmount);
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        // Alice grants charlie allowance to burn her shares
        vm.prank(alice);
        vault.approve(charlie, depositAmount);

        vm.prank(charlie);
        vault.withdraw(depositAmount, charlie, alice);

        assertEq(vault.balanceOf(alice), 0);
        assertEq(underlying.balanceOf(charlie), depositAmount);
    }

    function test_RedeemByNonOwnerWithAllowanceSucceeds() public {
        uint256 depositAmount = 100e18;
        vm.prank(alice);
        underlying.approve(vaultAddr, depositAmount);
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        vm.prank(alice);
        vault.approve(charlie, depositAmount);

        vm.prank(charlie);
        vault.redeem(depositAmount, charlie, alice);

        assertEq(vault.balanceOf(alice), 0);
        assertEq(underlying.balanceOf(charlie), depositAmount);
    }

    function test_WithdrawConsumesAllowance() public {
        uint256 depositAmount = 100e18;
        vm.prank(alice);
        underlying.approve(vaultAddr, depositAmount);
        vm.prank(alice);
        vault.deposit(depositAmount, alice);

        uint256 withdrawAmount = 50e18;
        uint256 sharesToBurn = vault.previewWithdraw(withdrawAmount);

        vm.prank(alice);
        vault.approve(charlie, sharesToBurn);

        vm.prank(charlie);
        vault.withdraw(withdrawAmount, charlie, alice);

        // Allowance should be exhausted
        assertEq(vault.allowance(alice, charlie), 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    INFLATION ATTACK MITIGATION TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_InflationAttackFirstDepositSmallNotStolen() public {
        // Classic attack: attacker deposits 1 wei, then front-runs victim with large donation
        address attacker = address(0xDEAD);
        address victim = address(0xBEEF);

        underlying.mint(attacker, 1000e18);
        underlying.mint(victim, 1000e18);

        // Step 1: attacker deposits 1 wei
        vm.prank(attacker);
        underlying.approve(vaultAddr, 1);
        vm.prank(attacker);
        vault.deposit(1, attacker);
        // attacker has 1 share, vault has 1 asset

        // Step 2: attacker donates 999e18 underlying directly (inflate rate)
        vm.prank(attacker);
        underlying.transfer(vaultAddr, 999e18);
        // Now vault has 999e18 + 1 assets, 1 share outstanding

        // Step 3: victim deposits 1000e18
        vm.prank(victim);
        underlying.approve(vaultAddr, 1000e18);
        vm.prank(victim);
        uint256 victimShares = vault.deposit(1000e18, victim);

        // With virtual offset=0 and virtual denominator trick (+1 in denominator),
        // victim should get ~1 share (1000e18 * 1 / (999e18 + 1 + 1) ≈ 1)
        // The key is victim doesn't get 0 shares
        assertTrue(victimShares >= 1, "victim should get at least 1 share");
    }

    function test_DecimalsOffsetMitigatesInflation() public {
        // Deploy a vault with decimalsOffset = 3 for stronger inflation protection
        IERC4626 vaultWithOffset = IERC4626(_deployVault(underlyingAddr, "Protected Vault", "pvTK", 3));
        address vaultWithOffsetAddr = address(vaultWithOffset);

        address attacker2 = address(0xDEAD2);
        address victim2 = address(0xBEEF2);

        underlying.mint(attacker2, 1000e18);
        underlying.mint(victim2, 1000e18);

        // Attacker deposits 1 wei
        vm.prank(attacker2);
        underlying.approve(vaultWithOffsetAddr, 1);
        vm.prank(attacker2);
        vaultWithOffset.deposit(1, attacker2);

        // Attacker donates large amount
        vm.prank(attacker2);
        underlying.transfer(vaultWithOffsetAddr, 999e18);

        // Victim deposits 1000e18
        // With offset=3, virtualShares = supply + 10**3 = 1 + 1000
        // victimShares ≈ 1000e18 * 1001 / (999e18+1+1) ≈ 1001 shares
        vm.prank(victim2);
        underlying.approve(vaultWithOffsetAddr, 1000e18);
        vm.prank(victim2);
        uint256 victimShares2 = vaultWithOffset.deposit(1000e18, victim2);

        assertTrue(victimShares2 > 1000, "victim should get many shares with offset");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsIERC4626() public view {
        assertTrue(ERC165Facet(vaultAddr).supportsInterface(type(IERC4626).interfaceId));
    }

    function test_SupportsIERC20() public view {
        // ERC4626Lib registers IERC4626, ERC20Lib registers IERC20
        assertTrue(ERC165Facet(vaultAddr).supportsInterface(type(IERC20).interfaceId));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                      USDT-STYLE TOKEN COMPATIBILITY
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Deposit must succeed with a token whose transferFrom() returns no bool (USDT-style).
    function test_DepositWithUSDTStyleToken() public {
        MockNoReturnERC20 usdtLike = new MockNoReturnERC20();
        usdtLike.mint(alice, 1000e18);

        // The vault will call decimals() on usdtLike — it returns 300 so underlyingDecimals stays 18
        IERC4626 usdtVault = IERC4626(_deployVault(address(usdtLike), "USDT Vault", "vUSDT", 0));
        address usdtVaultAddr = address(usdtVault);
        assertEq(usdtVault.decimals(), 18, "oversize decimals should default to 18");

        vm.prank(alice);
        usdtLike.approve(usdtVaultAddr, 100e18);

        vm.prank(alice);
        uint256 shares = usdtVault.deposit(100e18, alice);

        assertEq(shares, 100e18);
        assertEq(usdtVault.balanceOf(alice), shares);
        assertEq(usdtLike.balanceOf(usdtVaultAddr), 100e18);
    }

    /// @notice Withdraw must succeed with a token whose transfer() returns no bool (USDT-style).
    function test_WithdrawWithUSDTStyleToken() public {
        MockNoReturnERC20 usdtLike = new MockNoReturnERC20();
        usdtLike.mint(alice, 1000e18);

        IERC4626 usdtVault = IERC4626(_deployVault(address(usdtLike), "USDT Vault", "vUSDT", 0));
        address usdtVaultAddr = address(usdtVault);

        // Deposit first
        vm.prank(alice);
        usdtLike.approve(usdtVaultAddr, 500e18);
        vm.prank(alice);
        usdtVault.deposit(500e18, alice);

        // Now withdraw
        vm.prank(alice);
        uint256 burned = usdtVault.withdraw(200e18, alice, alice);

        assertEq(burned, 200e18);
        assertEq(usdtLike.balanceOf(alice), 1000e18 - 500e18 + 200e18);
        assertEq(usdtVault.totalAssets(), 300e18);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        MULDIV OVERFLOW PROTECTION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice convertToShares with large totalAssets must not wrap around (tests 512-bit path).
    function test_MulDivOverflowProtection() public {
        // Fund vault so totalAssets ~ type(uint128).max
        uint256 bigAmount = type(uint128).max;
        underlying.mint(alice, bigAmount);
        vm.prank(alice);
        underlying.approve(vaultAddr, bigAmount);
        vm.prank(alice);
        vault.deposit(bigAmount, alice);

        // convertToShares(type(uint128).max) should return a sane value, not overflow-wrapped
        // At 1:1 the answer is approximately type(uint128).max (with virtual offset correction)
        uint256 result = vault.convertToShares(type(uint128).max);
        // The correct answer is close to type(uint128).max (never 0 or wildly wrong)
        assertGt(result, 0, "result must be > 0");
        // With 512-bit path: result ~ bigAmount * (bigAmount+1) / (bigAmount+1) = bigAmount
        // Allow a small tolerance for the virtual +1
        assertApproxEqAbs(result, bigAmount, 1, "result must be close to input");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       OVERSIZE DECIMALS DEFAULT TO 18
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice A token whose decimals() returns uint256(300) must cause vault to default to 18.
    function test_DecimalsTokenReturningOversizeValueDefaultsTo18() public {
        MockNoReturnERC20 weirdToken = new MockNoReturnERC20();
        // weirdToken.decimals() returns 300 — above type(uint8).max

        IERC4626 weirdVault = IERC4626(_deployVault(address(weirdToken), "Weird Vault", "vW", 0));

        // Should default to 18, not truncate 300 to 44 (300 mod 256 = 44)
        assertEq(weirdVault.decimals(), 18, "should default to 18 not truncate 300 to 44");
    }
}

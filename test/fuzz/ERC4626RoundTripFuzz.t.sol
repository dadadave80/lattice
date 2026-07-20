// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {ERC4626} from "@lattice/tokens/ERC4626/ERC4626.sol";
import {ERC4626Lib} from "@lattice/tokens/ERC4626/libraries/ERC4626Lib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Minimal ERC-20 underlying asset for vault fuzz tests.
contract FuzzUnderlying {
    string public name = "Underlying";
    string public symbol = "UND";
    uint8 public constant decimals = 18;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        totalSupply += amount;
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount);
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount);
        require(allowance[from][msg.sender] >= amount);
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @notice Minimal ERC-4626 vault with zero decimals offset. Flattens the composable {ERC20} share facet and the
///         {ERC4626} vault facet into one mock (both delegate to their namespaced-storage libs); `decimals` is
///         disambiguated to the ERC-4626 share-offset variant.
contract FuzzVault is ERC20, ERC4626, Initializable {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(ERC20, ERC4626) returns (bytes memory) {}

    function initialize(address asset_) external initializer {
        ERC20Lib.__ERC20_init("Vault Share", "vSHR");
        ERC4626Lib.__ERC4626_init(asset_, 0);
        AccessControlLib.__AccessControl_init(msg.sender);
    }

    /// @dev Resolves the `decimals()` clash between the flattened {ERC20} and {ERC4626} facets.
    function decimals() public view override(ERC20, ERC4626) returns (uint8) {
        return ERC4626.decimals();
    }
}

/// @title ERC4626RoundTripFuzz
contract ERC4626RoundTripFuzz is Test {
    FuzzVault vault;
    FuzzUnderlying underlying;

    address constant ALICE = address(0xA11CE);

    function setUp() public {
        underlying = new FuzzUnderlying();
        vault = new FuzzVault();
        vault.initialize(address(underlying));
    }

    /// @notice deposit then full redeem; final underlying balance is <= initial (rounding).
    function testFuzz_DepositRedeemRoundTrip(uint128 assets) public {
        assets = uint128(bound(uint256(assets), 1, type(uint96).max));

        underlying.mint(ALICE, assets);

        uint256 aliceStart = underlying.balanceOf(ALICE);

        vm.startPrank(ALICE);
        underlying.approve(address(vault), assets);
        uint256 shares = vault.deposit(assets, ALICE);

        // Redeem all shares back.
        vault.approve(address(vault), shares); // allow vault to spend shares when ALICE is owner
        uint256 assetsOut = vault.redeem(shares, ALICE, ALICE);
        vm.stopPrank();

        // Final underlying balance is <= initial due to floor rounding (no yield in empty vault).
        assertLe(underlying.balanceOf(ALICE), aliceStart, "round-trip cannot return more than deposited");
        // The rounding error is at most 1 wei per round-trip.
        assertGe(assetsOut + 1, assets, "should recover at least assets - 1 (rounding tolerance)");
    }

    /// @notice mint then full withdraw; share balance returns to 0.
    function testFuzz_MintWithdrawRoundTrip(uint128 shares) public {
        shares = uint128(bound(uint256(shares), 1, type(uint64).max));

        // Compute assets required to mint exactly `shares`.
        uint256 required = vault.previewMint(shares);
        // Guard against zero required (degenerate empty-vault case with offset=0).
        vm.assume(required > 0);

        underlying.mint(ALICE, required);

        vm.startPrank(ALICE);
        underlying.approve(address(vault), required);
        vault.mint(shares, ALICE);

        // Withdraw all deposited assets.
        uint256 maxAssets = vault.maxWithdraw(ALICE);
        vault.withdraw(maxAssets, ALICE, ALICE);
        vm.stopPrank();

        assertEq(vault.balanceOf(ALICE), 0, "all shares must be burned after withdraw");
    }

    /// @notice convertToShares is monotonically non-decreasing with assets.
    function testFuzz_ConvertToSharesAssetsMonotonic(uint128 a, uint128 b) public view {
        vm.assume(a < b);
        uint256 sharesA = vault.convertToShares(a);
        uint256 sharesB = vault.convertToShares(b);
        assertLe(sharesA, sharesB, "convertToShares must be non-decreasing");
    }
}

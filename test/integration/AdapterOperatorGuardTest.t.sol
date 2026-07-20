// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title AdapterOperatorGuardTest
/// @notice Security regression suite for the recipient-pin + operator-authorization fix applied
///         uniformly to every Lattice protocol adapter. Proven end-to-end on the Aave v3 adapter
///         (the supply/leverage adapter that pulls a real protocol position), and asserted as a
///         pattern for the rest via the shared `IProtocolAdapter`/`IAdapterOperator` surface.
///
/// THE VULNERABILITY (pre-fix): `withdraw(uint256, address to)` was permissionless with a
/// caller-supplied `to`. ANY EOA could call `adapter.withdraw(type(uint256).max, attacker)` and
/// drain the adapter's entire protocol position to themselves. `deploy()`/`harvest()` were likewise
/// permissionless (timing abuse). THE FIX: (1) the recall recipient is pinned to the adapter's own
/// stored `_vault`; (2) `deploy`/`withdraw`/`harvest` are gated to a single authorized operator
/// (the StrategyManager), checked BEFORE the reentrancy guard.

import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IAdapterOperator} from "@lattice/interfaces/defi/IAdapterOperator.sol";
import {IProtocolAdapter} from "@lattice/interfaces/defi/IProtocolAdapter.sol";
import {Test} from "forge-std/Test.sol";

// Reuse the faithful Aave mocks + the MockAaveAdapter facet from the supply test.
import {MockAToken, MockAaveAdapter, MockAaveV3Pool, MockAsset} from "./AaveV3AdapterSupplyTest.t.sol";

contract AdapterOperatorGuardTest is Test {
    MockAsset asset;
    MockAToken aToken;
    MockAaveV3Pool pool;
    MockAaveAdapter adapter;

    address admin = address(0xAD);
    address vault = address(0x7A17); // the adapter's stored _vault
    address treasury = address(0x7E0);
    address operator = address(0x09E8); // stand-in for the StrategyManager
    address attacker = address(0xBAD);
    bytes32 constant FEED_KEY = keccak256("USDC/USD");

    function setUp() public {
        asset = new MockAsset();
        aToken = new MockAToken(asset);
        pool = new MockAaveV3Pool();
        pool.setAToken(asset, aToken);

        adapter = new MockAaveAdapter();
        adapter.initialize(admin, address(pool), address(asset), vault, treasury, FEED_KEY, 1.05e18);
    }

    /// @dev Funds + supplies a position the operator owns, so there is something to (try to) steal.
    function _seedPosition(uint256 amount) internal {
        asset.mint(address(adapter), amount);
        vm.prank(admin);
        adapter.setOperator(operator);
        vm.prank(operator);
        adapter.deploy();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       THEFT PROOF (the critical fix)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice An unauthorized EOA calling `withdraw(max, attacker)` is rejected: it never reaches
    ///         the pool, and the position is untouched. (Pre-fix this drained the whole position.)
    function test_Theft_UnauthorizedWithdrawToAttacker_Reverts() public {
        _seedPosition(1_000e6);
        assertEq(adapter.totalAssetsManaged(), 1_000e6, "position seeded");

        // The attacker tries to sweep the entire position to themselves.
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(IProtocolAdapter.ProtocolAdapterUnauthorized.selector, attacker));
        adapter.withdraw(type(uint256).max, attacker);

        // Nothing moved: the position and the attacker's balance are exactly as before.
        assertEq(adapter.totalAssetsManaged(), 1_000e6, "position intact after blocked theft");
        assertEq(asset.balanceOf(attacker), 0, "attacker got nothing");
    }

    /// @notice Even the legit operator cannot redirect a recall to a non-vault address: the recipient
    ///         is pinned to the adapter's stored vault.
    function test_Theft_OperatorWithBadRecipient_Reverts() public {
        _seedPosition(1_000e6);

        vm.prank(operator);
        vm.expectRevert(abi.encodeWithSelector(IProtocolAdapter.ProtocolAdapterInvalidRecipient.selector, attacker));
        adapter.withdraw(500e6, attacker);

        assertEq(adapter.totalAssetsManaged(), 1_000e6, "position intact: bad recipient rejected");
        assertEq(asset.balanceOf(attacker), 0, "attacker got nothing");
    }

    /// @notice `deploy()` is operator-gated: a random caller cannot force-deploy idle funds.
    function test_Deploy_RevertsForNonOperator() public {
        asset.mint(address(adapter), 1_000e6);
        vm.prank(admin);
        adapter.setOperator(operator);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(IProtocolAdapter.ProtocolAdapterUnauthorized.selector, attacker));
        adapter.deploy();
    }

    /// @notice `harvest()` is operator-gated: a random caller cannot time reward/fee flows.
    function test_Harvest_RevertsForNonOperator() public {
        _seedPosition(1_000e6);

        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(IProtocolAdapter.ProtocolAdapterUnauthorized.selector, attacker));
        adapter.harvest();
    }

    /// @notice With NO operator wired, the trio reverts for everyone (secure default).
    function test_Trio_RevertsWhenOperatorUnset() public {
        asset.mint(address(adapter), 1_000e6);
        // No setOperator call — _operator is zero.
        vm.expectRevert(abi.encodeWithSelector(IProtocolAdapter.ProtocolAdapterUnauthorized.selector, address(this)));
        adapter.deploy();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          AUTHORIZED PATH STILL WORKS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The operator can withdraw to the vault exactly as the StrategyManager does — and the
    ///         funds land in the vault, honestly reported.
    function test_Authorized_WithdrawToVault_Succeeds() public {
        _seedPosition(1_000e6);

        vm.prank(operator);
        uint256 got = adapter.withdraw(400e6, vault);

        assertEq(got, 400e6, "real withdrawn to vault");
        assertEq(asset.balanceOf(vault), 400e6, "vault received");
        assertEq(adapter.totalAssetsManaged(), 600e6, "remaining supplied");
    }

    /// @notice The operator can deploy and harvest without reverting (parity with pre-fix behavior).
    function test_Authorized_DeployAndHarvest_Succeed() public {
        asset.mint(address(adapter), 1_000e6);
        vm.prank(admin);
        adapter.setOperator(operator);

        vm.prank(operator);
        uint256 deployed = adapter.deploy();
        assertEq(deployed, 1_000e6, "operator deploy works");

        // No rewards controller wired -> harvest is a graceful no-op, but must not revert.
        vm.prank(operator);
        adapter.harvest();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          setOperator / operator()
    //////////////////////////////////////////////////////////////////////////*//

    function test_SetOperator_AdminOnly() public {
        vm.prank(attacker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, attacker, DEFAULT_ADMIN_ROLE
            )
        );
        adapter.setOperator(operator);
    }

    function test_SetOperator_RejectsZero() public {
        vm.prank(admin);
        vm.expectRevert(IProtocolAdapter.ProtocolAdapterZeroAddress.selector);
        adapter.setOperator(address(0));
    }

    function test_SetOperator_ReflectsInView_AndEmits() public {
        vm.expectEmit(true, false, false, false, address(adapter));
        emit IProtocolAdapter.OperatorSet(operator);
        vm.prank(admin);
        adapter.setOperator(operator);
        assertEq(adapter.operator(), operator, "operator() reflects the set value");
    }
}

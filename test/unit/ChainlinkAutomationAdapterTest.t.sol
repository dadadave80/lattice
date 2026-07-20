// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {ChainlinkAutomationAdapterTestBase} from "@lattice-test/base/ChainlinkAutomationAdapterTestBase.sol";
import {IChainlinkAutomationAdapter} from "@lattice/interfaces/oracles/IChainlinkAutomationAdapter.sol";
import {ChainlinkAutomationAdapter} from "@lattice/oracles/chainlink/ChainlinkAutomationAdapter.sol";

/// @title ChainlinkAutomationAdapterTest
/// @notice Exercises the ChainlinkAutomationAdapter facet through a REAL {Diamond} assembled by the
///         ready-to-deploy {DeployChainlinkAutomationAdapter} script (see {ChainlinkAutomationAdapterTestBase}) —
///         every call below routes through the diamond's `delegatecall` dispatch, not a flattened inheritance
///         mock. Admin gating is enforced by the cut-in `AccessControl` facet; `supportsInterface` by the cut-in
///         `ERC165Facet`.
contract ChainlinkAutomationAdapterTest is ChainlinkAutomationAdapterTestBase {
    address admin = address(0x1);
    address user = address(0x2);
    address forwarder = address(0xF0);

    uint256 constant INTERVAL = 1 hours;

    function setUp() public {
        vm.warp(1_000_000);

        diamond = _deployChainlinkAutomationAdapter(admin);
        automation = ChainlinkAutomationAdapter(diamond);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           SET CONFIG TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Non-admin cannot set config.
    function test_SetConfigRevertsForNonAdmin() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), user, bytes32(0)
            )
        );
        automation.setConfig(forwarder, INTERVAL);
    }

    /// @notice setConfig with zero forwarder reverts ChainlinkAutomationInvalidConfig.
    function test_SetConfigRevertsOnZeroForwarder() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IChainlinkAutomationAdapter.ChainlinkAutomationInvalidConfig.selector));
        automation.setConfig(address(0), INTERVAL);
    }

    /// @notice setConfig with zero interval reverts ChainlinkAutomationInvalidConfig.
    function test_SetConfigRevertsOnZeroInterval() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IChainlinkAutomationAdapter.ChainlinkAutomationInvalidConfig.selector));
        automation.setConfig(forwarder, 0);
    }

    /// @notice Admin can set config; fields are stored and the timer resets.
    function test_SetConfigByAdmin() public {
        vm.prank(admin);
        automation.setConfig(forwarder, INTERVAL);

        assertEq(automation.getForwarder(), forwarder);
        assertEq(automation.getInterval(), INTERVAL);
        assertEq(automation.getLastTimeStamp(), block.timestamp);
        assertEq(automation.getCounter(), 0);
    }

    /// @notice setConfig resets the lastTimeStamp to the current block timestamp.
    function test_SetConfigResetsLastTimeStamp() public {
        vm.prank(admin);
        automation.setConfig(forwarder, INTERVAL);
        assertEq(automation.getLastTimeStamp(), block.timestamp);

        // Warp forward and re-configure; lastTimeStamp tracks the new timestamp.
        vm.warp(block.timestamp + 5000);
        vm.prank(admin);
        automation.setConfig(forwarder, INTERVAL);
        assertEq(automation.getLastTimeStamp(), block.timestamp);
    }

    /// @notice setConfig emits ChainlinkAutomationConfigSet.
    function test_SetConfigEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, true);
        emit IChainlinkAutomationAdapter.ChainlinkAutomationConfigSet(forwarder, INTERVAL);
        automation.setConfig(forwarder, INTERVAL);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           CHECK UPKEEP TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice checkUpkeep returns false immediately after config.
    function test_CheckUpkeepFalseRightAfterConfig() public {
        vm.prank(admin);
        automation.setConfig(forwarder, INTERVAL);

        (bool upkeepNeeded, bytes memory performData) = automation.checkUpkeep(hex"1234");
        assertFalse(upkeepNeeded);
        assertEq(performData, hex"1234");
    }

    /// @notice checkUpkeep returns true once the interval has elapsed and echoes checkData.
    function test_CheckUpkeepTrueAfterInterval() public {
        vm.prank(admin);
        automation.setConfig(forwarder, INTERVAL);

        vm.warp(block.timestamp + INTERVAL);

        bytes memory checkData = hex"deadbeef";
        (bool upkeepNeeded, bytes memory performData) = automation.checkUpkeep(checkData);
        assertTrue(upkeepNeeded);
        assertEq(performData, checkData);
    }

    /// @notice checkUpkeep returns false before any config is set.
    function test_CheckUpkeepFalseWhenNotConfigured() public view {
        (bool upkeepNeeded,) = automation.checkUpkeep("");
        assertFalse(upkeepNeeded);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          PERFORM UPKEEP TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice performUpkeep before any config reverts ChainlinkAutomationNotConfigured.
    function test_PerformUpkeepRevertsWhenNotConfigured() public {
        vm.expectRevert(abi.encodeWithSelector(IChainlinkAutomationAdapter.ChainlinkAutomationNotConfigured.selector));
        automation.performUpkeep("");
    }

    /// @notice performUpkeep from a non-forwarder reverts ChainlinkAutomationOnlyForwarder.
    function test_PerformUpkeepRevertsFromNonForwarder() public {
        vm.prank(admin);
        automation.setConfig(forwarder, INTERVAL);

        vm.warp(block.timestamp + INTERVAL);

        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(IChainlinkAutomationAdapter.ChainlinkAutomationOnlyForwarder.selector, user)
        );
        automation.performUpkeep("");
    }

    /// @notice performUpkeep before the interval has elapsed reverts ChainlinkAutomationConditionNotMet.
    function test_PerformUpkeepRevertsBeforeInterval() public {
        vm.prank(admin);
        automation.setConfig(forwarder, INTERVAL);

        vm.prank(forwarder);
        vm.expectRevert(abi.encodeWithSelector(IChainlinkAutomationAdapter.ChainlinkAutomationConditionNotMet.selector));
        automation.performUpkeep("");
    }

    /// @notice performUpkeep from the forwarder after the interval advances the
    ///         counter, resets the timer, and emits UpkeepPerformed.
    function test_PerformUpkeepFromForwarderAdvancesAndEmits() public {
        vm.prank(admin);
        automation.setConfig(forwarder, INTERVAL);

        vm.warp(block.timestamp + INTERVAL);
        uint256 expectedTimestamp = block.timestamp;

        vm.expectEmit(false, false, false, true);
        emit IChainlinkAutomationAdapter.UpkeepPerformed(1);
        vm.prank(forwarder);
        automation.performUpkeep(hex"00");

        assertEq(automation.getCounter(), 1);
        assertEq(automation.getLastTimeStamp(), expectedTimestamp);

        // A second perform requires another full interval.
        vm.prank(forwarder);
        vm.expectRevert(abi.encodeWithSelector(IChainlinkAutomationAdapter.ChainlinkAutomationConditionNotMet.selector));
        automation.performUpkeep("");

        vm.warp(block.timestamp + INTERVAL);
        vm.expectEmit(false, false, false, true);
        emit IChainlinkAutomationAdapter.UpkeepPerformed(2);
        vm.prank(forwarder);
        automation.performUpkeep("");
        assertEq(automation.getCounter(), 2);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice supportsInterface returns true for IChainlinkAutomationAdapter after init.
    function test_SupportsInterfaceChainlinkAutomationAdapter() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IChainlinkAutomationAdapter).interfaceId));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IChainlinkAutomationAdapter} from "@lattice/interfaces/IChainlinkAutomationAdapter.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ChainlinkAutomationAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant CHAINLINK_AUTOMATION_ADAPTER_STORAGE_SLOT =
    0x79ff96d501e28b99bca4f72c19ec619bce29c1cac16a5bcab62634e5e94dcb00;

/// @dev 0x97290114 is `type(IChainlinkAutomationAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x97290114), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ICHAINLINKAUTOMATIONADAPTER_SLOT =
    0xda518c4395658f1bda3e69bd76a71c3cebddb4103a2ca4f795abdfcb18525c7c;

/// @notice ERC-7201 namespaced storage for ChainlinkAutomationAdapter.
/// @custom:storage-location erc7201:lattice.storage.ChainlinkAutomationAdapter
struct ChainlinkAutomationAdapterStorage {
    address _forwarder;
    uint256 _interval;
    uint256 _lastTimeStamp;
    uint256 _counter;
}

/// @title ChainlinkAutomationAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Chainlink (https://github.com/smartcontractkit/chainlink)
/// @notice Library implementing the consumer side of Chainlink Automation
///         (keepers) with a canonical time-interval upkeep. `checkUpkeep`
///         reports `true` once `interval` seconds have elapsed; `performUpkeep`
///         (gated to the configured Automation forwarder) advances the counter
///         and resets the timer. The upkeep condition is re-validated inside
///         `performUpkeep` — `performData` is never trusted blindly.
library ChainlinkAutomationAdapterLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                                  STORAGE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the ERC-7201 storage struct for ChainlinkAutomationAdapter.
    function chainlinkAutomationAdapterStorage() internal pure returns (ChainlinkAutomationAdapterStorage storage $) {
        assembly {
            $.slot := CHAINLINK_AUTOMATION_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALISATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the IChainlinkAutomationAdapter ERC-165 interface.
    /// @dev Must be called between `preInitializer` / `postInitializer`.
    function __ChainlinkAutomationAdapter_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for IChainlinkAutomationAdapter.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ICHAINLINKAUTOMATIONADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the configured Automation forwarder.
    function getForwarder() internal view returns (address) {
        return chainlinkAutomationAdapterStorage()._forwarder;
    }

    /// @notice Returns the configured upkeep interval (seconds).
    function getInterval() internal view returns (uint256) {
        return chainlinkAutomationAdapterStorage()._interval;
    }

    /// @notice Returns the timestamp of the last performed upkeep.
    function getLastTimeStamp() internal view returns (uint256) {
        return chainlinkAutomationAdapterStorage()._lastTimeStamp;
    }

    /// @notice Returns the number of upkeeps performed.
    function getCounter() internal view returns (uint256) {
        return chainlinkAutomationAdapterStorage()._counter;
    }

    /// @notice Reports whether the upkeep should run.
    /// @dev Returns `true` once `interval` seconds have elapsed since the last
    ///      upkeep and a forwarder has been configured. `performData` echoes
    ///      `checkData`.
    /// @param checkData Arbitrary data configured on the upkeep.
    /// @return upkeepNeeded True if `performUpkeep` should be called.
    /// @return performData  The data to pass to `performUpkeep`.
    function checkUpkeep(bytes calldata checkData) internal view returns (bool upkeepNeeded, bytes memory performData) {
        ChainlinkAutomationAdapterStorage storage $ = chainlinkAutomationAdapterStorage();
        upkeepNeeded = ($._forwarder != address(0)) && (block.timestamp - $._lastTimeStamp >= $._interval);
        performData = checkData;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets or replaces the Automation configuration and resets the upkeep timer.
    /// @dev Caller must hold DEFAULT_ADMIN_ROLE.
    ///      Reverts `ChainlinkAutomationInvalidConfig` on a zero forwarder or
    ///      zero interval.
    /// @param forwarder The Automation forwarder allowed to call `performUpkeep`.
    /// @param interval  The minimum seconds between upkeeps.
    function setConfig(address forwarder, uint256 interval) internal {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        if (forwarder == address(0) || interval == 0) {
            revert IChainlinkAutomationAdapter.ChainlinkAutomationInvalidConfig();
        }
        ChainlinkAutomationAdapterStorage storage $ = chainlinkAutomationAdapterStorage();
        $._forwarder = forwarder;
        $._interval = interval;
        $._lastTimeStamp = block.timestamp;
        emit IChainlinkAutomationAdapter.ChainlinkAutomationConfigSet(forwarder, interval);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Performs the upkeep. Gated to the configured forwarder.
    /// @dev Reverts `ChainlinkAutomationNotConfigured` if no forwarder is set,
    ///      `ChainlinkAutomationOnlyForwarder` if the caller is not the
    ///      forwarder, and `ChainlinkAutomationConditionNotMet` if the interval
    ///      has not elapsed. Advances the counter, resets the timer, and emits
    ///      `UpkeepPerformed`.
    /// @param performData The data returned by `checkUpkeep` (unused by the reference upkeep).
    function performUpkeep(bytes calldata performData) internal {
        ChainlinkAutomationAdapterStorage storage $ = chainlinkAutomationAdapterStorage();

        address f = $._forwarder;
        if (f == address(0)) revert IChainlinkAutomationAdapter.ChainlinkAutomationNotConfigured();
        if (msg.sender != f) revert IChainlinkAutomationAdapter.ChainlinkAutomationOnlyForwarder(msg.sender);
        if (block.timestamp - $._lastTimeStamp < $._interval) {
            revert IChainlinkAutomationAdapter.ChainlinkAutomationConditionNotMet();
        }

        $._lastTimeStamp = block.timestamp;
        uint256 c = $._counter + 1;
        $._counter = c;
        emit IChainlinkAutomationAdapter.UpkeepPerformed(c);

        // performData is passed in but not consumed by the reference upkeep.
        // Silence the unused-variable warning.
        (performData);
    }
}

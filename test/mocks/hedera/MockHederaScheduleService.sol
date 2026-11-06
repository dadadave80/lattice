// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Vm} from "forge-std/Vm.sol";

/// @title MockHederaScheduleService
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from hiero-ledger/hiero-contracts (https://github.com/hiero-ledger/hiero-contracts)
/// @notice Native HSS ABI mock. `fire` alone models the network's assumed payer-as-sender callback.
contract MockHederaScheduleService {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct ScheduledCall {
        address payer;
        address to;
        uint256 expirySecond;
        uint256 gasLimit;
        uint64 value;
        bytes data;
    }

    mapping(address schedule => ScheduledCall) private _calls;
    mapping(address schedule => bool) public deleted;
    uint256 private _next;
    int64 public scheduleCode;
    int64 public deleteCode;
    uint8 public deleteMode;

    function configure(int64 scheduleCode_, int64 deleteCode_, uint8 deleteMode_) external {
        scheduleCode = scheduleCode_;
        deleteCode = deleteCode_;
        deleteMode = deleteMode_;
    }

    function scheduleCall(address to, uint256 expirySecond, uint256 gasLimit, uint64 value, bytes memory data)
        external
        returns (int64 responseCode, address schedule)
    {
        if (scheduleCode == -1) {
            assembly ("memory-safe") { return(0, 0) }
        }
        if (scheduleCode == -2) return (22, address(0));
        if (scheduleCode == -3) revert("native scheduling reverted");
        if (scheduleCode != 22) return (scheduleCode, address(0));
        schedule = address(uint160(0x10000 + ++_next));
        _calls[schedule] = ScheduledCall(msg.sender, to, expirySecond, gasLimit, value, data);
        return (22, schedule);
    }

    function deleteSchedule(address schedule) external returns (int64) {
        require(_calls[schedule].payer == msg.sender, "not schedule admin");
        if (deleteMode == 1) revert("native deletion reverted");
        if (deleteMode == 2) {
            assembly ("memory-safe") { return(0, 0) }
        }
        if (deleteMode == 3) {
            assembly ("memory-safe") { invalid() }
        }
        if (deleteMode == 4) {
            assembly ("memory-safe") {
                mstore(0, 22)
                return(0, 32768)
            }
        }
        if (deleteMode == 5) {
            assembly ("memory-safe") {
                mstore(0, 22)
                return(31, 1)
            }
        }
        if (deleteCode == 22) deleted[schedule] = true;
        return deleteCode;
    }

    function authorizeSchedule(address) external pure returns (int64) {
        return 22;
    }

    function hasScheduleCapacity(uint256, uint256) external pure returns (bool) {
        return true;
    }

    function payload(address schedule) external view returns (bytes memory) {
        return _calls[schedule].data;
    }

    /// @dev Ignores deletion/expiry deliberately, modelling a stale fire that recovery must reject locally.
    function fire(address schedule) external returns (bool ok, bytes memory result) {
        ScheduledCall storage s = _calls[schedule];
        vm.prank(s.payer);
        return s.to.call{gas: s.gasLimit, value: s.value}(s.data);
    }
}

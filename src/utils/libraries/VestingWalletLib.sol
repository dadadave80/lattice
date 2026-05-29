// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {OwnableLib} from "@diamond/libraries/OwnableLib.sol";
import {IVestingWallet} from "@lattice/interfaces/IVestingWallet.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.VestingWallet")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant VESTING_WALLET_STORAGE_SLOT =
    0x6d3272be2f02b6d92080037a80b8780ee2896be455de43b32ab08d8adbdbbe00;

/// @dev `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant VESTING_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x1c3a25a8 is `type(IVestingWallet).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x1c3a25a8), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IVESTINGWALLET_SLOT =
    0x30594729cb8d6a49998656680a715012a3392034ab2a6e4f69a94bf6b0450af9;

/// @notice Struct for storing VestingWallet state.
/// @custom:storage-location erc7201:lattice.storage.VestingWallet
struct VestingWalletStorage {
    uint256 _released;
    mapping(address token => uint256) _erc20Released;
    uint64 _start;
    uint64 _duration;
}

/// @title VestingWallet Library
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Library implementing linear vesting of ETH and ERC20 tokens to a beneficiary.
/// @dev The beneficiary is the Ownable owner of the contract. To change the beneficiary,
/// transfer ownership via OwnableLib.
library VestingWalletLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                           VESTING WALLET STORAGE
    //////////////////////////////////////////////////////////////////////////*//

    function vestingWalletStorage() internal pure returns (VestingWalletStorage storage $) {
        assembly {
            $.slot := VESTING_WALLET_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               ERC-165
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IVestingWallet interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IVESTINGWALLET_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZER
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the VestingWallet module.
    /// @param startTimestamp The Unix timestamp at which vesting begins.
    /// @param durationSeconds The total duration of the vesting period in seconds.
    /// @dev Must be called between InitializableLib.preInitializer and postInitializer.
    function __VestingWallet_init(uint64 startTimestamp, uint64 durationSeconds) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        VestingWalletStorage storage $ = vestingWalletStorage();
        $._start = startTimestamp;
        $._duration = durationSeconds;
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           SCHEDULE QUERIES
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the start timestamp of the vesting schedule.
    function start() internal view returns (uint256) {
        return vestingWalletStorage()._start;
    }

    /// @notice Returns the duration of the vesting schedule in seconds.
    function duration() internal view returns (uint256) {
        return vestingWalletStorage()._duration;
    }

    /// @notice Returns the end timestamp (start + duration).
    function end() internal view returns (uint256) {
        VestingWalletStorage storage $ = vestingWalletStorage();
        return uint256($._start) + uint256($._duration);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           RELEASE ACCOUNTING
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the total amount of ETH already released.
    function released() internal view returns (uint256) {
        return vestingWalletStorage()._released;
    }

    /// @notice Returns the total amount of an ERC20 token already released.
    function released(address token) internal view returns (uint256) {
        return vestingWalletStorage()._erc20Released[token];
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              RELEASABLE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the ETH amount currently available to release.
    function releasable() internal view returns (uint256) {
        return vestedAmount(uint64(block.timestamp)) - released();
    }

    /// @notice Returns the ERC20 token amount currently available to release.
    function releasable(address token) internal view returns (uint256) {
        return vestedAmount(token, uint64(block.timestamp)) - released(token);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             VESTED AMOUNTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Calculates the total vested ETH amount at a given timestamp.
    /// @param timestamp The Unix timestamp to evaluate.
    function vestedAmount(uint64 timestamp) internal view returns (uint256) {
        uint256 totalAllocation = address(this).balance + released();
        return _vestingSchedule(totalAllocation, timestamp);
    }

    /// @notice Calculates the total vested ERC20 token amount at a given timestamp.
    /// @param token The ERC20 token contract address.
    /// @param timestamp The Unix timestamp to evaluate.
    function vestedAmount(address token, uint64 timestamp) internal view returns (uint256) {
        uint256 totalAllocation = IERC20(token).balanceOf(address(this)) + released(token);
        return _vestingSchedule(totalAllocation, timestamp);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                RELEASE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Releases all currently releasable ETH to the beneficiary (owner).
    /// @dev Anyone may call; funds always go to the owner.
    function release() internal {
        uint256 amount = releasable();
        vestingWalletStorage()._released += amount;
        (bool ok,) = OwnableLib.owner().call{value: amount}("");
        require(ok, "VestingWallet: ETH transfer failed");
        emit IVestingWallet.EtherReleased(amount);
    }

    /// @notice Releases all currently releasable tokens of an ERC20 to the beneficiary (owner).
    /// @param token The ERC20 token contract address.
    /// @dev Anyone may call; funds always go to the owner.
    function release(address token) internal {
        uint256 amount = releasable(token);
        vestingWalletStorage()._erc20Released[token] += amount;
        bool ok = IERC20(token).transfer(OwnableLib.owner(), amount);
        require(ok, "VestingWallet: ERC20 transfer failed");
        emit IVestingWallet.ERC20Released(token, amount);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           INTERNAL SCHEDULE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Applies the linear vesting formula to a total allocation.
    /// @param totalAllocation The total amount to be vested (balance + already released).
    /// @param timestamp The timestamp at which to evaluate.
    /// @return The vested amount at the given timestamp.
    function _vestingSchedule(uint256 totalAllocation, uint64 timestamp) internal view returns (uint256) {
        VestingWalletStorage storage $ = vestingWalletStorage();
        uint64 _start = $._start;
        uint64 _duration = $._duration;
        if (timestamp < _start) return 0;
        if (timestamp >= _start + _duration) return totalAllocation;
        return (totalAllocation * (timestamp - _start)) / _duration;
    }
}

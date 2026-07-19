// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {OwnableLib} from "@diamond/libraries/OwnableLib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {VestingWallet} from "@lattice/utils/VestingWallet.sol";
import {VestingWalletLib} from "@lattice/utils/libraries/VestingWalletLib.sol";

/// @title VestingWalletStandalone
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/finance/VestingWallet.sol)
/// @notice A non-Diamond deployable VestingWallet that can be used as a standalone contract.
/// @dev Combines VestingWallet functionality with direct ownership via OwnableLib.
/// The beneficiary is the Ownable owner; to change the beneficiary transfer ownership.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract VestingWalletStandalone is VestingWallet, Initializable {
    /// @param beneficiary The initial beneficiary (owner) who will receive vested tokens.
    /// @param startTimestamp The Unix timestamp at which vesting begins.
    /// @param durationSeconds The total duration of the vesting period in seconds.
    constructor(address beneficiary, uint64 startTimestamp, uint64 durationSeconds) initializer {
        OwnableLib.initializeOwner(beneficiary);
        VestingWalletLib.__VestingWallet_init(startTimestamp, durationSeconds);
    }

    /// @dev Accepts ETH deposits.
    receive() external payable {}
}

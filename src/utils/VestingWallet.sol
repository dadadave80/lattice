// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IVestingWallet} from "@lattice/interfaces/utils/IVestingWallet.sol";
import {VestingWalletLib} from "@lattice/utils/libraries/VestingWalletLib.sol";

/// @title VestingWallet
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/finance/VestingWallet.sol)
/// @notice A Diamond facet that holds ETH/ERC20 tokens and releases them linearly over time
/// to the Ownable beneficiary.
/// @dev Stateless delegator — all logic and storage live in VestingWalletLib.
/// Consumers should deploy this as a facet within a Diamond proxy alongside OwnableFacet.
/// CUSTODY: the vesting allocation is the diamond's WHOLE balance, `balanceOf(address(this)) + released`,
/// and anyone may call `release`. Do not cut it next to a module that holds the same asset (an ERC-4626
/// vault, BridgeERC20 or ShieldedPool escrow): once vesting ends, that module's funds go to the owner.
/// One custodian per asset per diamond (issue #240).
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract VestingWallet is IVestingWallet {
    /// @inheritdoc IVestingWallet
    function start() public view virtual returns (uint256) {
        return VestingWalletLib.start();
    }

    /// @inheritdoc IVestingWallet
    function duration() public view virtual returns (uint256) {
        return VestingWalletLib.duration();
    }

    /// @inheritdoc IVestingWallet
    function end() public view virtual returns (uint256) {
        return VestingWalletLib.end();
    }

    /// @inheritdoc IVestingWallet
    function released() public view virtual returns (uint256) {
        return VestingWalletLib.released();
    }

    /// @inheritdoc IVestingWallet
    function released(address token) public view virtual returns (uint256) {
        return VestingWalletLib.released(token);
    }

    /// @inheritdoc IVestingWallet
    function releasable() public view virtual returns (uint256) {
        return VestingWalletLib.releasable();
    }

    /// @inheritdoc IVestingWallet
    function releasable(address token) public view virtual returns (uint256) {
        return VestingWalletLib.releasable(token);
    }

    /// @inheritdoc IVestingWallet
    function vestedAmount(uint64 timestamp) public view virtual returns (uint256) {
        return VestingWalletLib.vestedAmount(timestamp);
    }

    /// @inheritdoc IVestingWallet
    function vestedAmount(address token, uint64 timestamp) public view virtual returns (uint256) {
        return VestingWalletLib.vestedAmount(token, timestamp);
    }

    /// @inheritdoc IVestingWallet
    function release() public virtual {
        VestingWalletLib.release();
    }

    /// @inheritdoc IVestingWallet
    function release(address token) public virtual {
        VestingWalletLib.release(token);
    }
}

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

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect VestingWallet methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `duration()` 0x0fb5a6b4
    ///      `end()` 0xefbe1c1c
    ///      `releasable()` 0xfbccedae
    ///      `releasable(address)` 0xa3f8eace
    ///      `release()` 0x86d1a69f
    ///      `release(address)` 0x19165587
    ///      `released()` 0x96132521
    ///      `released(address)` 0x9852595c
    ///      `start()` 0xbe9a6555
    ///      `vestedAmount(address,uint64)` 0x810ec23b
    ///      `vestedAmount(uint64)` 0x0a17b06b
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"0fb5a6b4efbe1c1cfbccedaea3f8eace86d1a69f19165587961325219852595cbe9a6555810ec23b0a17b06b";
    }
}

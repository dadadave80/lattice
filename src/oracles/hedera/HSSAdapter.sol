// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IHSSAdapter} from "@lattice/interfaces/oracles/IHSSAdapter.sol";
import {HSSAdapterLib} from "@lattice/oracles/hedera/HSSAdapterLib.sol";

/// @title HSSAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from hiero-ledger/hiero-contracts (https://github.com/hiero-ledger/hiero-contracts)
/// @notice Diamond facet for Hedera Schedule Service automation: scheduled (self-)calls paid by the diamond,
///         plus contract-key signatures on native scheduled transactions.
/// @dev Stateless delegator over HSSAdapterLib. Only meaningful on Hedera.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Hedera
contract HSSAdapter is IHSSAdapter {
    /// @inheritdoc IHSSAdapter
    function hasScheduleCapacity(uint256 expirySecond, uint256 gasLimit) external view virtual override returns (bool) {
        return HSSAdapterLib.hasScheduleCapacity(expirySecond, gasLimit);
    }

    /// @inheritdoc IHSSAdapter
    function scheduleOf(bytes32 jobId) external view virtual override returns (address scheduleAddress) {
        return HSSAdapterLib.scheduleOf(jobId);
    }

    /// @inheritdoc IHSSAdapter
    function scheduleCall(address to, uint256 expirySecond, uint256 gasLimit, uint64 value, bytes calldata data)
        external
        virtual
        override
        returns (address scheduleAddress)
    {
        return HSSAdapterLib.scheduleCall(to, expirySecond, gasLimit, value, data);
    }

    /// @inheritdoc IHSSAdapter
    function scheduleSelfCall(bytes32 jobId, uint256 expirySecond, uint256 gasLimit, bytes calldata data)
        external
        virtual
        override
        returns (address scheduleAddress)
    {
        return HSSAdapterLib.scheduleSelfCall(jobId, expirySecond, gasLimit, data);
    }

    /// @inheritdoc IHSSAdapter
    function deleteSchedule(address scheduleAddress) external virtual override {
        HSSAdapterLib.deleteSchedule(scheduleAddress);
    }

    /// @inheritdoc IHSSAdapter
    function authorizeSchedule(address scheduleAddress) external virtual override {
        HSSAdapterLib.authorizeSchedule(scheduleAddress);
    }

    /// @inheritdoc IHSSAdapter
    function completeSelfCall(bytes32 jobId) external virtual override {
        HSSAdapterLib.completeSelfCall(jobId);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643). Order matches `forge inspect HSSAdapter
    ///      methodIdentifiers` (alphabetical by signature); kept in exact parity by ExportSelectorsParityTest. Chunks:
    ///      `authorizeSchedule(address)` 0xf0637961
    ///      `completeSelfCall(bytes32)` 0x1735e9e0
    ///      `deleteSchedule(address)` 0x72d42394
    ///      `hasScheduleCapacity(uint256,uint256)` 0xdfb4a999
    ///      `scheduleCall(address,uint256,uint256,uint64,bytes)` 0x6f5bfde8
    ///      `scheduleOf(bytes32)` 0xec2a7610
    ///      `scheduleSelfCall(bytes32,uint256,uint256,bytes)` 0x193704bb
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"f06379611735e9e072d42394dfb4a9996f5bfde8ec2a7610193704bb";
    }
}

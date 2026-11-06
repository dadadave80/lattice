// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IHSSAdapterRecovery} from "@lattice/interfaces/oracles/IHSSAdapterRecovery.sol";
import {HSSAdapterLib} from "@lattice/oracles/hedera/HSSAdapterLib.sol";

/// @title HSSAdapterRecovery
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from hiero-ledger/hiero-contracts (https://github.com/hiero-ledger/hiero-contracts)
/// @notice Companion facet for generation-bound HSS self-calls and scheduler-authorized recovery.
/// @dev Install atomically with the matching HSSAdapter upgrade. Shares its append-only namespace.
/// @custom:lattice-source Hedera
/// @custom:lattice-requires HSSAdapter convention full-schedule-management-surface;
/// @custom:lattice-requires AccessControl|AccessControlEnumerable|AccessControlTimed convention scheduler-role-management;
/// @custom:lattice-family none
/// @custom:lattice-owns none;
/// @custom:lattice-touches lattice.storage.HSSAdapter;
/// @custom:lattice-init HSSAdapterRecoveryInit
/// @custom:lattice-seam none;
contract HSSAdapterRecovery is IHSSAdapterRecovery {
    /// @inheritdoc IHSSAdapterRecovery
    function cancelSelfCall(bytes32 jobId) external returns (bool scheduleDeleted) {
        return HSSAdapterLib.cancelSelfCall(jobId);
    }

    /// @inheritdoc IHSSAdapterRecovery
    function executeSelfCall(bytes32 jobId, uint256 generation, bytes calldata data) external {
        HSSAdapterLib.executeSelfCall(jobId, generation, data);
    }

    /// @notice ERC-8153 export of the two recovery selectors, excluding exportSelectors itself.
    function exportSelectors() external pure returns (bytes memory) {
        return hex"cb60176f8670ca3b";
    }
}

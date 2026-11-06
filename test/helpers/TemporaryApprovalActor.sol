// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title TemporaryApprovalActor
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Batches real nested calls inside one transaction; optional failures preserve the caller's frame.
contract TemporaryApprovalActor {
    struct Action {
        address target;
        bytes data;
        bool allowFailure;
    }

    error DeliberateRollback();

    function run(Action[] calldata actions) external returns (bytes[] memory) {
        return _run(actions);
    }

    function runAndRevert(Action[] calldata actions) external {
        _run(actions);
        revert DeliberateRollback();
    }

    function _run(Action[] calldata actions) internal returns (bytes[] memory results) {
        results = new bytes[](actions.length);
        for (uint256 i; i < actions.length; ++i) {
            (bool ok, bytes memory result) = actions[i].target.call(actions[i].data);
            if (!ok && !actions[i].allowFailure) {
                assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
            }
            results[i] = result;
        }
    }
}

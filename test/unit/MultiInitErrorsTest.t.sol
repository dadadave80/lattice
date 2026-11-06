// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MultiInit, MultiInit__StepFailed} from "@diamond/initializers/MultiInit.sol";
import {MultiInitErrors} from "@lattice-test/helpers/MultiInitErrors.sol";
import {Test} from "forge-std/Test.sol";

contract MultiInitErrorsTest is Test {
    function witness(uint256 index, bytes memory batchCall, bytes memory inner) external pure returns (bytes memory) {
        return MultiInitErrors.at(index, batchCall, inner);
    }

    function test_ExactTargetIndexAndInnerBytesComeFromTypedInputs() public pure {
        address[] memory inits = new address[](2);
        bytes[] memory calls = new bytes[](2);
        inits[0] = address(0xA);
        inits[1] = address(0xB);
        bytes memory inner = hex"0123456789abcdef";
        assertEq(
            MultiInitErrors.at(1, abi.encodeCall(MultiInit.multiInit, (inits, calls)), inner),
            abi.encodeWithSelector(MultiInit__StepFailed.selector, 1, address(0xB), inner)
        );
    }

    function test_WrongSelectorCannotBecomeAnExpectedFailure() public {
        vm.expectRevert(MultiInitErrors.InvalidBatchWitness.selector);
        this.witness(0, abi.encodeWithSignature("other(address[],bytes[])", new address[](1), new bytes[](1)), "");
    }

    function test_MissingStepCannotBecomeAnExpectedFailure() public {
        bytes memory callData = abi.encodeCall(MultiInit.multiInit, (new address[](1), new bytes[](1)));
        vm.expectRevert(MultiInitErrors.InvalidBatchWitness.selector);
        this.witness(1, callData, "");
    }

    function test_MismatchedArraysCannotBecomeAnExpectedFailure() public {
        bytes memory callData = abi.encodeCall(MultiInit.multiInit, (new address[](1), new bytes[](0)));
        vm.expectRevert(MultiInitErrors.InvalidBatchWitness.selector);
        this.witness(0, callData, "");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    GOVERNED_DIAMOND_CUT_STORAGE_SLOT,
    GovernedDiamondCutLib,
    UPGRADE_EXECUTOR_ROLE
} from "@lattice/governance/libraries/GovernedDiamondCutLib.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/IGovernedDiamondCut.sol";
import {Test} from "forge-std/Test.sol";

/// @title GovernedDiamondCutTester
/// @notice Unit tests for the GovernedDiamondCut module.
contract GovernedDiamondCutTester is Test {
    /// @notice The interface exposes exactly one function (`diamondCut`), so its interfaceId
    ///         equals that function's selector — which is the canonical EIP-2535 cut selector
    ///         0x1f931c1c, identical to IDiamondCut. This is intentional: GovernedDiamondCut
    ///         replaces the stock DiamondCutFacet at the same selector.
    function test_InterfaceIdIsCutSelector() public pure {
        assertEq(
            type(IGovernedDiamondCut).interfaceId,
            bytes4(0x1f931c1c),
            "GovernedDiamondCut iface id must be the cut selector"
        );
    }

    function _erc7201Slot(string memory id) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256(bytes(id))) - 1)) & ~bytes32(uint256(0xff));
    }

    function test_StorageSlotDerivation() public pure {
        assertEq(
            GOVERNED_DIAMOND_CUT_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.GovernedDiamondCut"),
            "GovernedDiamondCut storage slot mismatch"
        );
    }

    function test_UpgradeExecutorRoleConstant() public pure {
        assertEq(UPGRADE_EXECUTOR_ROLE, keccak256("UPGRADE_EXECUTOR_ROLE"), "role constant mismatch");
    }
}

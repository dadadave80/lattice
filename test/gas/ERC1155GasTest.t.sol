// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC1155} from "@lattice/tokens/ERC1155.sol";
import {ERC1155Lib} from "@lattice/tokens/libraries/ERC1155Lib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Minimal mock ERC1155 for gas tests.
contract GasERC1155 is ERC1155, AccessControl {
    function initialize(string memory uri_, address admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        ERC1155Lib.__ERC1155_init(uri_);
        AccessControlLib.__AccessControl_init(admin);
        InitializableLib.postInitializer(s);
    }

    function mintBatchHelper(address to, uint256[] calldata ids, uint256[] calldata values, bytes calldata data)
        external
    {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ERC1155Lib._mintBatch(to, ids, values, data);
    }

    function mintHelper(address to, uint256 id, uint256 value, bytes calldata data) external {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ERC1155Lib._mint(to, id, value, data);
    }

    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

/// @title ERC1155GasTest
/// @notice Gas snapshot tests for hot paths in the ERC1155 module.
contract ERC1155GasTest is Test {
    GasERC1155 token;

    address admin = address(0xA);
    address alice = address(0x1);
    address bob = address(0x2);

    // Generous upper bounds (~3× expected).
    uint256 constant GAS_BOUND_MINT_BATCH = 200_000;
    uint256 constant GAS_BOUND_BATCH_TRANSFER = 300_000;
    uint256 constant GAS_BOUND_SET_APPROVAL = 60_000;

    function setUp() public {
        token = new GasERC1155();
        token.initialize("https://token.uri/{id}", admin);
    }

    /// @notice Gas cost of _mintBatch with 5 different token IDs.
    function test_Gas_MintBatch() public {
        uint256[] memory ids = new uint256[](5);
        uint256[] memory amounts = new uint256[](5);
        for (uint256 i; i < 5; ++i) {
            ids[i] = i + 1;
            amounts[i] = 100e18;
        }

        vm.prank(admin);
        vm.startSnapshotGas("ERC1155.mintBatch");
        token.mintBatchHelper(alice, ids, amounts, "");
        uint256 gasUsed = vm.stopSnapshotGas();
        assertLt(gasUsed, GAS_BOUND_MINT_BATCH, "ERC1155.mintBatch gas regression");
    }

    /// @notice Gas cost of safeBatchTransferFrom with 5 tokens between EOAs.
    function test_Gas_SafeBatchTransferFrom() public {
        uint256[] memory ids = new uint256[](5);
        uint256[] memory amounts = new uint256[](5);
        for (uint256 i; i < 5; ++i) {
            ids[i] = i + 1;
            amounts[i] = 100e18;
        }

        vm.prank(admin);
        token.mintBatchHelper(alice, ids, amounts, "");

        vm.prank(alice);
        vm.startSnapshotGas("ERC1155.safeBatchTransferFrom");
        token.safeBatchTransferFrom(alice, bob, ids, amounts, "");
        uint256 gasUsed = vm.stopSnapshotGas();
        assertLt(gasUsed, GAS_BOUND_BATCH_TRANSFER, "ERC1155.safeBatchTransferFrom gas regression");
    }

    /// @notice Gas cost of setApprovalForAll.
    function test_Gas_SetApprovalForAll() public {
        vm.prank(alice);
        vm.startSnapshotGas("ERC1155.setApprovalForAll");
        token.setApprovalForAll(bob, true);
        uint256 gasUsed = vm.stopSnapshotGas();
        assertLt(gasUsed, GAS_BOUND_SET_APPROVAL, "ERC1155.setApprovalForAll gas regression");
    }
}

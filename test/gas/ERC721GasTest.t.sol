// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {ERC721} from "@lattice/tokens/ERC721/ERC721.sol";
import {ERC721Lib} from "@lattice/tokens/ERC721/libraries/ERC721Lib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Minimal mock ERC721 for gas tests.
contract GasERC721 is ERC721, AccessControl {
    function initialize(string memory name_, string memory symbol_, address admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        ERC721Lib.__ERC721_init(name_, symbol_);
        AccessControlLib.__AccessControl_init(admin);
        InitializableLib.postInitializer(s);
    }

    function mintHelper(address to, uint256 tokenId) external {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ERC721Lib._mint(to, tokenId);
    }

    function safeMintHelper(address to, uint256 tokenId) external {
        AccessControlLib.checkRole(DEFAULT_ADMIN_ROLE);
        ERC721Lib._safeMint(to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

/// @title ERC721GasTest
/// @notice Gas snapshot tests for hot paths in the ERC721 module.
contract ERC721GasTest is Test {
    GasERC721 token;

    address admin = address(0xA);
    address alice = address(0x1);
    address bob = address(0x2);

    uint256 constant TOKEN_1 = 1;
    uint256 constant TOKEN_2 = 2;
    uint256 constant TOKEN_3 = 3;
    uint256 constant TOKEN_4 = 4;

    // Generous upper bounds (~3× expected).
    uint256 constant GAS_BOUND_MINT = 90_000;
    uint256 constant GAS_BOUND_TRANSFER = 90_000;
    uint256 constant GAS_BOUND_SAFE_TRANSFER = 90_000;
    uint256 constant GAS_BOUND_APPROVE = 120_000;

    function setUp() public {
        token = new GasERC721();
        token.initialize("Gas NFT", "GNFT", admin);
    }

    /// @notice Gas cost of minting a new token to an EOA.
    function test_Gas_Mint() public {
        vm.prank(admin);
        vm.startSnapshotGas("ERC721.mint");
        token.mintHelper(alice, TOKEN_1);
        uint256 gasUsed = vm.stopSnapshotGas();
        assertLt(gasUsed, GAS_BOUND_MINT, "ERC721.mint gas regression");
    }

    /// @notice Gas cost of transferFrom between two EOAs.
    function test_Gas_Transfer() public {
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_2);

        vm.prank(alice);
        vm.startSnapshotGas("ERC721.transferFrom");
        token.transferFrom(alice, bob, TOKEN_2);
        uint256 gasUsed = vm.stopSnapshotGas();
        assertLt(gasUsed, GAS_BOUND_TRANSFER, "ERC721.transferFrom gas regression");
    }

    /// @notice Gas cost of safeTransferFrom to a plain EOA.
    function test_Gas_SafeTransfer() public {
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_3);

        vm.prank(alice);
        vm.startSnapshotGas("ERC721.safeTransferFrom");
        token.safeTransferFrom(alice, bob, TOKEN_3);
        uint256 gasUsed = vm.stopSnapshotGas();
        assertLt(gasUsed, GAS_BOUND_SAFE_TRANSFER, "ERC721.safeTransferFrom gas regression");
    }

    /// @notice Gas cost of approving a single token spender.
    function test_Gas_Approve() public {
        vm.prank(admin);
        token.mintHelper(alice, TOKEN_4);

        vm.prank(alice);
        vm.startSnapshotGas("ERC721.approve");
        token.approve(bob, TOKEN_4);
        uint256 gasUsed = vm.stopSnapshotGas();
        assertLt(gasUsed, GAS_BOUND_APPROVE, "ERC721.approve gas regression");
    }
}

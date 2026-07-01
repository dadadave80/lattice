// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib, DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IERC2981} from "@lattice/interfaces/tokens/IERC2981.sol";
import {ERC2981} from "@lattice/tokens/ERC2981/ERC2981.sol";
import {ERC2981Lib} from "@lattice/tokens/ERC2981/libraries/ERC2981Lib.sol";
import {Test} from "forge-std/Test.sol";

/// @title MockERC2981Contract
/// @notice Mock ERC-2981 royalty contract for testing.
contract MockERC2981Contract is ERC2981, AccessControl {
    function initialize(address admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        ERC2981Lib.__ERC2981_init();
        AccessControlLib.__AccessControl_init(admin);
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 interfaceId) public view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

/// @title ERC2981Test
contract ERC2981Test is Test {
    MockERC2981Contract royalty;

    address admin = address(0xA);
    address alice = address(0x1);
    address bob = address(0x2);
    address treasury = address(0xFEE);

    uint256 constant TOKEN_1 = 1;
    uint256 constant TOKEN_2 = 2;

    function setUp() public {
        royalty = new MockERC2981Contract();
        royalty.initialize(admin);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          DEFAULT ROYALTY TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_DefaultRoyaltyReturnedForAnyToken() public {
        vm.prank(admin);
        royalty.setDefaultRoyalty(treasury, 500); // 5%

        (address receiver, uint256 amount) = royalty.royaltyInfo(TOKEN_1, 10_000);
        assertEq(receiver, treasury);
        assertEq(amount, 500); // 5% of 10_000

        (receiver, amount) = royalty.royaltyInfo(TOKEN_2, 10_000);
        assertEq(receiver, treasury);
        assertEq(amount, 500);
    }

    function test_RoyaltyAmountCalculation() public {
        vm.prank(admin);
        royalty.setDefaultRoyalty(treasury, 250); // 2.5%

        (address receiver, uint256 amount) = royalty.royaltyInfo(TOKEN_1, 1_000_000);
        assertEq(receiver, treasury);
        assertEq(amount, 25_000); // 2.5% of 1_000_000
    }

    function test_ZeroRoyaltyDefault() public view {
        // No royalty set: receiver is zero, amount is zero
        (address receiver, uint256 amount) = royalty.royaltyInfo(TOKEN_1, 10_000);
        assertEq(receiver, address(0));
        assertEq(amount, 0);
    }

    function test_SetDefaultRoyaltyWithFractionGreaterThanDenominatorReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC2981.ERC2981InvalidDefaultRoyalty.selector, uint256(10_001), uint256(10_000))
        );
        vm.prank(admin);
        royalty.setDefaultRoyalty(treasury, 10_001);
    }

    function test_SetDefaultRoyaltyWithZeroReceiverReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC2981.ERC2981InvalidDefaultRoyaltyReceiver.selector, address(0)));
        vm.prank(admin);
        royalty.setDefaultRoyalty(address(0), 500);
    }

    function test_NonAdminSetDefaultRoyaltyReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, DEFAULT_ADMIN_ROLE)
        );
        vm.prank(alice);
        royalty.setDefaultRoyalty(treasury, 500);
    }

    function test_DeleteDefaultRoyaltyClearsInfo() public {
        vm.prank(admin);
        royalty.setDefaultRoyalty(treasury, 500);

        vm.prank(admin);
        royalty.deleteDefaultRoyalty();

        (address receiver, uint256 amount) = royalty.royaltyInfo(TOKEN_1, 10_000);
        assertEq(receiver, address(0));
        assertEq(amount, 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         TOKEN-SPECIFIC ROYALTY TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_TokenSpecificRoyaltyOverridesDefault() public {
        vm.prank(admin);
        royalty.setDefaultRoyalty(treasury, 500); // 5% default

        vm.prank(admin);
        royalty.setTokenRoyalty(TOKEN_1, alice, 1000); // 10% for TOKEN_1

        (address receiver, uint256 amount) = royalty.royaltyInfo(TOKEN_1, 10_000);
        assertEq(receiver, alice);
        assertEq(amount, 1000); // 10% for TOKEN_1

        // TOKEN_2 still uses default
        (receiver, amount) = royalty.royaltyInfo(TOKEN_2, 10_000);
        assertEq(receiver, treasury);
        assertEq(amount, 500);
    }

    function test_ResetTokenRoyaltyFallsBackToDefault() public {
        vm.prank(admin);
        royalty.setDefaultRoyalty(treasury, 500); // 5% default

        vm.prank(admin);
        royalty.setTokenRoyalty(TOKEN_1, alice, 1000); // Override

        vm.prank(admin);
        royalty.resetTokenRoyalty(TOKEN_1); // Remove override

        (address receiver, uint256 amount) = royalty.royaltyInfo(TOKEN_1, 10_000);
        assertEq(receiver, treasury); // Falls back to default
        assertEq(amount, 500);
    }

    function test_SetTokenRoyaltyFractionExceedsDenominatorReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC2981.ERC2981InvalidTokenRoyalty.selector, TOKEN_1, uint256(10_001), uint256(10_000)
            )
        );
        vm.prank(admin);
        royalty.setTokenRoyalty(TOKEN_1, alice, 10_001);
    }

    function test_SetTokenRoyaltyZeroReceiverReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC2981.ERC2981InvalidTokenRoyaltyReceiver.selector, TOKEN_1, address(0))
        );
        vm.prank(admin);
        royalty.setTokenRoyalty(TOKEN_1, address(0), 500);
    }

    function test_NonAdminSetTokenRoyaltyReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, DEFAULT_ADMIN_ROLE)
        );
        vm.prank(alice);
        royalty.setTokenRoyalty(TOKEN_1, treasury, 500);
    }

    function test_FullDenominatorRoyalty() public {
        vm.prank(admin);
        royalty.setDefaultRoyalty(treasury, 10_000); // 100%

        (address receiver, uint256 amount) = royalty.royaltyInfo(TOKEN_1, 1_000);
        assertEq(receiver, treasury);
        assertEq(amount, 1_000); // 100% of 1_000
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsERC2981Interface() public view {
        assertTrue(royalty.supportsInterface(0x2a55205a)); // IERC2981
    }
}

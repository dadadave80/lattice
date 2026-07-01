// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {ERC2981TestBase} from "@lattice-test/base/ERC2981TestBase.sol";
import {DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IERC2981} from "@lattice/interfaces/tokens/IERC2981.sol";
import {ERC2981} from "@lattice/tokens/ERC2981/ERC2981.sol";

/// @title ERC2981Test
/// @notice Exercises the ERC-2981 royalty facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployERC2981} script (see {ERC2981TestBase}) — every call below routes through the diamond's
///         `delegatecall` dispatch, not a flattened inheritance mock. Admin gating is enforced by the cut-in
///         `AccessControl` facet; `supportsInterface` by the cut-in `ERC165Facet`.
contract ERC2981Test is ERC2981TestBase {
    address admin = address(0xA);
    address alice = address(0x1);
    address bob = address(0x2);
    address treasury = address(0xFEE);

    uint256 constant TOKEN_1 = 1;
    uint256 constant TOKEN_2 = 2;

    function setUp() public {
        diamond = _deployERC2981(admin);
        royalty = ERC2981(diamond);
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
        assertTrue(ERC165Facet(diamond).supportsInterface(0x2a55205a)); // IERC2981
    }
}

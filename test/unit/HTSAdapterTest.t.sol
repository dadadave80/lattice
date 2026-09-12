// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {MockHederaTokenService} from "@lattice-test/mocks/hedera/MockHederaTokenService.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IHTSAdapter} from "@lattice/interfaces/tokens/IHTSAdapter.sol";
import {HTSAdapter} from "@lattice/tokens/hedera/HTSAdapter.sol";
import {HTSAdapterLib, HTS_MANAGER_ROLE, HTS_OPERATOR_ROLE} from "@lattice/tokens/hedera/HTSAdapterLib.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Composite that stands in for a diamond: AccessControl + HTSAdapter + initializer (same shape as the
///         fork-test composites elsewhere in the suite).
contract MockHTSDiamond is AccessControl, HTSAdapter, Initializable {
    function exportSelectors() external pure virtual override(AccessControl, HTSAdapter) returns (bytes memory) {}

    function initialize(address admin) external initializer {
        AccessControlLib.__AccessControl_init(admin);
        AccessControlLib._grantRole(HTS_MANAGER_ROLE, admin);
        AccessControlLib._grantRole(HTS_OPERATOR_ROLE, admin);
        HTSAdapterLib.__HTSAdapter_init();
    }

    function supportsInterface(bytes4 id) public view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }

    receive() external payable {}
}

/// @title HTSAdapterTest
/// @notice Unit tests against a `vm.etch`ed HTS mock at 0x167 — no fork, no RPC, no npm. Proves the adapter's
///         response-code → custom-error mapping and the delegatable-key requirement end to end.
contract HTSAdapterTest is Test {
    address constant HTS = 0x0000000000000000000000000000000000000167;

    MockHTSDiamond diamond;
    MockHederaTokenService hts;
    address admin = makeAddr("admin");
    address alice = makeAddr("alice");

    function setUp() public {
        vm.etch(HTS, address(new MockHederaTokenService()).code);
        hts = MockHederaTokenService(payable(HTS));
        diamond = new MockHTSDiamond();
        diamond.initialize(admin);
        vm.deal(admin, 100 ether);
    }

    function _createFT() internal returns (address token) {
        vm.prank(admin);
        token = diamond.createFungibleToken{value: 10 ether}("Lattice HBAR Test", "LHT", "memo", 8, 1_000, 0);
    }

    function test_SupportsInterface() public view {
        assertTrue(diamond.supportsInterface(type(IHTSAdapter).interfaceId), "IHTSAdapter not registered");
    }

    function test_CreateFungibleToken_DiamondIsTreasuryAndKeyHolder() public {
        address token = _createFT();
        assertTrue(hts.tokenExists(token));
        assertEq(hts.supplyKeyHolder(token), address(diamond), "supply key must be the diamond (delegatable)");
        assertEq(hts.balanceOf(token, address(diamond)), 1_000);
        assertTrue(diamond.isAssociated(token), "treasury is auto-associated");
        assertTrue(diamond.isHTSToken(token));
        assertEq(diamond.htsTokenType(token), 0);
        assertEq(diamond.createdTokens().length, 1);
    }

    function test_Mint_Burn_Transfer() public {
        address token = _createFT();
        vm.startPrank(admin);
        (int64 supply,) = diamond.mintToken(token, 500, new bytes[](0));
        assertEq(supply, 1_500);
        assertEq(diamond.burnToken(token, 200, new int64[](0)), 1_300);
        vm.stopPrank();

        // Receiver must be associated first (the network rule the adapter surfaces as a typed error).
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IHTSAdapter.HTSTokenNotAssociated.selector, token, address(diamond)));
        diamond.transferToken(token, alice, 100);

        vm.prank(alice);
        hts.associateToken(alice, token);
        vm.prank(admin);
        vm.expectEmit(true, true, true, true);
        emit IHTSAdapter.HTSTokenTransferred(token, address(diamond), alice, 100);
        diamond.transferToken(token, alice, 100);
        assertEq(hts.balanceOf(token, alice), 100);
    }

    function test_ResponseCodeMapping() public {
        address token = _createFT();
        hts.force(bytes4(keccak256("mintToken(address,int64,bytes[])")), 326); // INVALID_FULL_PREFIX_SIGNATURE_FOR_PRECOMPILE
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IHTSAdapter.HTSKeyNotActive.selector, token));
        diamond.mintToken(token, 1, new bytes[](0));

        hts.force(bytes4(keccak256("mintToken(address,int64,bytes[])")), 236); // TOKEN_MAX_SUPPLY_REACHED
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(IHTSAdapter.HTSMaxSupplyReached.selector, token));
        diamond.mintToken(token, 1, new bytes[](0));

        hts.force(bytes4(keccak256("associateToken(address,address)")), 166); // unmapped → catch-all
        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IHTSAdapter.HTSCallFailed.selector, bytes4(keccak256("associateToken(address,address)")), int64(166)
            )
        );
        diamond.associateToken(token);
    }

    function test_RoleGating() public {
        address token = _createFT();
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, HTS_OPERATOR_ROLE)
        );
        diamond.transferToken(token, alice, 1);
    }

    function test_CreateRejectsBadSupply() public {
        vm.prank(admin);
        vm.expectRevert(IHTSAdapter.HTSInvalidAmount.selector);
        diamond.createFungibleToken{value: 1 ether}("x", "x", "", 0, 10, 5);
    }
}

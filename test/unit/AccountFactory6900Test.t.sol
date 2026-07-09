// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {Account6900BlueprintHelper} from "@lattice-test/helpers/Account6900BlueprintHelper.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccountFactory6900} from "@lattice/accounts/erc6900/AccountFactory6900.sol";
import {AccountInit6900} from "@lattice/accounts/erc6900/AccountInit6900.sol";
import {ERC6900ModuleManager} from "@lattice/accounts/erc6900/ERC6900ModuleManager.sol";
import {ERC6900TypesLib} from "@lattice/accounts/erc6900/libraries/ERC6900TypesLib.sol";
import {IAccountFactory} from "@lattice/interfaces/accounts/IAccountFactory.sol";
import {
    IERC6900Account,
    IERC6900AccountView,
    ModuleEntity,
    ValidationConfig,
    ValidationDataView,
    ValidationFlags
} from "@lattice/interfaces/external/IERC6900.sol";

contract AccountFactory6900Test is Account6900BlueprintHelper {
    AccountFactory6900 factory;
    address entryPoint = address(0xE417);
    address owner = address(0xA11CE);
    bytes32 salt = keccak256("salt-1");

    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes4 constant IERC1271_ID = 0x1626ba7e;

    function setUp() public {
        (FacetCut[] memory blueprint, AccountInit6900 init) = _accountBlueprint6900(entryPoint);
        factory = new AccountFactory6900(blueprint, address(init));
    }

    function test_GetAddressMatchesCreate() public {
        address predicted = factory.getAddress(owner, salt);
        address created = factory.createAccount(owner, salt);
        assertEq(created, predicted, "create != predicted");
        assertGt(created.code.length, 0, "no code deployed");
    }

    function test_Idempotent() public {
        address first = factory.createAccount(owner, salt);
        address second = factory.createAccount(owner, salt); // must not revert
        assertEq(first, second, "non-idempotent");
    }

    function test_OwnerAndSaltBindAddress() public view {
        assertTrue(factory.getAddress(owner, salt) != factory.getAddress(address(0xBEEF), salt), "owner not bound");
        assertTrue(factory.getAddress(owner, salt) != factory.getAddress(owner, keccak256("salt-2")), "salt not bound");
    }

    function test_EmitsAccountCreated() public {
        address predicted = factory.getAddress(owner, salt);
        vm.expectEmit(true, true, false, true, address(factory));
        emit IAccountFactory.AccountCreated(predicted, owner, salt);
        factory.createAccount(owner, salt);
    }

    function test_DeployedAccountWired() public {
        address account = factory.createAccount(owner, salt);
        assertEq(ERC6900ModuleManager(account).accountId(), "lattice.modular-account-6900.0.1.0", "accountId");
        // The 6900 account is admin-managed by the owner EOA (no default signer to self-bootstrap).
        assertTrue(AccessControl(account).hasRole(DEFAULT_ADMIN_ROLE, owner), "owner not admin");
        assertTrue(ERC165Facet(account).supportsInterface(IERC1271_ID), "IERC1271 not registered");
        assertTrue(
            ERC165Facet(account).supportsInterface(type(IERC6900Account).interfaceId), "IERC6900Account not registered"
        );
        assertTrue(
            ERC165Facet(account).supportsInterface(type(IERC6900AccountView).interfaceId),
            "IERC6900AccountView not registered"
        );
        assertEq(DiamondLoupeFacet(account).facetAddresses().length, 9, "blueprint not fully wired");
    }

    function test_AdminCanInstallValidationThroughProxy() public {
        address account = factory.createAccount(owner, salt);
        ModuleEntity me = ERC6900TypesLib.pack(address(0xBEEF), 1);
        ValidationConfig cfg = ERC6900TypesLib.pack(address(0xBEEF), 1, true, false, true); // global + userOp

        vm.prank(owner);
        IERC6900Account(account).installValidation(cfg, new bytes4[](0), "", new bytes[](0));

        ValidationDataView memory d = IERC6900AccountView(account).getValidationData(me);
        assertEq(uint8(ValidationFlags.unwrap(d.validationFlags)), 0x05, "validation installed (global|userOp)");
    }

    function test_NonAdminCannotInstallValidation() public {
        address account = factory.createAccount(owner, salt);
        ValidationConfig cfg = ERC6900TypesLib.pack(address(0xBEEF), 1, true, false, true);
        vm.prank(address(0xBAD));
        vm.expectRevert();
        IERC6900Account(account).installValidation(cfg, new bytes4[](0), "", new bytes[](0));
    }

    function test_RevertsOnEmptyBlueprint() public {
        FacetCut[] memory empty = new FacetCut[](0);
        vm.expectRevert(IAccountFactory.EmptyBlueprint.selector);
        new AccountFactory6900(empty, address(0x1417));
    }

    function test_CannotReinitialize() public {
        address account = factory.createAccount(owner, salt);
        FacetCut[] memory empty = new FacetCut[](0);
        vm.expectRevert();
        Diamond(payable(account)).initialize(empty, address(0), "");
    }
}

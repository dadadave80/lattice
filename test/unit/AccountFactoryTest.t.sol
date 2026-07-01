// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {DiamondCutFacet} from "@diamond/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {ERC1271Signature} from "@lattice/accounts/ERC1271Signature.sol";
import {ERC4337Validation} from "@lattice/accounts/ERC4337Validation.sol";
import {AccountFactory} from "@lattice/accounts/erc7579/AccountFactory.sol";
import {AccountInit} from "@lattice/accounts/erc7579/AccountInit.sol";
import {AccountSigner} from "@lattice/accounts/erc7579/AccountSigner.sol";
import {ERC7821Executor} from "@lattice/accounts/erc7579/ERC7821Executor.sol";
import {IAccountFactory} from "@lattice/interfaces/accounts/IAccountFactory.sol";
import {IERC7821} from "@lattice/interfaces/external/IERC7821.sol";

contract AccountFactoryTest is GetSelectors {
    AccountFactory factory;
    address entryPoint = address(0xE417);
    address owner = address(0xA11CE);
    bytes32 salt = keccak256("salt-1");

    bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes4 constant IERC1271_ID = 0x1626ba7e; // bytes4(keccak256("isValidSignature(bytes32,bytes)"))

    function setUp() public {
        // Shared facet singletons (deployed once, reused by every account).
        address cut = address(new DiamondCutFacet());
        address loupe = address(new DiamondLoupeFacet());
        address erc165 = address(new ERC165Facet());
        address access = address(new AccessControl());
        address signer = address(new AccountSigner());
        address validation = address(new ERC4337Validation());
        address erc1271 = address(new ERC1271Signature());
        address executor = address(new ERC7821Executor());

        FacetCut[] memory blueprint = new FacetCut[](8);
        blueprint[0] = _cut(cut, "DiamondCutFacet");
        blueprint[1] = _cut(loupe, "DiamondLoupeFacet");
        blueprint[2] = _cut(erc165, "ERC165Facet");
        blueprint[3] = _cut(access, "AccessControl");
        blueprint[4] = _cut(signer, "AccountSigner");
        blueprint[5] = _cut(validation, "ERC4337Validation");
        blueprint[6] = _cut(erc1271, "ERC1271Signature");
        blueprint[7] = _cut(executor, "ERC7821Executor");

        AccountInit init = new AccountInit(entryPoint);
        factory = new AccountFactory(blueprint, address(init));
    }

    function _cut(address facet, string memory name) internal returns (FacetCut memory) {
        return FacetCut({facetAddress: facet, action: FacetCutAction.Add, functionSelectors: _getSelectors(name)});
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
        assertEq(AccountSigner(first).owner(), owner, "owner mutated on re-call");
    }

    function test_OwnerBindsAddress() public view {
        assertTrue(
            factory.getAddress(owner, salt) != factory.getAddress(address(0xBEEF), salt), "owner not bound to address"
        );
    }

    function test_SaltBindsAddress() public view {
        assertTrue(factory.getAddress(owner, salt) != factory.getAddress(owner, keccak256("salt-2")), "salt not bound");
    }

    function test_EmitsAccountCreated() public {
        address predicted = factory.getAddress(owner, salt);
        vm.expectEmit(true, true, false, true, address(factory));
        emit IAccountFactory.AccountCreated(predicted, owner, salt);
        factory.createAccount(owner, salt);
    }

    function test_DeployedAccountInitialized() public {
        address account = factory.createAccount(owner, salt);
        assertEq(AccountSigner(account).owner(), owner, "owner not seeded");
        assertEq(ERC4337Validation(account).entryPoint(), entryPoint, "entryPoint not seeded");
        // The account administers itself: admin authority is the account, not the owner EOA.
        assertTrue(AccessControl(account).hasRole(DEFAULT_ADMIN_ROLE, account), "account not self-admin");
        assertFalse(AccessControl(account).hasRole(DEFAULT_ADMIN_ROLE, owner), "owner wrongly granted admin");
        assertTrue(ERC165Facet(account).supportsInterface(IERC1271_ID), "IERC1271 not registered");
        assertTrue(ERC165Facet(account).supportsInterface(type(IERC7821).interfaceId), "IERC7821 not registered");
        assertEq(DiamondLoupeFacet(account).facetAddresses().length, 8, "blueprint not fully wired");
    }

    function test_RevertsOnEmptyBlueprint() public {
        FacetCut[] memory empty = new FacetCut[](0);
        vm.expectRevert(IAccountFactory.EmptyBlueprint.selector);
        new AccountFactory(empty, address(0x1417));
    }

    function test_CannotReinitialize() public {
        address account = factory.createAccount(owner, salt);
        FacetCut[] memory empty = new FacetCut[](0);
        vm.expectRevert();
        Diamond(payable(account)).initialize(empty, address(0), "");
    }
}

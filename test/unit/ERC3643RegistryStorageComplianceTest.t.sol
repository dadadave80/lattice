// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {OwnableFacet} from "@diamond/facets/OwnableFacet.sol";
import {
    ERC3643RegistryTestBase,
    RegistryCallbackCaller,
    RegistryExecutionProbe,
    RegistryIdentityMock,
    RegistryRawIdentity
} from "@lattice-test/helpers/ERC3643RegistryTestHelpers.sol";
import {IERC3643Identity} from "@lattice/interfaces/external/erc3643/IERC3643Identity.sol";
import {ICompliance} from "@lattice/interfaces/tokens/erc3643/ICompliance.sol";
import {IIdentityRegistryStorage} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistryStorage.sol";
import {ERC3643ExecutionInProgress} from "@lattice/tokens/ERC3643/libraries/ERC3643ExecutionLib.sol";

contract ERC3643IdentityRegistryStorageTest is ERC3643RegistryTestBase {
    IIdentityRegistryStorage store;
    RegistryIdentityMock investor;
    address wallet = address(0xA11CE);

    function setUp() public {
        store = IIdentityRegistryStorage(_deployStorage());
        investor = new RegistryIdentityMock();
    }

    function test_OnlyBoundRegistryCanWriteEvenWhenCallerIsOwner() public {
        vm.expectRevert(
            abi.encodeWithSelector(IIdentityRegistryStorage.ERC3643UnauthorizedRegistry.selector, address(this))
        );
        store.addIdentityToStorage(wallet, investor, 840);
        store.bindIdentityRegistry(address(this));
        store.addIdentityToStorage(wallet, investor, 840);
        vm.prank(wallet);
        vm.expectRevert();
        store.modifyStoredInvestorCountry(wallet, 826);
        vm.prank(wallet);
        vm.expectRevert();
        store.removeIdentityFromStorage(wallet);
        vm.prank(wallet);
        vm.expectRevert();
        store.modifyStoredIdentity(wallet, investor);
        store.unbindIdentityRegistry(address(this));
        vm.expectRevert();
        store.modifyStoredInvestorCountry(wallet, 826);
        assertEq(store.storedInvestorCountry(wallet), 840);
    }

    function test_CounterfactualBindingDuplicateAndUnknownUnbinding() public {
        address futureRegistry = address(0xF070);
        assertEq(futureRegistry.code.length, 0);
        store.bindIdentityRegistry(futureRegistry);
        assertEq(store.linkedIdentityRegistries()[0], futureRegistry);
        vm.expectRevert(
            abi.encodeWithSelector(IIdentityRegistryStorage.ERC3643RegistryAlreadyBound.selector, futureRegistry)
        );
        store.bindIdentityRegistry(futureRegistry);
        store.unbindIdentityRegistry(futureRegistry);
        vm.expectRevert(
            abi.encodeWithSelector(IIdentityRegistryStorage.ERC3643RegistryNotBound.selector, futureRegistry)
        );
        store.unbindIdentityRegistry(futureRegistry);
        vm.expectRevert(abi.encodeWithSelector(IIdentityRegistryStorage.ERC3643InvalidRegistry.selector, address(0)));
        store.bindIdentityRegistry(address(0));
    }

    function test_ThreeHundredRegistryLimitAndRemovalReleasesCapacity() public {
        for (uint256 i = 1; i <= 300; ++i) {
            store.bindIdentityRegistry(address(uint160(i)));
        }
        vm.expectRevert(IIdentityRegistryStorage.ERC3643RegistryLimit.selector);
        store.bindIdentityRegistry(address(301));
        store.unbindIdentityRegistry(address(150));
        store.bindIdentityRegistry(address(301));
        assertEq(store.linkedIdentityRegistries().length, 300);
    }

    function test_OwnerTransferImmediatelyControlsBindings() public {
        OwnableFacet(address(store)).transferOwnership(wallet);
        vm.expectRevert();
        store.bindIdentityRegistry(address(this));
        vm.prank(wallet);
        store.bindIdentityRegistry(address(this));
        vm.prank(wallet);
        store.unbindIdentityRegistry(address(this));
        assertEq(store.linkedIdentityRegistries().length, 0);
    }

    function test_RecordValidationDuplicateMissingAndCountryClearing() public {
        store.bindIdentityRegistry(address(this));
        vm.expectRevert(abi.encodeWithSelector(IIdentityRegistryStorage.ERC3643InvalidInvestor.selector, address(0)));
        store.addIdentityToStorage(address(0), investor, 840);
        vm.expectRevert(abi.encodeWithSelector(IIdentityRegistryStorage.ERC3643InvalidIdentity.selector, address(0)));
        store.addIdentityToStorage(wallet, IERC3643Identity(address(0)), 840);
        vm.expectRevert(abi.encodeWithSelector(IIdentityRegistryStorage.ERC3643InvalidIdentity.selector, wallet));
        store.addIdentityToStorage(wallet, IERC3643Identity(wallet), 840);
        vm.expectRevert(abi.encodeWithSelector(IIdentityRegistryStorage.ERC3643IdentityNotStored.selector, wallet));
        store.removeIdentityFromStorage(wallet);
        vm.expectRevert(abi.encodeWithSelector(IIdentityRegistryStorage.ERC3643IdentityNotStored.selector, wallet));
        store.modifyStoredInvestorCountry(wallet, 840);
        store.addIdentityToStorage(wallet, investor, 840);
        vm.expectRevert(abi.encodeWithSelector(IIdentityRegistryStorage.ERC3643IdentityAlreadyStored.selector, wallet));
        store.addIdentityToStorage(wallet, investor, 826);
        assertEq(store.storedInvestorCountry(wallet), 840);
        store.removeIdentityFromStorage(wallet);
        assertEq(address(store.storedIdentity(wallet)), address(0));
        assertEq(store.storedInvestorCountry(wallet), 0);
        store.addIdentityToStorage(wallet, investor, 826);
        assertEq(store.storedInvestorCountry(wallet), 826);
    }

    function test_UpdateIdentityRequiresCanonicalManagementProofAndPreservesCountry() public {
        store.bindIdentityRegistry(address(this));
        store.addIdentityToStorage(wallet, investor, 840);
        RegistryRawIdentity bad = new RegistryRawIdentity();
        bad.setReply(abi.encode(uint256(2)));
        vm.expectRevert(
            abi.encodeWithSelector(IIdentityRegistryStorage.ERC3643IdentityKeyMissing.selector, address(bad), wallet)
        );
        store.modifyStoredIdentity(wallet, IERC3643Identity(address(bad)));
        bad.setReply(hex"");
        vm.expectRevert();
        store.modifyStoredIdentity(wallet, IERC3643Identity(address(bad)));
        RegistryIdentityMock next = new RegistryIdentityMock();
        next.setManagement(wallet, true);
        store.modifyStoredIdentity(wallet, next);
        assertEq(address(store.storedIdentity(wallet)), address(next));
        assertEq(store.storedInvestorCountry(wallet), 840);
    }
}

contract ERC3643ComplianceTest is ERC3643RegistryTestBase {
    address diamond;
    ICompliance compliance;

    function setUp() public {
        diamond = _deployRegistry(address(0));
        compliance = ICompliance(diamond);
    }

    function test_DefaultComplianceAndInterface() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(ICompliance).interfaceId));
        assertEq(compliance.getTokenBound(), diamond);
        assertTrue(compliance.canTransfer(address(0), address(0), type(uint256).max));
    }

    function test_OwnerBindingSameTokenIdempotenceDifferentTokenAndCounterfactualAddress() public {
        compliance.bindToken(diamond);
        vm.expectRevert(abi.encodeWithSelector(ICompliance.ERC3643TokenAlreadyBound.selector, diamond));
        compliance.bindToken(address(0xA11CE));
        vm.expectRevert(abi.encodeWithSelector(ICompliance.ERC3643TokenNotBound.selector, address(0xBAD)));
        compliance.unbindToken(address(0xBAD));
        compliance.unbindToken(diamond);
        vm.expectRevert(abi.encodeWithSelector(ICompliance.ERC3643InvalidToken.selector, address(0)));
        compliance.bindToken(address(0));
        compliance.bindToken(address(0xF070));
        assertEq(compliance.getTokenBound(), address(0xF070));
        compliance.unbindToken(address(0xF070));
        assertEq(compliance.getTokenBound(), address(0));
    }

    function test_BindingAndUnbindingRemainOwnerOnlyAfterOwnershipTransfer() public {
        address nextOwner = address(0xA11CE);
        vm.prank(nextOwner);
        vm.expectRevert();
        compliance.unbindToken(diamond);
        OwnableFacet(diamond).transferOwnership(nextOwner);
        vm.expectRevert();
        compliance.unbindToken(diamond);
        vm.prank(nextOwner);
        compliance.unbindToken(diamond);
        vm.expectRevert();
        compliance.bindToken(diamond);
        vm.prank(nextOwner);
        compliance.bindToken(diamond);
    }

    function test_PublicLifecycleCallbacksOnlyAcceptCurrentlyBoundToken() public {
        vm.expectRevert(abi.encodeWithSelector(ICompliance.ERC3643UnauthorizedToken.selector, address(this)));
        compliance.transferred(address(1), address(2), 3);
        vm.expectRevert();
        compliance.created(address(2), 3);
        vm.expectRevert();
        compliance.destroyed(address(1), 3);
        RegistryCallbackCaller caller = new RegistryCallbackCaller();
        compliance.unbindToken(diamond);
        compliance.bindToken(address(caller));
        caller.notify(diamond);
        compliance.unbindToken(address(caller));
        vm.expectRevert(abi.encodeWithSelector(ICompliance.ERC3643UnauthorizedToken.selector, address(caller)));
        caller.notify(diamond);
        compliance.bindToken(address(caller));
        caller.notify(diamond);
    }

    function test_LocalInternalCallbacksRequireLocalBindingAndShareExecutionGuard() public {
        RegistryExecutionProbe(diamond).localCallbacks();
        bytes memory input = abi.encodeCall(ICompliance.created, (address(2), 3));
        (bool ok, bytes memory result) = RegistryExecutionProbe(diamond).attempt(input);
        assertFalse(ok);
        assertEq(result, abi.encodeWithSelector(ERC3643ExecutionInProgress.selector));
        compliance.unbindToken(diamond);
        vm.expectRevert(abi.encodeWithSelector(ICompliance.ERC3643TokenNotBound.selector, diamond));
        RegistryExecutionProbe(diamond).localCallbacks();
        compliance.bindToken(diamond);
        RegistryExecutionProbe(diamond).localCallbacks();
    }
}

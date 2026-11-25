// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {ENSSubnameIssuerV2TestBase} from "@lattice-test/base/ENSSubnameIssuerV2TestBase.sol";
import {MultiInitErrors} from "@lattice-test/helpers/MultiInitErrors.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {ENS_MANAGER_ROLE} from "@lattice/ens/libraries/ENSResolverLib.sol";
import {ENS_SUBNAME_ISSUER_ROLE} from "@lattice/ens/libraries/ENSSubnameIssuerLib.sol";
import {ENS_V2_SUBNAME_ISSUER_ROLE} from "@lattice/ens/libraries/ENSSubnameIssuerV2Lib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IENSSubnameIssuerV2} from "@lattice/interfaces/ens/IENSSubnameIssuerV2.sol";
import {IPermissionedRegistry} from "@lattice/interfaces/external/ens/IPermissionedRegistry.sol";
import {IUniversalHelper} from "@lattice/interfaces/external/ens/IUniversalHelper.sol";
import {IERC1155Receiver} from "@lattice/interfaces/tokens/IERC1155.sol";

contract MockENSV2IssuerHelper is IUniversalHelper {
    address public immutable ROOT_REGISTRY;
    mapping(bytes => address) private _canonicalRegistries;

    constructor(address root) {
        ROOT_REGISTRY = root;
    }

    function setCanonicalRegistry(bytes calldata parent, address registry) external {
        _canonicalRegistries[parent] = registry;
    }

    function findCanonicalRegistry(bytes calldata parent) external view returns (address) {
        return _canonicalRegistries[parent];
    }
}

contract MockENSV2IssuerRegistry is IPermissionedRegistry {
    error NoRegistrarGrant(address caller);
    error LabelRegistered();
    error LabelReserved();
    error UnsafeRecipient();

    struct State {
        uint256 tokenId;
        address owner;
        address childRegistry;
        address resolver;
        uint256 roles;
        uint64 expiry;
    }

    mapping(address => bool) private _registrars;
    mapping(string => State) private _states;
    uint256 public lastTokenId;

    function setRegistrar(address account, bool enabled) external {
        _registrars[account] = enabled;
    }

    function reserve(string calldata label, uint64 expiry) external {
        _states[label].expiry = expiry;
    }

    function getState(string calldata label) external view returns (State memory) {
        return _states[label];
    }

    function updateRoles(string calldata label, uint256 roles) external {
        State storage state = _states[label];
        require(msg.sender == state.owner);
        state.roles = roles;
        state.tokenId = ++lastTokenId;
    }

    function register(
        string calldata label,
        address owner,
        address registry,
        address resolver,
        uint256 roles,
        uint64 expiry
    ) external returns (uint256 tokenId) {
        if (!_registrars[msg.sender]) revert NoRegistrarGrant(msg.sender);
        State storage previous = _states[label];
        if (previous.expiry > block.timestamp) {
            if (previous.owner == address(0)) revert LabelReserved();
            revert LabelRegistered();
        }

        tokenId = ++lastTokenId;
        _states[label] = State(tokenId, owner, registry, resolver, roles, expiry);
        if (owner.code.length != 0) {
            bytes4 accepted = IERC1155Receiver(owner).onERC1155Received(msg.sender, address(0), tokenId, 1, "");
            if (accepted != IERC1155Receiver.onERC1155Received.selector) revert UnsafeRecipient();
        }
    }
}

contract MockENSV2IssuerRecipient {
    bool private immutable _accept;

    constructor(bool accept) {
        _accept = accept;
    }

    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external view returns (bytes4) {
        return _accept ? IERC1155Receiver.onERC1155Received.selector : bytes4(0);
    }
}

contract ENSSubnameIssuerV2Test is ENSSubnameIssuerV2TestBase {
    address private constant ADMIN = address(0xA1);
    address private constant ISSUER = address(0xB2);
    address private constant MANAGER = address(0xC3);
    address private constant LEGACY_ISSUER = address(0xD4);
    address private constant OWNER = address(0xD00D);
    address private constant RESOLVER = address(0xE11E);

    bytes private constant PARENT = hex"076d7970726f746f0365746800";
    bytes private constant SECOND_PARENT = hex"056f746865720365746800";
    string private constant LABEL = "treasury";
    uint256 private constant OWNER_ROLES = (1 << 20) | (1 << 24);
    uint64 private constant EXPIRY = 10_000;

    MockENSV2IssuerHelper private helper;
    MockENSV2IssuerRegistry private parent;

    function setUp() public {
        vm.warp(100);
        parent = new MockENSV2IssuerRegistry();
        helper = new MockENSV2IssuerHelper(address(new MockENSV2IssuerRegistry()));
        helper.setCanonicalRegistry(PARENT, address(parent));
        _deployENSSubnameIssuerV2(ADMIN, address(helper));
        parent.setRegistrar(diamond, true);
        vm.startPrank(ADMIN);
        IAccessControl(diamond).grantRole(ENS_V2_SUBNAME_ISSUER_ROLE, ISSUER);
        IAccessControl(diamond).grantRole(ENS_MANAGER_ROLE, MANAGER);
        IAccessControl(diamond).grantRole(ENS_SUBNAME_ISSUER_ROLE, LEGACY_ISSUER);
        vm.stopPrank();
    }

    function test_IssuePreservesNativeRolesExpiryResolverAndChildRegistry() public {
        address child = address(new MockENSV2IssuerRegistry());
        vm.expectEmit(true, true, true, true, diamond);
        emit IENSSubnameIssuerV2.EnsSubnameIssuedV2(address(parent), 1, OWNER, LABEL);

        vm.prank(ISSUER);
        uint256 tokenId = subnameIssuer.issueEnsSubnameV2(PARENT, LABEL, OWNER, child, RESOLVER, OWNER_ROLES, EXPIRY);

        MockENSV2IssuerRegistry.State memory state = parent.getState(LABEL);
        assertEq(tokenId, state.tokenId);
        assertEq(state.owner, OWNER);
        assertEq(state.childRegistry, child);
        assertEq(state.resolver, RESOLVER);
        assertEq(state.roles, OWNER_ROLES);
        assertEq(state.expiry, EXPIRY);
    }

    function test_IssuerCanUseASecondCanonicalParentWithItsOwnGrant() public {
        MockENSV2IssuerRegistry second = new MockENSV2IssuerRegistry();
        helper.setCanonicalRegistry(SECOND_PARENT, address(second));
        second.setRegistrar(diamond, true);

        vm.prank(ISSUER);
        subnameIssuer.issueEnsSubnameV2(SECOND_PARENT, LABEL, OWNER, address(0), RESOLVER, OWNER_ROLES, EXPIRY);
        assertEq(second.getState(LABEL).owner, OWNER);
        assertEq(parent.getState(LABEL).owner, address(0));
    }

    function test_MissingFacetOnlyAndRevokedRegistryGrantsCannotMint() public {
        address facet = _facet();
        parent.setRegistrar(diamond, false);
        _expectGrantFailure();

        parent.setRegistrar(facet, true);
        _expectGrantFailure();

        parent.setRegistrar(diamond, true);
        _issue(OWNER);
        parent.setRegistrar(diamond, false);
        vm.expectRevert(abi.encodeWithSelector(MockENSV2IssuerRegistry.NoRegistrarGrant.selector, diamond));
        vm.prank(ISSUER);
        subnameIssuer.issueEnsSubnameV2(PARENT, "other", OWNER, address(0), RESOLVER, OWNER_ROLES, EXPIRY);
        assertEq(parent.getState("other").owner, address(0));
        assertEq(parent.getState(LABEL).owner, OWNER);
    }

    function test_V1IssuerAndManagerDoNotInheritIssuingPermission() public {
        address[2] memory unauthorized = [LEGACY_ISSUER, MANAGER];
        for (uint256 i; i < unauthorized.length; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccessControl.AccessControlUnauthorizedAccount.selector,
                    unauthorized[i],
                    ENS_V2_SUBNAME_ISSUER_ROLE
                )
            );
            vm.prank(unauthorized[i]);
            subnameIssuer.issueEnsSubnameV2(PARENT, LABEL, OWNER, address(0), RESOLVER, OWNER_ROLES, EXPIRY);
        }
    }

    function test_UnattachedAliasAndCodelessParentsCannotMint() public {
        _expectInvalidParent(SECOND_PARENT, address(0));
        _expectInvalidParent(hex"05616c6961730365746800", address(0));
        helper.setCanonicalRegistry(SECOND_PARENT, RESOLVER);
        _expectInvalidParent(SECOND_PARENT, RESOLVER);
        assertEq(parent.lastTokenId(), 0);
    }

    function test_RejectsEmptyAndRootParents() public {
        vm.startPrank(ISSUER);
        vm.expectRevert(IENSSubnameIssuerV2.ENSSubnameIssuerV2InvalidParentName.selector);
        subnameIssuer.issueEnsSubnameV2("", LABEL, OWNER, address(0), RESOLVER, OWNER_ROLES, EXPIRY);
        vm.expectRevert(IENSSubnameIssuerV2.ENSSubnameIssuerV2InvalidParentName.selector);
        subnameIssuer.issueEnsSubnameV2(hex"00", LABEL, OWNER, address(0), RESOLVER, OWNER_ROLES, EXPIRY);
        vm.stopPrank();
    }

    function test_RejectsInvalidLabels() public {
        string[4] memory labels = [string(""), "split.label", "with\x00null", string(new bytes(256))];
        vm.startPrank(ISSUER);
        for (uint256 i; i < labels.length; ++i) {
            vm.expectRevert(IENSSubnameIssuerV2.ENSSubnameIssuerV2InvalidLabel.selector);
            subnameIssuer.issueEnsSubnameV2(PARENT, labels[i], OWNER, address(0), RESOLVER, OWNER_ROLES, EXPIRY);
        }
        vm.stopPrank();
    }

    function test_AcceptsUpstreamMaximumLabelLength() public {
        bytes memory label = new bytes(255);
        for (uint256 i; i < label.length; ++i) {
            label[i] = "a";
        }
        vm.prank(ISSUER);
        uint256 tokenId =
            subnameIssuer.issueEnsSubnameV2(PARENT, string(label), OWNER, address(0), RESOLVER, OWNER_ROLES, EXPIRY);
        assertEq(parent.getState(string(label)).tokenId, tokenId);
    }

    function test_RejectsZeroOwnerAndNonfutureExpiry() public {
        vm.expectRevert(IENSSubnameIssuerV2.ENSSubnameIssuerV2InvalidOwner.selector);
        _issue(address(0));

        vm.startPrank(ISSUER);
        for (uint64 expiry = 99; expiry <= 100; ++expiry) {
            vm.expectRevert(
                abi.encodeWithSelector(IENSSubnameIssuerV2.ENSSubnameIssuerV2InvalidExpiry.selector, expiry)
            );
            subnameIssuer.issueEnsSubnameV2(PARENT, LABEL, OWNER, address(0), RESOLVER, OWNER_ROLES, expiry);
        }
        vm.stopPrank();
    }

    function test_DuplicateAndReservedRevertsPreserveRecords() public {
        uint256 tokenId = _issue(OWNER);
        vm.expectRevert(MockENSV2IssuerRegistry.LabelRegistered.selector);
        _issue(MANAGER);
        assertEq(parent.getState(LABEL).tokenId, tokenId);
        assertEq(parent.getState(LABEL).owner, OWNER);
        assertEq(parent.getState(LABEL).resolver, RESOLVER);

        parent.reserve("reserved", EXPIRY);
        vm.expectRevert(MockENSV2IssuerRegistry.LabelReserved.selector);
        vm.prank(ISSUER);
        subnameIssuer.issueEnsSubnameV2(PARENT, "reserved", OWNER, address(0), RESOLVER, OWNER_ROLES, EXPIRY);
        MockENSV2IssuerRegistry.State memory state = parent.getState("reserved");
        assertEq(state.owner, address(0));
        assertEq(state.expiry, EXPIRY);
    }

    function test_ERC1155RejectionRollsBackBeforeSuccessfulDelivery() public {
        MockENSV2IssuerRecipient rejecting = new MockENSV2IssuerRecipient(false);
        vm.expectRevert(MockENSV2IssuerRegistry.UnsafeRecipient.selector);
        _issue(address(rejecting));
        assertEq(parent.getState(LABEL).owner, address(0));
        assertEq(parent.getState(LABEL).expiry, 0);
        assertEq(parent.getState(LABEL).resolver, address(0));
        assertEq(parent.lastTokenId(), 0);

        MockENSV2IssuerRecipient accepting = new MockENSV2IssuerRecipient(true);
        uint256 tokenId = _issue(address(accepting));
        assertEq(parent.getState(LABEL).tokenId, tokenId);
        assertEq(parent.getState(LABEL).owner, address(accepting));
    }

    function test_ReissueAfterRoleChangeAndExpiryReturnsNewRegistryTokenId() public {
        uint256 first = _issue(OWNER);
        vm.prank(OWNER);
        parent.updateRoles(LABEL, 0);
        assertNotEq(parent.getState(LABEL).tokenId, first);
        assertEq(parent.getState(LABEL).roles, 0);

        vm.warp(EXPIRY);
        vm.prank(ISSUER);
        uint256 second =
            subnameIssuer.issueEnsSubnameV2(PARENT, LABEL, MANAGER, address(0), RESOLVER, OWNER_ROLES, EXPIRY + 1);
        assertNotEq(second, first);
        assertEq(parent.getState(LABEL).tokenId, second);
        assertEq(parent.getState(LABEL).owner, MANAGER);
        assertEq(parent.getState(LABEL).roles, OWNER_ROLES);
    }

    function test_ManagerRotatesHelperAndIssuerCannot() public {
        MockENSV2IssuerHelper replacement = new MockENSV2IssuerHelper(address(parent));
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, ISSUER, ENS_MANAGER_ROLE)
        );
        vm.prank(ISSUER);
        subnameIssuer.setEnsUniversalHelper(address(replacement));

        vm.expectEmit(true, false, false, false, diamond);
        emit IENSSubnameIssuerV2.EnsUniversalHelperSet(address(replacement));
        vm.prank(MANAGER);
        subnameIssuer.setEnsUniversalHelper(address(replacement));
        assertEq(subnameIssuer.ensUniversalHelper(), address(replacement));
    }

    function test_RejectsInvalidHelperAndKeepsCurrentConfiguration() public {
        address withoutRootCode = address(new MockENSV2IssuerHelper(OWNER));
        address[3] memory invalidHelpers = [OWNER, address(parent), withoutRootCode];
        vm.startPrank(MANAGER);
        for (uint256 i; i < invalidHelpers.length; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(IENSSubnameIssuerV2.ENSSubnameIssuerV2InvalidHelper.selector, invalidHelpers[i])
            );
            subnameIssuer.setEnsUniversalHelper(invalidHelpers[i]);
        }
        vm.stopPrank();
        assertEq(subnameIssuer.ensUniversalHelper(), address(helper));
    }

    function test_InvalidHelperRevertsDuringInitialization() public {
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(ADMIN, OWNER);
        Lattice d = new Lattice();
        vm.expectRevert(
            MultiInitErrors.at(
                0,
                initCalldata,
                abi.encodeWithSelector(IENSSubnameIssuerV2.ENSSubnameIssuerV2InvalidHelper.selector, OWNER)
            )
        );
        d.initialize(cuts, init, initCalldata);
    }

    function test_SupportsInterfaceThroughDiamond() public view {
        assertEq(type(IENSSubnameIssuerV2).interfaceId, bytes4(0x5db4438d));
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IENSSubnameIssuerV2).interfaceId));
    }

    function _issue(address owner) private returns (uint256) {
        vm.prank(ISSUER);
        return subnameIssuer.issueEnsSubnameV2(PARENT, LABEL, owner, address(0), RESOLVER, OWNER_ROLES, EXPIRY);
    }

    function _expectGrantFailure() private {
        vm.expectRevert(abi.encodeWithSelector(MockENSV2IssuerRegistry.NoRegistrarGrant.selector, diamond));
        _issue(OWNER);
        assertEq(parent.getState(LABEL).owner, address(0));
    }

    function _expectInvalidParent(bytes memory parentName, address result) private {
        vm.expectRevert(
            abi.encodeWithSelector(IENSSubnameIssuerV2.ENSSubnameIssuerV2InvalidParentRegistry.selector, result)
        );
        vm.prank(ISSUER);
        subnameIssuer.issueEnsSubnameV2(parentName, LABEL, OWNER, address(0), RESOLVER, OWNER_ROLES, EXPIRY);
    }

    function _facet() private view returns (address) {
        return IDiamondLoupe(diamond).facetAddress(IENSSubnameIssuerV2.issueEnsSubnameV2.selector);
    }
}

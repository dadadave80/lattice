// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {ENSSubnameIssuerTestBase} from "@lattice-test/base/ENSSubnameIssuerTestBase.sol";
import {ENSSubnameIssuer} from "@lattice/ens/ENSSubnameIssuer.sol";
import {ENS_SUBNAME_ISSUER_ROLE} from "@lattice/ens/libraries/ENSSubnameIssuerLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IENSSubnameIssuer} from "@lattice/interfaces/ens/IENSSubnameIssuer.sol";
import {INameWrapper} from "@lattice/interfaces/external/INameWrapper.sol";

/// @title MockNameWrapper
/// @notice Minimal ENS NameWrapper that records the last setSubnodeRecord call and returns the node. Kept as a test
///         fixture (external contract the facet forwards to — NOT the facet under test).
contract MockNameWrapper is INameWrapper {
    bytes32 public lastParentNode;
    string public lastLabel;
    address public lastOwner;
    address public lastResolver;
    uint64 public lastTtl;
    uint32 public lastFuses;
    uint64 public lastExpiry;

    function setSubnodeRecord(
        bytes32 parentNode,
        string calldata label,
        address owner,
        address resolver,
        uint64 ttl,
        uint32 fuses,
        uint64 expiry
    ) external returns (bytes32 node) {
        node = keccak256(abi.encodePacked(parentNode, keccak256(bytes(label))));
        lastParentNode = parentNode;
        lastLabel = label;
        lastOwner = owner;
        lastResolver = resolver;
        lastTtl = ttl;
        lastFuses = fuses;
        lastExpiry = expiry;
    }
}

/// @title ENSSubnameIssuerTest
/// @notice Exercises the ENS subname-issuer facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployENSSubnameIssuer} script (see {ENSSubnameIssuerTestBase}) — `issueSubname` forwards
///         `setSubnodeRecord` through the diamond's `delegatecall` dispatch, not a flattened inheritance mock.
///         Role gating is enforced by the cut-in `AccessControl` facet; `supportsInterface` by the cut-in
///         `ERC165Facet`. The external `MockNameWrapper` stays a test fixture (it is NOT the facet under test).
contract ENSSubnameIssuerTest is ENSSubnameIssuerTestBase {
    MockNameWrapper nameWrapper;

    address admin = address(0xA1);
    address issuer = address(0xB2);
    address stranger = address(0xC3);
    address childOwner = address(0xD00D);
    address resolver = address(0xE11E);

    bytes32 constant PARENT = keccak256("myproto.eth");
    string constant LABEL = "treasury";

    event SubnameIssued(bytes32 indexed parentNode, bytes32 indexed node, address indexed owner);
    event NameWrapperSet(address indexed nameWrapper);

    function setUp() public {
        nameWrapper = new MockNameWrapper();
        diamond = _deployENSSubnameIssuer(admin, address(nameWrapper));
        subnameIssuer = ENSSubnameIssuer(diamond);
        vm.prank(admin);
        IAccessControl(diamond).grantRole(ENS_SUBNAME_ISSUER_ROLE, issuer);
    }

    function _expectedNode() internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(PARENT, keccak256(bytes(LABEL))));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              issueSubname
    //////////////////////////////////////////////////////////////////////////*//

    function test_IssueSubnameForwardsAndReturnsNode() public {
        vm.prank(issuer);
        bytes32 node = subnameIssuer.issueSubname(PARENT, LABEL, childOwner, resolver, 0, 0, 0);

        assertEq(node, _expectedNode());
        assertEq(nameWrapper.lastParentNode(), PARENT);
        assertEq(nameWrapper.lastLabel(), LABEL);
        assertEq(nameWrapper.lastOwner(), childOwner);
        assertEq(nameWrapper.lastResolver(), resolver);
    }

    function test_IssueSubnamePassesFusesAndExpiry() public {
        vm.prank(issuer);
        subnameIssuer.issueSubname(PARENT, LABEL, childOwner, resolver, 3600, 0x10000, 99999);
        assertEq(nameWrapper.lastTtl(), 3600);
        assertEq(uint256(nameWrapper.lastFuses()), 0x10000);
        assertEq(uint256(nameWrapper.lastExpiry()), 99999);
    }

    function test_IssueSubnameEmits() public {
        vm.expectEmit(true, true, true, false, address(subnameIssuer));
        emit SubnameIssued(PARENT, _expectedNode(), childOwner);
        vm.prank(issuer);
        subnameIssuer.issueSubname(PARENT, LABEL, childOwner, resolver, 0, 0, 0);
    }

    function test_IssueSubnameUnauthorizedReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, ENS_SUBNAME_ISSUER_ROLE
            )
        );
        vm.prank(stranger);
        subnameIssuer.issueSubname(PARENT, LABEL, childOwner, resolver, 0, 0, 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              configuration
    //////////////////////////////////////////////////////////////////////////*//

    function test_NameWrapperConfiguredAtInit() public view {
        assertEq(subnameIssuer.nameWrapper(), address(nameWrapper));
    }

    function test_SetNameWrapperByIssuer() public {
        MockNameWrapper nw2 = new MockNameWrapper();
        vm.expectEmit(true, false, false, false, address(subnameIssuer));
        emit NameWrapperSet(address(nw2));
        vm.prank(issuer);
        subnameIssuer.setNameWrapper(address(nw2));
        assertEq(subnameIssuer.nameWrapper(), address(nw2));
    }

    function test_SetNameWrapperZeroReverts() public {
        vm.expectRevert(IENSSubnameIssuer.ENSSubnameIssuerZeroNameWrapper.selector);
        vm.prank(issuer);
        subnameIssuer.setNameWrapper(address(0));
    }

    function test_SetNameWrapperUnauthorizedReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, ENS_SUBNAME_ISSUER_ROLE
            )
        );
        vm.prank(stranger);
        subnameIssuer.setNameWrapper(address(nameWrapper));
    }

    function test_InitZeroNameWrapperReverts() public {
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin, address(0));
        Diamond d = new Diamond();
        vm.expectRevert(IENSSubnameIssuer.ENSSubnameIssuerZeroNameWrapper.selector);
        d.initialize(cuts, init, initCalldata);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                ERC-165
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsIENSSubnameIssuer() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IENSSubnameIssuer).interfaceId));
    }

    function test_InterfaceIdMatchesConstant() public pure {
        assertEq(type(IENSSubnameIssuer).interfaceId, bytes4(0x6ead39e3), "IENSSubnameIssuer interfaceId moved");
    }
}

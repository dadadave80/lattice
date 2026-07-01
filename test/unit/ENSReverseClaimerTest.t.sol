// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {ENSReverseClaimerTestBase} from "@lattice-test/base/ENSReverseClaimerTestBase.sol";
import {ENSReverseClaimer} from "@lattice/ens/ENSReverseClaimer.sol";
import {ENS_MANAGER_ROLE} from "@lattice/ens/libraries/ENSReverseClaimerLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IENSReverseClaimer} from "@lattice/interfaces/ens/IENSReverseClaimer.sol";
import {IReverseRegistrar} from "@lattice/interfaces/external/IReverseRegistrar.sol";

/// @title MockReverseRegistrar
/// @notice Minimal ENS reverse registrar that records the name each caller sets for itself. Kept as a test fixture
///         (external contract the facet forwards to — NOT the facet under test).
contract MockReverseRegistrar is IReverseRegistrar {
    mapping(address caller => string name) public nameOf;

    function setName(string memory name) external {
        nameOf[msg.sender] = name;
    }
}

/// @title MockL1ReverseRegistrar
/// @notice ENS L1-style registrar whose `setName` returns `bytes32` (unlike the L2 registrar, which
///         returns nothing). Used to prove the facet's void-typed call works against BOTH ABIs.
contract MockL1ReverseRegistrar {
    mapping(address caller => string name) public nameOf;

    function setName(string memory name) external returns (bytes32) {
        nameOf[msg.sender] = name;
        return keccak256(abi.encodePacked("addr.reverse", msg.sender));
    }
}

/// @title ENSReverseClaimerTest
/// @notice Exercises the ENS reverse-claim facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployENSReverseClaimer} script (see {ENSReverseClaimerTestBase}) — `setEnsName` forwards `setName` to
///         the registrar AS the diamond (msg.sender == diamond) through the `delegatecall` dispatch, not a
///         flattened inheritance mock. Role gating is enforced by the cut-in `AccessControl` facet;
///         `supportsInterface` by the cut-in `ERC165Facet`. The external registrar mocks stay test fixtures (they
///         are NOT the facet under test).
contract ENSReverseClaimerTest is ENSReverseClaimerTestBase {
    MockReverseRegistrar registrar;

    address admin = address(0xA1);
    address manager = address(0xB2);
    address stranger = address(0xC3);

    string constant ENS_NAME = "treasury.myproto.eth";

    event EnsNameSet(string name);
    event ReverseRegistrarSet(address indexed reverseRegistrar);

    function setUp() public {
        registrar = new MockReverseRegistrar();
        diamond = _deployENSReverseClaimer(admin, address(registrar));
        claimer = ENSReverseClaimer(diamond);
        vm.prank(admin);
        IAccessControl(diamond).grantRole(ENS_MANAGER_ROLE, manager);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 setEnsName
    //////////////////////////////////////////////////////////////////////////*//

    function test_SetEnsNameForwardsToRegistrarAsDiamond() public {
        vm.prank(manager);
        claimer.setEnsName(ENS_NAME);
        // The diamond called setName as msg.sender, so the registrar records the name under the
        // diamond's own address — i.e. the diamond's reverse record resolves to ENS_NAME.
        assertEq(registrar.nameOf(address(claimer)), ENS_NAME);
        assertEq(claimer.ensName(), ENS_NAME);
    }

    function test_SetEnsNameEmits() public {
        vm.expectEmit(false, false, false, true, address(claimer));
        emit EnsNameSet(ENS_NAME);
        vm.prank(manager);
        claimer.setEnsName(ENS_NAME);
    }

    function test_SetEnsNameUnauthorizedReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, ENS_MANAGER_ROLE)
        );
        vm.prank(stranger);
        claimer.setEnsName(ENS_NAME);
    }

    function test_EnsNameUnsetIsEmpty() public view {
        assertEq(claimer.ensName(), "");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            setReverseRegistrar
    //////////////////////////////////////////////////////////////////////////*//

    function test_ReverseRegistrarConfiguredAtInit() public view {
        assertEq(claimer.reverseRegistrar(), address(registrar));
    }

    function test_SetReverseRegistrarRotatesAndRetargets() public {
        MockReverseRegistrar reg2 = new MockReverseRegistrar();

        vm.expectEmit(true, false, false, false, address(claimer));
        emit ReverseRegistrarSet(address(reg2));
        vm.prank(manager);
        claimer.setReverseRegistrar(address(reg2));
        assertEq(claimer.reverseRegistrar(), address(reg2));

        // A subsequent claim must go to the newly configured registrar.
        vm.prank(manager);
        claimer.setEnsName(ENS_NAME);
        assertEq(reg2.nameOf(address(claimer)), ENS_NAME);
    }

    function test_SetEnsNameWorksAgainstBytes32ReturningRegistrar() public {
        // L1 ReverseRegistrar.setName returns bytes32; the facet's void-typed call must ignore it and
        // not revert (the L2 registrar returns nothing — covered by the default void mock).
        MockL1ReverseRegistrar l1 = new MockL1ReverseRegistrar();
        vm.prank(manager);
        claimer.setReverseRegistrar(address(l1));
        vm.prank(manager);
        claimer.setEnsName(ENS_NAME);
        assertEq(l1.nameOf(address(claimer)), ENS_NAME);
        assertEq(claimer.ensName(), ENS_NAME);
    }

    function test_SetReverseRegistrarZeroReverts() public {
        vm.expectRevert(IENSReverseClaimer.ENSReverseClaimerZeroRegistrar.selector);
        vm.prank(manager);
        claimer.setReverseRegistrar(address(0));
    }

    function test_SetReverseRegistrarUnauthorizedReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, ENS_MANAGER_ROLE)
        );
        vm.prank(stranger);
        claimer.setReverseRegistrar(address(registrar));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              init + ERC-165
    //////////////////////////////////////////////////////////////////////////*//

    function test_InitZeroRegistrarReverts() public {
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin, address(0));
        Diamond d = new Diamond();
        vm.expectRevert(IENSReverseClaimer.ENSReverseClaimerZeroRegistrar.selector);
        d.initialize(cuts, init, initCalldata);
    }

    function test_SupportsIENSReverseClaimer() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IENSReverseClaimer).interfaceId));
    }

    function test_InterfaceIdMatchesConstant() public pure {
        assertEq(type(IENSReverseClaimer).interfaceId, bytes4(0x84019dd8), "IENSReverseClaimer interfaceId moved");
    }
}

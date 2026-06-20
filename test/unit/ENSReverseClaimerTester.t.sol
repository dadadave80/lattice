// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ENSReverseClaimer} from "@lattice/ens/ENSReverseClaimer.sol";
import {ENSReverseClaimerLib, ENS_MANAGER_ROLE} from "@lattice/ens/libraries/ENSReverseClaimerLib.sol";
import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";
import {IENSReverseClaimer} from "@lattice/interfaces/IENSReverseClaimer.sol";
import {IReverseRegistrar} from "@lattice/interfaces/external/IReverseRegistrar.sol";
import {Test} from "forge-std/Test.sol";

/// @title MockReverseRegistrar
/// @notice Minimal ENS reverse registrar that records the name each caller sets for itself.
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

/// @title MockENSReverseClaimerContract
/// @notice Wrapper that inherits the ENSReverseClaimer facet and wires AccessControl + init.
contract MockENSReverseClaimerContract is ENSReverseClaimer {
    function initialize(address admin, address registrar) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(admin);
        ENSReverseClaimerLib.__ENSReverseClaimer_init(registrar);
        InitializableLib.postInitializer(s);
    }

    function grantRole(bytes32 role, address account) external {
        AccessControlLib.grantRole(role, account);
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

/// @title ENSReverseClaimerTester
/// @notice Unit tests for the ENS reverse-claim facet.
contract ENSReverseClaimerTester is Test {
    MockENSReverseClaimerContract claimer;
    MockReverseRegistrar registrar;

    address admin = address(0xA1);
    address manager = address(0xB2);
    address stranger = address(0xC3);

    string constant ENS_NAME = "treasury.myproto.eth";

    event EnsNameSet(string name);
    event ReverseRegistrarSet(address indexed reverseRegistrar);

    function setUp() public {
        registrar = new MockReverseRegistrar();
        claimer = new MockENSReverseClaimerContract();
        claimer.initialize(admin, address(registrar));
        vm.prank(admin);
        claimer.grantRole(ENS_MANAGER_ROLE, manager);
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
        MockENSReverseClaimerContract c = new MockENSReverseClaimerContract();
        vm.expectRevert(IENSReverseClaimer.ENSReverseClaimerZeroRegistrar.selector);
        c.initialize(admin, address(0));
    }

    function test_SupportsIENSReverseClaimer() public view {
        assertTrue(claimer.supportsInterface(type(IENSReverseClaimer).interfaceId));
    }

    function test_InterfaceIdMatchesConstant() public pure {
        assertEq(type(IENSReverseClaimer).interfaceId, bytes4(0x84019dd8), "IENSReverseClaimer interfaceId moved");
    }
}

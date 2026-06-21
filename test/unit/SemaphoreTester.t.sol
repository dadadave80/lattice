// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {ISemaphore} from "@lattice/interfaces/ISemaphore.sol";
import {Semaphore} from "@lattice/privacy/Semaphore.sol";
import {SemaphoreLib} from "@lattice/privacy/libraries/SemaphoreLib.sol";
import {SemaphoreVerifier} from "@semaphore/SemaphoreVerifier.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Harness exposing init + ERC-165 discovery for the Semaphore facet.
contract MockSemaphoreContract is Semaphore {
    function initialize(address verifier_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        AccessControlLib.__AccessControl_init(msg.sender);
        SemaphoreLib.__Semaphore_init(verifier_);
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

/// @title SemaphoreTester
/// @notice Tests the Semaphore membership/signaling facet against a REAL Semaphore v4 proof generated
///         off-chain with the semaphore-protocol packages (3 members, depth 2, message 42, scope 7) that
///         passes Semaphore's own proof verification. See test/fixtures/semaphore.
contract SemaphoreTester is Test {
    uint256 constant ROOT = 5504274371000021352836406185992230687759203853005470845011606913465462220001;

    MockSemaphoreContract s;

    address bob = address(0xB0B);

    function setUp() public {
        SemaphoreVerifier ver = new SemaphoreVerifier();
        s = new MockSemaphoreContract();
        s.initialize(address(ver));
    }

    function _commitments() internal pure returns (uint256[] memory c) {
        c = new uint256[](3);
        c[0] = 17949992577497164382864432164243702268920029987038590152616928858552957999582;
        c[1] = 4249399685134541224162435585301087150767153586340041298231151767920676646338;
        c[2] = 13437183960962146794866378975828372296062966514344951918805485185578865539414;
    }

    function _proof() internal pure returns (ISemaphore.SemaphoreProof memory p) {
        p.merkleTreeDepth = 2;
        p.merkleTreeRoot = ROOT;
        p.nullifier = 21552595372099034156339245889868090636531801712661785302440645643285791428071;
        p.message = 42;
        p.scope = 7;
        p.points[0] = 2310998922429931557627261666497574760272300626413517203631246217123999772441;
        p.points[1] = 21190114837064209911022848968053933667974666779267520653022499676495177202729;
        p.points[2] = 12256851427213069888795528365249461208698039434556553962345112716225727331719;
        p.points[3] = 1583347636129575038621432220725258156077029837575052652782774719585457550450;
        p.points[4] = 21522717901265613016597011137435065155486311594747768280110546382673748732113;
        p.points[5] = 5980365365218607493280642502625378877138339885283754567518603507027677763976;
        p.points[6] = 7096447544782757323392261558738625653784137985680307502707397728104034971084;
        p.points[7] = 13074336683986268969597064344784755121212035399500021564522910255223254967537;
    }

    function _groupWithMembers() internal returns (uint256 groupId) {
        groupId = s.createGroup();
        s.addMembers(groupId, _commitments());
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_AddMembersMatchesProofRoot() public {
        uint256 groupId = _groupWithMembers();
        // The on-chain Poseidon LeanIMT root must equal the off-chain Semaphore group root.
        assertEq(s.getMerkleTreeRoot(groupId), ROOT);
        assertEq(s.getMerkleTreeSize(groupId), 3);
        assertTrue(s.hasMember(groupId, _commitments()[0]));
    }

    function test_VerifyProofReturnsTrue() public {
        uint256 groupId = _groupWithMembers();
        assertTrue(s.verifyProof(groupId, _proof()));
    }

    function test_ValidateRealProof() public {
        uint256 groupId = _groupWithMembers();
        s.validateProof(groupId, _proof());
        // nullifier is now consumed: a replay must revert (covered by the next test).
    }

    function test_ReplayRevertsNullifier() public {
        uint256 groupId = _groupWithMembers();
        s.validateProof(groupId, _proof());
        vm.expectRevert(ISemaphore.SemaphoreNullifierAlreadyUsed.selector);
        s.validateProof(groupId, _proof());
    }

    function test_RejectWrongRoot() public {
        uint256 groupId = _groupWithMembers();
        ISemaphore.SemaphoreProof memory p = _proof();
        p.merkleTreeRoot = ROOT + 1; // not a known root of the group
        vm.expectRevert(ISemaphore.SemaphoreMerkleTreeRootNotInGroup.selector);
        s.verifyProof(groupId, p);
    }

    function test_RejectUnsupportedDepth() public {
        uint256 groupId = _groupWithMembers();
        ISemaphore.SemaphoreProof memory p = _proof();
        p.merkleTreeDepth = 33; // > MAX_DEPTH
        vm.expectRevert(ISemaphore.SemaphoreMerkleTreeDepthUnsupported.selector);
        s.verifyProof(groupId, p);
    }

    function test_ValidateUnknownGroupReverts() public {
        vm.expectRevert(ISemaphore.SemaphoreGroupDoesNotExist.selector);
        s.verifyProof(99, _proof());
    }

    function test_OnlyAdminAddsMember() public {
        uint256 groupId = s.createGroup(); // admin = address(this)
        vm.prank(bob);
        vm.expectRevert(ISemaphore.SemaphoreCallerIsNotGroupAdmin.selector);
        s.addMember(groupId, _commitments()[0]);
    }

    function test_GroupBookkeeping() public {
        assertEq(s.groupCount(), 0);
        uint256 g0 = s.createGroup(bob);
        assertEq(g0, 0);
        assertEq(s.groupCount(), 1);
        assertEq(s.groupAdmin(g0), bob);
    }

    function test_SetVerifierOnlyAdmin() public {
        // The test contract is the default admin (set at init); bob is not.
        vm.prank(bob);
        vm.expectRevert();
        s.setVerifier(address(0xDEAD));
        // admin can update
        s.setVerifier(address(0xBEEF));
        assertEq(s.verifier(), address(0xBEEF));
    }

    function test_RejectZeroVerifier() public {
        // The verifier is required, so setting it to the zero address is rejected (fails closed).
        vm.expectRevert(ISemaphore.SemaphoreVerifierIsZero.selector);
        s.setVerifier(address(0));
    }

    function test_InterfaceIdMatchesConstant() public pure {
        assertEq(type(ISemaphore).interfaceId, bytes4(0xf497879d), "ISemaphore interfaceId moved");
    }

    function test_SupportsInterface() public view {
        assertTrue(s.supportsInterface(type(ISemaphore).interfaceId));
    }
}

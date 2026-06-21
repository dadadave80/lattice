// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IPrivateVoting} from "@lattice/interfaces/IPrivateVoting.sol";
import {ISemaphore} from "@lattice/interfaces/ISemaphore.sol";
import {PrivateVoting} from "@lattice/privacy/PrivateVoting.sol";
import {Semaphore} from "@lattice/privacy/Semaphore.sol";
import {PrivateVotingLib} from "@lattice/privacy/libraries/PrivateVotingLib.sol";
import {SemaphoreLib} from "@lattice/privacy/libraries/SemaphoreLib.sol";
import {SemaphoreVerifier} from "@semaphore/SemaphoreVerifier.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Harness composing the PrivateVoting + Semaphore facets in one diamond.
contract MockVotingContract is PrivateVoting, Semaphore {
    function initialize(address verifier) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        SemaphoreLib.__Semaphore_init(verifier);
        PrivateVotingLib.__PrivateVoting_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

/// @title PrivateVotingTester
/// @notice Tests anonymous 1p1v over Semaphore using REAL proofs (scope = pollId = 1, message = choice).
contract PrivateVotingTester is Test {
    MockVotingContract v;
    uint256 groupId;

    uint256 constant ROOT = 5504274371000021352836406185992230687759203853005470845011606913465462220001;

    function setUp() public {
        SemaphoreVerifier verifier = new SemaphoreVerifier();
        v = new MockVotingContract();
        v.initialize(address(verifier));
        vm.warp(1_000_000);
        groupId = v.createGroup(); // groupId 0, admin = this
        uint256[] memory c = _commitments();
        v.addMembers(groupId, c);
        assertEq(v.getMerkleTreeRoot(groupId), ROOT, "group root mismatch");
    }

    function _commitments() internal pure returns (uint256[] memory c) {
        c = new uint256[](3);
        c[0] = 17949992577497164382864432164243702268920029987038590152616928858552957999582;
        c[1] = 4249399685134541224162435585301087150767153586340041298231151767920676646338;
        c[2] = 13437183960962146794866378975828372296062966514344951918805485185578865539414;
    }

    // aliceFor: scope=1, message=1 ("for")
    function _aliceFor() internal pure returns (ISemaphore.SemaphoreProof memory p) {
        p.merkleTreeDepth = 2;
        p.merkleTreeRoot = ROOT;
        p.nullifier = 17665386117840923362363448966770809018339331190752797181313770969909958498172;
        p.message = 1;
        p.scope = 1;
        p.points = [
            uint256(20196458981195194000846627961181540804989238189048564062508563667876240356556),
            13155482868756179436825063493141532452384917114344960108790373159371771421893,
            12255486888841231144549937616800709257849629354968007037190102698242566400791,
            21399202054029473463488330945199498391739519151850429129083332828227123998717,
            13397324343562805745782556855095081187346293223499889866161512775333843462978,
            2792311850486425808966537120261321525938960591520408505397840473730990986932,
            18272550688887394887281392024140301638865198143056788615374352297959592898448,
            748347156975453846976325381481739342596451063481662730714441789709761324408
        ];
    }

    // bobAgainst: scope=1, message=0 ("against")
    function _bobAgainst() internal pure returns (ISemaphore.SemaphoreProof memory p) {
        p.merkleTreeDepth = 2;
        p.merkleTreeRoot = ROOT;
        p.nullifier = 13494162983801382079352638909962754439556059771453220127531450321471561081640;
        p.message = 0;
        p.scope = 1;
        p.points = [
            uint256(15921821929287181681052755670660052688828305421610418070817935969088194516955),
            7775540222503412917495665282465863207760677910711649403254003326523009243433,
            10354912669253653501966625106176292953662447800757667049833221148441446580222,
            1675531934881144236843207386410908657933742470888037723978637504812410944316,
            15672390184625039905228340512795562425985076684354591410062165082380305857793,
            10027105387884352140368049041757682503791971468998526287217599659749744894552,
            7418417306084011264885244481365165114811497762167889983320288647293456828687,
            684314859580313565545520336764682689543752992100398897649279254724132587788
        ];
    }

    function _newPoll() internal returns (uint256) {
        return v.createPoll(groupId, 3, 0, 0); // 3 choices, always open
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_CreatePollAndTallyVotes() public {
        uint256 pollId = _newPoll();
        assertEq(pollId, 1);

        v.vote(pollId, _aliceFor());
        assertEq(v.getVotes(pollId, 1), 1);
        assertEq(v.getPoll(pollId).totalVotes, 1);
        assertTrue(v.hasVoted(pollId, _aliceFor().nullifier));

        v.vote(pollId, _bobAgainst());
        assertEq(v.getVotes(pollId, 0), 1);
        assertEq(v.getVotes(pollId, 1), 1);
        assertEq(v.getPoll(pollId).totalVotes, 2);
    }

    function test_DoubleVoteReverts() public {
        uint256 pollId = _newPoll();
        v.vote(pollId, _aliceFor());
        vm.expectRevert(IPrivateVoting.PrivateVotingAlreadyVoted.selector);
        v.vote(pollId, _aliceFor());
    }

    function test_ScopeMismatchReverts() public {
        _newPoll(); // pollId 1
        uint256 pollId2 = _newPoll(); // pollId 2; aliceFor.scope == 1 != 2
        vm.expectRevert(IPrivateVoting.PrivateVotingScopeMismatch.selector);
        v.vote(pollId2, _aliceFor());
    }

    function test_InvalidChoiceReverts() public {
        uint256 pollId = _newPoll(); // numChoices 3
        ISemaphore.SemaphoreProof memory bad = _aliceFor();
        bad.message = 99; // >= numChoices; checked before the ZK verify
        vm.expectRevert(IPrivateVoting.PrivateVotingInvalidChoice.selector);
        v.vote(pollId, bad);
    }

    function test_TamperedProofRejected() public {
        uint256 pollId = _newPoll();
        ISemaphore.SemaphoreProof memory bad = _aliceFor();
        unchecked {
            bad.nullifier = bad.nullifier + 1; // wrong public signal -> verifier returns false
        }
        vm.expectRevert(IPrivateVoting.PrivateVotingInvalidProof.selector);
        v.vote(pollId, bad);
    }

    function test_PollDoesNotExistReverts() public {
        vm.expectRevert(IPrivateVoting.PrivateVotingPollDoesNotExist.selector);
        v.vote(999, _aliceFor());
    }

    function test_OnlyGroupAdminCreatesPoll() public {
        vm.prank(address(0xBEEF));
        vm.expectRevert(IPrivateVoting.PrivateVotingNotGroupAdmin.selector);
        v.createPoll(groupId, 3, 0, 0);
    }

    function test_InvalidNumChoicesReverts() public {
        vm.expectRevert(IPrivateVoting.PrivateVotingInvalidNumChoices.selector);
        v.createPoll(groupId, 1, 0, 0);
    }

    function test_InvalidTimeWindowReverts() public {
        vm.expectRevert(IPrivateVoting.PrivateVotingInvalidTimeWindow.selector);
        v.createPoll(groupId, 3, 1000, 500); // endTime <= startTime
    }

    function test_NotOpenReverts() public {
        uint256 pollId = v.createPoll(groupId, 3, uint64(block.timestamp + 1000), 0);
        vm.expectRevert(IPrivateVoting.PrivateVotingNotOpen.selector);
        v.vote(pollId, _aliceFor());
    }

    function test_ClosedReverts() public {
        uint256 pollId = v.createPoll(groupId, 3, 1, 500); // window in the past (now == 1_000_000)
        vm.expectRevert(IPrivateVoting.PrivateVotingClosed.selector);
        v.vote(pollId, _aliceFor());
    }

    function test_InterfaceIdMatchesConstant() public pure {
        assertEq(type(IPrivateVoting).interfaceId, bytes4(0xf750b661), "IPrivateVoting interfaceId moved");
    }

    function test_SupportsInterface() public view {
        assertTrue(v.supportsInterface(type(IPrivateVoting).interfaceId));
    }
}

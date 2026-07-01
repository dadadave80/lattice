// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {ICommitReveal} from "@lattice/interfaces/privacy/ICommitReveal.sol";
import {CommitReveal} from "@lattice/privacy/CommitReveal.sol";
import {CommitRevealLib} from "@lattice/privacy/libraries/CommitRevealLib.sol";
import {Test} from "forge-std/Test.sol";

/// @title MockCommitRevealContract
/// @notice Wrapper that inherits the CommitReveal facet and exposes init + ERC-165 discovery.
contract MockCommitRevealContract is CommitReveal {
    function initialize() external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        CommitRevealLib.__CommitReveal_init();
        InitializableLib.postInitializer(s);
    }

    function supportsInterface(bytes4 interfaceId) external view returns (bool) {
        return ERC165Lib.supportsInterface(interfaceId);
    }
}

/// @title CommitRevealTest
/// @notice Unit tests for the commit–reveal primitive facet.
contract CommitRevealTest is Test {
    MockCommitRevealContract cr;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address attacker = address(0xBAD);

    bytes32 constant SALT = keccak256("salt-1");

    event Committed(bytes32 indexed commitment, address indexed committer, uint64 committedAt);
    event Revealed(bytes32 indexed commitment, address indexed committer, bytes data, bytes32 salt);

    function setUp() public {
        cr = new MockCommitRevealContract();
        cr.initialize();
        vm.warp(1_000_000);
    }

    function _data() internal pure returns (bytes memory) {
        return hex"deadbeef";
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  commit
    //////////////////////////////////////////////////////////////////////////*//

    function test_CommitStoresAndEmits() public {
        bytes32 h = cr.computeCommitment(alice, _data(), SALT);
        vm.expectEmit(true, true, false, true, address(cr));
        emit Committed(h, alice, uint64(block.timestamp));
        vm.prank(alice);
        cr.commit(h);

        ICommitReveal.Commitment memory c = cr.commitmentInfo(h);
        assertEq(c.committer, alice);
        assertEq(c.committedAt, uint64(block.timestamp));
        assertFalse(c.revealed);
    }

    function test_CommitZeroReverts() public {
        vm.expectRevert(ICommitReveal.CommitRevealZeroCommitment.selector);
        cr.commit(bytes32(0));
    }

    function test_CommitDuplicateReverts() public {
        bytes32 h = cr.computeCommitment(alice, _data(), SALT);
        vm.prank(alice);
        cr.commit(h);
        vm.expectRevert(abi.encodeWithSelector(ICommitReveal.CommitRevealAlreadyCommitted.selector, h));
        cr.commit(h);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  reveal
    //////////////////////////////////////////////////////////////////////////*//

    function test_RevealMarksRevealedAndEmits() public {
        bytes32 h = cr.computeCommitment(alice, _data(), SALT);
        vm.prank(alice);
        cr.commit(h);

        vm.expectEmit(true, true, false, true, address(cr));
        emit Revealed(h, alice, _data(), SALT);
        vm.prank(alice);
        cr.reveal(_data(), SALT);

        assertTrue(cr.isRevealed(h));
    }

    function test_RevealNotCommittedReverts() public {
        bytes32 h = cr.computeCommitment(alice, _data(), SALT);
        vm.expectRevert(abi.encodeWithSelector(ICommitReveal.CommitRevealNotCommitted.selector, h));
        vm.prank(alice);
        cr.reveal(_data(), SALT);
    }

    function test_RevealTwiceReverts() public {
        bytes32 h = cr.computeCommitment(alice, _data(), SALT);
        vm.startPrank(alice);
        cr.commit(h);
        cr.reveal(_data(), SALT);
        vm.expectRevert(abi.encodeWithSelector(ICommitReveal.CommitRevealAlreadyRevealed.selector, h));
        cr.reveal(_data(), SALT);
        vm.stopPrank();
    }

    function test_WrongSenderCannotReveal() public {
        // alice commits a hash bound to alice.
        bytes32 h = cr.computeCommitment(alice, _data(), SALT);
        vm.prank(alice);
        cr.commit(h);
        // bob reveals the same data/salt: reveal recomputes the hash bound to bob, which was never committed.
        bytes32 bobHash = cr.computeCommitment(bob, _data(), SALT);
        vm.expectRevert(abi.encodeWithSelector(ICommitReveal.CommitRevealNotCommitted.selector, bobHash));
        vm.prank(bob);
        cr.reveal(_data(), SALT);
        assertFalse(cr.isRevealed(h));
    }

    function test_WrongDataReverts() public {
        bytes32 h = cr.computeCommitment(alice, _data(), SALT);
        vm.prank(alice);
        cr.commit(h);
        bytes memory wrong = hex"00";
        bytes32 wrongHash = cr.computeCommitment(alice, wrong, SALT);
        vm.expectRevert(abi.encodeWithSelector(ICommitReveal.CommitRevealNotCommitted.selector, wrongHash));
        vm.prank(alice);
        cr.reveal(wrong, SALT);
    }

    function test_FrontRunCommitDoesNotBlockReveal() public {
        // bob's commitment binds bob; an attacker front-runs the commit transaction.
        bytes32 h = cr.computeCommitment(bob, _data(), SALT);
        vm.prank(attacker);
        cr.commit(h);
        assertEq(cr.commitmentInfo(h).committer, attacker);

        // No hijack: the attacker's reveal recomputes a hash bound to the attacker, which was never committed.
        bytes32 attackerHash = cr.computeCommitment(attacker, _data(), SALT);
        vm.expectRevert(abi.encodeWithSelector(ICommitReveal.CommitRevealNotCommitted.selector, attackerHash));
        vm.prank(attacker);
        cr.reveal(_data(), SALT);

        // No block: bob can still reveal — the hash binds bob, so the front-run did not stop him.
        vm.prank(bob);
        cr.reveal(_data(), SALT);
        assertTrue(cr.isRevealed(h));
    }

    function test_CannotRecommitAfterReveal() public {
        // A revealed commitment is permanently consumed and cannot be re-committed.
        bytes32 h = cr.computeCommitment(alice, _data(), SALT);
        vm.startPrank(alice);
        cr.commit(h);
        cr.reveal(_data(), SALT);
        vm.expectRevert(abi.encodeWithSelector(ICommitReveal.CommitRevealAlreadyCommitted.selector, h));
        cr.commit(h);
        vm.stopPrank();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  misc
    //////////////////////////////////////////////////////////////////////////*//

    function test_ComputeCommitmentMatches() public view {
        assertEq(cr.computeCommitment(alice, _data(), SALT), keccak256(abi.encode(alice, _data(), SALT)));
    }

    function test_SupportsICommitReveal() public view {
        assertTrue(cr.supportsInterface(type(ICommitReveal).interfaceId));
    }

    function test_InterfaceIdMatchesConstant() public pure {
        assertEq(type(ICommitReveal).interfaceId, bytes4(0xe371e8b7), "ICommitReveal interfaceId moved");
    }
}

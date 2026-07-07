// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {ERC20VotesTestBase} from "@lattice-test/base/ERC20VotesTestBase.sol";
import {ERC20VotesTestFacet} from "@lattice-test/helpers/ERC20VotesTestFacet.sol";
import {IVotes} from "@lattice/interfaces/governance/IVotes.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC20Votes} from "@lattice/interfaces/tokens/IERC20Votes.sol";
import {INonces} from "@lattice/interfaces/utils/INonces.sol";
import {Checkpoints} from "@lattice/utils/libraries/Checkpoints.sol";

/// @notice Combined handle over the composed votes-token diamond: the ERC-5805 voting surface ({IVotes}, served by
///         the separately-cut {Votes} facet), the ERC-20 share surface ({IERC20}), and the OZ checkpoint accessors
///         (served by the {ERC20Votes} facet) — all on ONE diamond assembled by {DeployERC20Votes}.
interface IVotesTokenHandle is IVotes, IERC20 {
    function numCheckpoints(address account) external view returns (uint32);
    function checkpoints(address account, uint32 pos) external view returns (Checkpoints.Checkpoint208 memory);
}

/// @title ERC20VotesTest
/// @notice Exercises the {ERC20Votes} facet through a REAL {Diamond} assembled by the ready-to-deploy
///         {DeployERC20Votes} script (base ERC-20 + the ERC20Votes mixed cut that REPLACES transfer/transferFrom
///         and ADDS the ERC-5805 delegation surface + AccessControl). Every delegation, checkpoint, and
///         `delegateBySig` call routes through the diamond's `delegatecall` dispatch, not a flattened inheritance
///         mock; the checkpoint/cap `mint`/`burn` and the `nonces`/`DOMAIN_SEPARATOR` reads come from the
///         test-only {ERC20VotesTestFacet} (`helper`), `approve`/`totalSupply` from the base ERC-20 facet
///         (`erc20`), and `supportsInterface` from the cut-in `ERC165Facet`.
contract ERC20VotesTest is ERC20VotesTestBase {
    IVotesTokenHandle internal token; // votes surface (getVotes/delegate/transfer/checkpoints/clock/…) on the diamond
    IERC20 internal erc20; // base ERC-20 surface (approve/totalSupply) on the same diamond
    ERC20VotesTestFacet internal helper; // test-only mint/burn/nonces/DOMAIN_SEPARATOR

    address admin = address(0xAD);
    address alice;
    uint256 aliceKey = 0xA11CE;
    address bob = address(0xB0B);
    address charlie = address(0xC4);

    uint256 constant INITIAL_SUPPLY = 1_000e18;

    bytes32 constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousVotes, uint256 newVotes);

    function setUp() public {
        alice = vm.addr(aliceKey);
        diamond = _deployERC20Votes("Vote Token", "VOTE", admin);
        token = IVotesTokenHandle(diamond);
        erc20 = IERC20(diamond);
        helper = ERC20VotesTestFacet(diamond);
        // Mint initial supply to alice
        helper.mint(alice, INITIAL_SUPPLY);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          HELPER: build delegation digest
    //////////////////////////////////////////////////////////////////////////*//

    function _delegationHash(address delegatee, uint256 nonce, uint256 expiry) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        return keccak256(abi.encodePacked("\x19\x01", helper.DOMAIN_SEPARATOR(), structHash));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         INITIAL STATE TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_InitialVotingPowerIsZero() public view {
        // Before delegating, getVotes returns 0 even though alice has tokens
        assertEq(token.getVotes(alice), 0);
    }

    function test_InitialDelegateIsAddressZero() public view {
        assertEq(token.delegates(alice), address(0));
    }

    function test_TotalSupplyCheckpointAfterMint() public {
        // mint already called in setUp — warp forward and query
        uint256 ts = block.timestamp;
        vm.warp(ts + 1);
        assertEq(token.getPastTotalSupply(ts), INITIAL_SUPPLY);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         DELEGATE TO SELF TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_DelegateToSelf_VotingPowerEqualsBalance() public {
        vm.prank(alice);
        token.delegate(alice);

        assertEq(token.getVotes(alice), INITIAL_SUPPLY);
        assertEq(token.delegates(alice), alice);
    }

    function test_DelegateToSelf_EmitsDelegateChanged() public {
        vm.expectEmit(true, true, true, false, address(token));
        emit DelegateChanged(alice, address(0), alice);

        vm.prank(alice);
        token.delegate(alice);
    }

    function test_DelegateToSelf_EmitsDelegateVotesChanged() public {
        vm.expectEmit(true, false, false, true, address(token));
        emit DelegateVotesChanged(alice, 0, INITIAL_SUPPLY);

        vm.prank(alice);
        token.delegate(alice);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       DELEGATE TO ANOTHER TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_DelegateToAnother_VotesTransferFromPreviousDelegate() public {
        // Alice delegates to bob first
        vm.prank(alice);
        token.delegate(bob);
        assertEq(token.getVotes(bob), INITIAL_SUPPLY);
        assertEq(token.getVotes(alice), 0);

        // Alice re-delegates to charlie
        vm.prank(alice);
        token.delegate(charlie);
        assertEq(token.getVotes(charlie), INITIAL_SUPPLY);
        assertEq(token.getVotes(bob), 0);
    }

    function test_DelegateToAnother_ThenToSelf() public {
        vm.prank(alice);
        token.delegate(bob);
        assertEq(token.getVotes(bob), INITIAL_SUPPLY);

        vm.prank(alice);
        token.delegate(alice);
        assertEq(token.getVotes(alice), INITIAL_SUPPLY);
        assertEq(token.getVotes(bob), 0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       TRANSFER BETWEEN NON-DELEGATORS
    //////////////////////////////////////////////////////////////////////////*//

    function test_TransferBetweenNonDelegators_DoesNotMoveDelegatedVotes() public {
        // Neither alice nor bob has delegated — voting power stays 0
        vm.prank(alice);
        token.transfer(bob, 100e18);

        assertEq(token.getVotes(alice), 0);
        assertEq(token.getVotes(bob), 0);
    }

    function test_TransferBetweenNonDelegators_TotalSupplyCheckpointUpdates() public {
        uint256 ts = block.timestamp;
        // Mint more to observe total supply checkpoint
        helper.mint(bob, 500e18);

        vm.warp(ts + 1);
        assertEq(token.getPastTotalSupply(ts), INITIAL_SUPPLY + 500e18);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       TRANSFER BETWEEN DELEGATORS
    //////////////////////////////////////////////////////////////////////////*//

    function test_TransferBetweenDelegators_MovesVotes() public {
        // Alice and bob both delegate to themselves
        vm.prank(alice);
        token.delegate(alice);
        vm.prank(bob);
        token.delegate(bob);

        uint256 transferAmount = 200e18;

        vm.prank(alice);
        token.transfer(bob, transferAmount);

        assertEq(token.getVotes(alice), INITIAL_SUPPLY - transferAmount);
        assertEq(token.getVotes(bob), transferAmount);
    }

    function test_TransferFrom_MovesVotes() public {
        vm.prank(alice);
        token.delegate(alice);
        vm.prank(bob);
        token.delegate(bob);

        // Alice approves charlie
        vm.prank(alice);
        erc20.approve(charlie, 300e18);

        vm.prank(charlie);
        token.transferFrom(alice, bob, 300e18);

        assertEq(token.getVotes(alice), INITIAL_SUPPLY - 300e18);
        assertEq(token.getVotes(bob), 300e18);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         GET PAST VOTES TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_GetPastVotes_AfterDelegate() public {
        vm.prank(alice);
        token.delegate(alice);

        uint256 ts = block.timestamp;
        vm.warp(ts + 1);

        assertEq(token.getPastVotes(alice, ts), INITIAL_SUPPLY);
    }

    function test_GetPastVotes_BeforeDelegate_ReturnsZero() public {
        uint256 ts = block.timestamp;
        vm.warp(ts + 1);

        vm.prank(alice);
        token.delegate(alice);

        // ts is before delegation — should return 0
        assertEq(token.getPastVotes(alice, ts), 0);
    }

    function test_GetPastVotes_FutureLookupReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IVotes.ERC5805FutureLookup.selector, block.timestamp, block.timestamp));
        token.getPastVotes(alice, block.timestamp);
    }

    function test_GetPastVotes_TracksDelegationChange() public {
        vm.prank(alice);
        token.delegate(alice);

        uint256 ts1 = block.timestamp;
        vm.warp(ts1 + 1);

        // Re-delegate to bob at ts2
        vm.prank(alice);
        token.delegate(bob);

        uint256 ts2 = block.timestamp;
        vm.warp(ts2 + 1);

        // At ts1, alice had all votes
        assertEq(token.getPastVotes(alice, ts1), INITIAL_SUPPLY);
        // At ts2, alice has none
        assertEq(token.getPastVotes(alice, ts2), 0);
        // Bob got votes at ts2
        assertEq(token.getPastVotes(bob, ts2), INITIAL_SUPPLY);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                      GET PAST TOTAL SUPPLY TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_GetPastTotalSupply_AfterMint() public {
        uint256 ts = block.timestamp;
        helper.mint(bob, 500e18);

        vm.warp(ts + 1);
        assertEq(token.getPastTotalSupply(ts), INITIAL_SUPPLY + 500e18);
    }

    function test_GetPastTotalSupply_AfterBurn() public {
        uint256 ts = block.timestamp;
        helper.burn(alice, 100e18);

        vm.warp(ts + 1);
        assertEq(token.getPastTotalSupply(ts), INITIAL_SUPPLY - 100e18);
    }

    function test_GetPastTotalSupply_FutureLookupReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IVotes.ERC5805FutureLookup.selector, block.timestamp, block.timestamp));
        token.getPastTotalSupply(block.timestamp);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                        DELEGATE BY SIG TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_DelegateBySig_ValidSig_Delegates() public {
        uint256 nonce = helper.nonces(alice);
        uint256 expiry = block.timestamp + 1 hours;

        bytes32 digest = _delegationHash(bob, nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);

        token.delegateBySig(bob, nonce, expiry, v, r, s);

        assertEq(token.delegates(alice), bob);
        assertEq(token.getVotes(bob), INITIAL_SUPPLY);
    }

    function test_DelegateBySig_ConsumesNonce() public {
        uint256 nonceBefore = helper.nonces(alice);
        uint256 expiry = block.timestamp + 1 hours;

        bytes32 digest = _delegationHash(bob, nonceBefore, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);

        token.delegateBySig(bob, nonceBefore, expiry, v, r, s);

        assertEq(helper.nonces(alice), nonceBefore + 1);
    }

    function test_DelegateBySig_ExpiredSignatureReverts() public {
        uint256 nonce = helper.nonces(alice);
        uint256 expiry = block.timestamp - 1; // already expired

        bytes32 digest = _delegationHash(bob, nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);

        vm.expectRevert(abi.encodeWithSelector(IVotes.VotesExpiredSignature.selector, expiry));
        token.delegateBySig(bob, nonce, expiry, v, r, s);
    }

    function test_DelegateBySig_WrongNonceReverts() public {
        uint256 expiry = block.timestamp + 1 hours;
        uint256 wrongNonce = 999;

        bytes32 digest = _delegationHash(bob, wrongNonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);

        vm.expectRevert(abi.encodeWithSelector(INonces.InvalidAccountNonce.selector, alice, uint256(0)));
        token.delegateBySig(bob, wrongNonce, expiry, v, r, s);
    }

    function test_DelegateBySig_ReplaySameSignatureReverts() public {
        uint256 nonce = helper.nonces(alice);
        uint256 expiry = block.timestamp + 1 hours;

        bytes32 digest = _delegationHash(bob, nonce, expiry);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);

        token.delegateBySig(bob, nonce, expiry, v, r, s);

        // Replay: nonce is now 1, passing old nonce=0 triggers InvalidAccountNonce(alice, 1)
        vm.expectRevert(abi.encodeWithSelector(INonces.InvalidAccountNonce.selector, alice, uint256(1)));
        token.delegateBySig(bob, nonce, expiry, v, r, s);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    MINT ABOVE UINT208 MAX REVERTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_MintAboveUint208Max_Reverts() public {
        uint256 cap = type(uint208).max;
        // Current supply is INITIAL_SUPPLY; mint enough to exceed cap
        uint256 excess = cap - INITIAL_SUPPLY + 1;

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Votes.ERC20ExceededSafeSupply.selector, INITIAL_SUPPLY + excess, cap)
        );
        helper.mint(bob, excess);
    }

    function test_MintExactlyAtCap_Succeeds() public {
        uint256 cap = type(uint208).max;
        uint256 remaining = cap - INITIAL_SUPPLY;
        helper.mint(bob, remaining);
        assertEq(erc20.totalSupply(), cap);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               CLOCK TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_Clock_ReturnsCurrentTimestamp() public view {
        assertEq(token.clock(), uint48(block.timestamp));
    }

    function test_ClockMode_IsTimestamp() public view {
        assertEq(token.CLOCK_MODE(), "mode=timestamp");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ERC-165 TESTS
    //////////////////////////////////////////////////////////////////////////*//

    function test_SupportsIVotes() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IVotes).interfaceId));
    }

    function test_SupportsIERC20() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC20).interfaceId));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //           E2V-03: numCheckpoints / checkpoints accessors
    //////////////////////////////////////////////////////////////////////////*//

    function test_NumCheckpoints_BeforeDelegate_IsZero() public view {
        assertEq(token.numCheckpoints(alice), 0);
    }

    function test_NumCheckpoints_AfterDelegate_IsOne() public {
        vm.prank(alice);
        token.delegate(alice);

        // One checkpoint pushed when voting units move
        assertEq(token.numCheckpoints(alice), 1);
    }

    function test_NumCheckpoints_AfterTwoDelegations_IsTwo() public {
        vm.prank(alice);
        token.delegate(alice);

        // Warp so second delegation lands on a different timestamp key
        vm.warp(block.timestamp + 1);

        vm.prank(alice);
        token.delegate(bob);

        // alice lost votes (one more checkpoint pushed for alice)
        assertEq(token.numCheckpoints(alice), 2);
    }

    function test_Checkpoints_ReturnsCorrectEntry() public {
        vm.prank(alice);
        token.delegate(alice);

        uint48 ts = uint48(block.timestamp);
        // First checkpoint: key == current timestamp, value == INITIAL_SUPPLY
        (bool exists, uint48 key, uint208 value) = type(uint48).max > 0
            ? (true, token.checkpoints(alice, 0)._key, token.checkpoints(alice, 0)._value)
            : (false, 0, 0);

        assertTrue(exists);
        assertEq(key, ts);
        assertEq(value, uint208(INITIAL_SUPPLY));
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC721Votes} from "@lattice-script/base/tokens/DeployERC721Votes.s.sol";
import {ERC721TestBase} from "@lattice-test/base/ERC721TestBase.sol";
import {ERC721TestFacet} from "@lattice-test/helpers/ERC721TestFacet.sol";
import {DELEGATION_TYPEHASH} from "@lattice/governance/libraries/VotesLib.sol";
import {IVotes} from "@lattice/interfaces/governance/IVotes.sol";
import {IERC721} from "@lattice/interfaces/tokens/IERC721.sol";
import {ERC721} from "@lattice/tokens/ERC721/ERC721.sol";
import {ERC721Votes} from "@lattice/tokens/ERC721/ERC721Votes.sol";

/// @title ERC721VotesTest
/// @notice Exercises the {ERC721Votes} facet through a REAL diamond assembled by the {DeployERC721Votes} recipe:
///         base ERC-721, the {Votes} facet, and {ERC721Votes}, which REPLACES `transferFrom`, both
///         `safeTransferFrom` overloads and the {Votes} facet's `delegate`/`delegateBySig`. One token is one voting
///         unit. The test-only {ERC721TestFacet} mints and burns through {ERC721VotesLib}.
contract ERC721VotesTest is ERC721TestBase {
    IVotes internal votes;

    uint256 internal aliceKey = 0xA11CE;
    address internal alice;
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA201);

    string internal constant NAME = "Votes NFT";

    function setUp() public override {
        alice = vm.addr(aliceKey);
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            new DeployERC721Votes().buildCuts(NAME, "VNFT");
        diamond = _deployWithHelper(cuts, inits, initCalldatas);
        token = ERC721(diamond);
        helper = ERC721TestFacet(diamond);
        votes = IVotes(diamond);
        vm.warp(1000);
    }

    function test_SupportsInterface() public view {
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IVotes).interfaceId), "IVotes");
        assertTrue(ERC165Facet(diamond).supportsInterface(0x80ac58cd), "EIP-721");
    }

    /// @notice The recipe routes the movement selectors and the delegations to the votes facet.
    function test_RecipeReplacesMovementAndDelegation() public view {
        address facet = IDiamondLoupe(diamond).facetAddress(ERC721Votes.delegate.selector);
        assertTrue(facet != IDiamondLoupe(diamond).facetAddress(IVotes.getVotes.selector), "not the Votes facet");
        assertEq(IDiamondLoupe(diamond).facetAddress(ERC721Votes.delegateBySig.selector), facet, "delegateBySig");
        assertEq(IDiamondLoupe(diamond).facetAddress(IERC721.transferFrom.selector), facet, "transferFrom");
        assertEq(IDiamondLoupe(diamond).facetAddress(0x42842e0e), facet, "safeTransferFrom(3)");
        assertEq(IDiamondLoupe(diamond).facetAddress(0xb88d4fde), facet, "safeTransferFrom(4)");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                      MINT, BURN AND TRANSFER MOVE UNITS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Units count only once delegated: delegating counts every token already held.
    function test_DelegateCountsHeldTokens() public {
        helper.votesMint(alice, 1);
        helper.votesMint(alice, 2);
        assertEq(votes.getVotes(alice), 0, "undelegated tokens carry no votes");

        vm.prank(alice);
        votes.delegate(alice);
        assertEq(votes.getVotes(alice), 2, "one unit per token");
        assertEq(votes.delegates(alice), alice);
    }

    function test_MintMovesUnitsToDelegate() public {
        vm.prank(alice);
        votes.delegate(bob);
        helper.votesMint(alice, 1);
        assertEq(votes.getVotes(bob), 1);
        helper.votesSafeMint(alice, 2);
        assertEq(votes.getVotes(bob), 2);
    }

    function test_BurnMovesUnitsOut() public {
        helper.votesMint(alice, 1);
        helper.votesMint(alice, 2);
        vm.prank(alice);
        votes.delegate(alice);

        helper.votesBurn(1);
        assertEq(votes.getVotes(alice), 1);
    }

    function test_TransferFromMovesUnitsBetweenDelegates() public {
        helper.votesMint(alice, 1);
        vm.prank(alice);
        votes.delegate(alice);
        vm.prank(bob);
        votes.delegate(carol);

        vm.prank(alice);
        token.transferFrom(alice, bob, 1);
        assertEq(votes.getVotes(alice), 0);
        assertEq(votes.getVotes(carol), 1, "bob's delegate gains the unit");
    }

    function test_SafeTransferFromBothOverloadsMoveUnits() public {
        helper.votesMint(alice, 1);
        helper.votesMint(alice, 2);
        vm.prank(alice);
        votes.delegate(alice);
        vm.prank(bob);
        votes.delegate(bob);

        vm.startPrank(alice);
        token.safeTransferFrom(alice, bob, 1);
        token.safeTransferFrom(alice, bob, 2, "data");
        vm.stopPrank();
        assertEq(votes.getVotes(alice), 0);
        assertEq(votes.getVotes(bob), 2);
    }

    function test_TransferFromKeepsBaseChecks() public {
        helper.votesMint(alice, 1);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InsufficientApproval.selector, bob, 1));
        token.transferFrom(alice, bob, 1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721IncorrectOwner.selector, bob, 1, alice));
        token.transferFrom(bob, carol, 1);
    }

    /// @notice The authorization-free {ERC721VotesLib._transfer}/{_safeTransfer} (for permissioned or
    ///         signature-based movement) move voting units, as OpenZeppelin's `_update` override does.
    function test_UnauthorizedTransferMovesUnits() public {
        helper.votesMint(alice, 1);
        helper.votesMint(alice, 2);
        vm.prank(alice);
        votes.delegate(alice);
        vm.prank(bob);
        votes.delegate(carol);

        helper.votesTransfer(alice, bob, 1);
        assertEq(votes.getVotes(alice), 1);
        assertEq(votes.getVotes(carol), 1, "bob's delegate gains the unit");

        helper.votesSafeTransfer(alice, bob, 2);
        assertEq(votes.getVotes(alice), 0);
        assertEq(votes.getVotes(carol), 2);
    }

    /// @notice The authorization-free transfers keep {ERC721Lib._transfer}'s checks.
    function test_UnauthorizedTransferKeepsBaseChecks() public {
        helper.votesMint(alice, 1);
        vm.prank(alice);
        votes.delegate(alice);

        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, 9));
        helper.votesTransfer(alice, bob, 9);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721IncorrectOwner.selector, bob, 1, alice));
        helper.votesTransfer(bob, carol, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InvalidReceiver.selector, address(0)));
        helper.votesTransfer(alice, address(0), 1);
        assertEq(votes.getVotes(alice), 1, "the reverted transfers moved no unit");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         PAST SUPPLY AND CHECKPOINTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Mint and burn checkpoint the total supply; a transfer does not change it.
    function test_PastTotalSupplyTracksMintAndBurn() public {
        helper.votesMint(alice, 1);
        helper.votesMint(alice, 2);
        vm.warp(1001);
        helper.votesBurn(1);
        vm.warp(1002);
        vm.prank(alice);
        token.transferFrom(alice, bob, 2);
        vm.warp(1003);

        assertEq(votes.getPastTotalSupply(1000), 2);
        assertEq(votes.getPastTotalSupply(1001), 1);
        assertEq(votes.getPastTotalSupply(1002), 1);
    }

    function test_PastVotesFollowTransfers() public {
        helper.votesMint(alice, 1);
        vm.prank(alice);
        votes.delegate(alice);
        vm.prank(bob);
        votes.delegate(bob);
        vm.warp(1001);
        vm.prank(alice);
        token.transferFrom(alice, bob, 1);
        vm.warp(1002);

        assertEq(votes.getPastVotes(alice, 1000), 1);
        assertEq(votes.getPastVotes(alice, 1001), 0);
        assertEq(votes.getPastVotes(bob, 1001), 1);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             DELEGATE BY SIG
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice A signed delegation counts the signer's ERC-721 balance (not the base facet's ERC-20 balance).
    function test_DelegateBySigUsesNftBalance() public {
        helper.votesMint(alice, 1);
        helper.votesMint(alice, 2);
        uint256 expiry = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, _delegationDigest(bob, 0, expiry));

        vm.prank(carol);
        votes.delegateBySig(bob, 0, expiry, v, r, s);
        assertEq(votes.delegates(alice), bob);
        assertEq(votes.getVotes(bob), 2);

        vm.expectRevert();
        votes.delegateBySig(bob, 0, expiry, v, r, s);
    }

    function test_DelegateBySigExpiredReverts() public {
        uint256 expiry = block.timestamp - 1;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, _delegationDigest(bob, 0, expiry));
        vm.expectRevert(abi.encodeWithSelector(IVotes.VotesExpiredSignature.selector, expiry));
        votes.delegateBySig(bob, 0, expiry, v, r, s);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  FUZZ
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice After any mint/transfer mix, each self-delegated holder's votes equal its balance.
    function testFuzz_VotesEqualBalances(uint8 n, uint256 mask) public {
        n = uint8(bound(n, 1, 24));
        vm.prank(alice);
        votes.delegate(alice);
        vm.prank(bob);
        votes.delegate(bob);
        for (uint256 i; i < n; ++i) {
            helper.votesMint(alice, i);
        }
        for (uint256 i; i < n; ++i) {
            if ((mask >> i) & 1 == 1) {
                vm.prank(alice);
                token.transferFrom(alice, bob, i);
            }
        }
        assertEq(votes.getVotes(alice), token.balanceOf(alice));
        assertEq(votes.getVotes(bob), token.balanceOf(bob));
        assertEq(votes.getVotes(alice) + votes.getVotes(bob), n);
    }

    function _delegationDigest(address delegatee, uint256 nonce, uint256 expiry) internal view returns (bytes32) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(NAME)),
                keccak256("1"),
                block.chainid,
                diamond
            )
        );
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}

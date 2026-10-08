// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MultiInit} from "@diamond/initializers/MultiInit.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC20} from "@lattice-script/base/tokens/DeployERC20.s.sol";
import {ERC20VotesTestFacet} from "@lattice-test/helpers/ERC20VotesTestFacet.sol";
import {TokenTestFacet} from "@lattice-test/helpers/TokenTestFacet.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {Votes} from "@lattice/governance/Votes.sol";
import {IVotes} from "@lattice/interfaces/governance/IVotes.sol";
import {ERC20VotesInit} from "@lattice/tokens/ERC20/ERC20VotesInit.sol";
import {Test} from "forge-std/Test.sol";

/// @title VotesTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Exercises the standalone {Votes} facet on a REAL {Diamond} built from the base {DeployERC20} recipe
///         plus `Votes`, WITHOUT {ERC20Votes}: both delegation entrypoints must count the delegator's ERC-20
///         balance, as OpenZeppelin's `_getVotingUnits` does. `mint` comes from the test-only {TokenTestFacet}
///         (plain {ERC20Lib._mint}) and `nonces`/`DOMAIN_SEPARATOR` from {ERC20VotesTestFacet}.
contract VotesTest is Test {
    bytes32 internal constant DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");
    uint256 internal constant BALANCE = 100e18;

    address internal token;
    uint256 internal aliceKey = 0xA11CE;
    address internal alice;
    address internal bob = makeAddr("bob");

    function setUp() public {
        alice = vm.addr(aliceKey);
        (FacetCut[] memory base, address baseInit, bytes memory baseData) = new DeployERC20().buildCuts("Token", "TKN");

        address helper = address(new ERC20VotesTestFacet());
        bytes4[] memory helperSels = new bytes4[](2);
        (helperSels[0], helperSels[1]) =
        (ERC20VotesTestFacet.nonces.selector, ERC20VotesTestFacet.DOMAIN_SEPARATOR.selector);
        bytes4[] memory mintSel = new bytes4[](1);
        mintSel[0] = TokenTestFacet.mint.selector;

        FacetCut[] memory cuts = new FacetCut[](base.length + 3);
        for (uint256 i; i < base.length; ++i) {
            cuts[i] = base[i];
        }
        Votes votes = new Votes();
        cuts[base.length] = _add(address(votes), _exported(votes));
        cuts[base.length + 1] = _add(helper, helperSels);
        cuts[base.length + 2] = _add(address(new TokenTestFacet()), mintSel);

        address[] memory inits = new address[](2);
        bytes[] memory datas = new bytes[](2);
        (inits[0], datas[0]) = (baseInit, baseData);
        (inits[1], datas[1]) = (address(new ERC20VotesInit()), abi.encodeCall(ERC20VotesInit.init, ("Token", alice)));

        Lattice d = new Lattice();
        d.initialize(cuts, address(new MultiInit()), abi.encodeCall(MultiInit.multiInit, (inits, datas)));
        token = address(d);
        TokenTestFacet(token).mint(alice, BALANCE);
    }

    function test_Delegate_CountsBalance() public {
        vm.prank(alice);
        IVotes(token).delegate(bob);
        assertEq(IVotes(token).getVotes(bob), BALANCE);
    }

    /// @notice VOT-08 regression: `delegateBySig` must count the signer's balance, as `delegate` does.
    function test_DelegateBySig_CountsSignerBalance() public {
        uint256 nonce = ERC20VotesTestFacet(token).nonces(alice);
        uint256 expiry = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                ERC20VotesTestFacet(token).DOMAIN_SEPARATOR(),
                keccak256(abi.encode(DELEGATION_TYPEHASH, bob, nonce, expiry))
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);

        vm.expectEmit(token);
        emit IVotes.DelegateVotesChanged(bob, 0, BALANCE);
        IVotes(token).delegateBySig(bob, nonce, expiry, v, r, s);

        assertEq(IVotes(token).delegates(alice), bob);
        assertEq(IVotes(token).getVotes(bob), BALANCE, "signer's balance counted");
        assertEq(ERC20VotesTestFacet(token).nonces(alice), nonce + 1, "nonce consumed");
    }

    function _exported(Votes facet) internal pure returns (bytes4[] memory sels) {
        bytes memory packed = facet.exportSelectors();
        sels = new bytes4[](packed.length / 4);
        for (uint256 i; i < sels.length; ++i) {
            bytes4 sel;
            assembly ("memory-safe") {
                sel := mload(add(add(packed, 0x20), mul(i, 4)))
            }
            sels[i] = sel;
        }
    }

    function _add(address facet, bytes4[] memory sels) internal pure returns (FacetCut memory) {
        return FacetCut({facetAddress: facet, action: FacetCutAction.Add, functionSelectors: sels});
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC721Wrapper} from "@lattice-script/base/tokens/DeployERC721Wrapper.s.sol";
import {ERC721TestBase} from "@lattice-test/base/ERC721TestBase.sol";
import {ERC721TestFacet} from "@lattice-test/helpers/ERC721TestFacet.sol";
import {IERC721, IERC721Receiver} from "@lattice/interfaces/tokens/IERC721.sol";
import {IERC721Wrapper} from "@lattice/interfaces/tokens/IERC721Wrapper.sol";
import {ERC721} from "@lattice/tokens/ERC721/ERC721.sol";
import {ERC721Wrapper} from "@lattice/tokens/ERC721/ERC721Wrapper.sol";

/// @notice A contract account with no `onERC721Received`, so a safe mint to it fails.
contract NonReceiver {}

/// @notice A receiver that records the `operator` and `from` its last `onERC721Received` call carried.
contract OperatorRecorder {
    address public lastOperator;
    address public lastFrom;

    function onERC721Received(address operator, address from, uint256, bytes calldata) external returns (bytes4) {
        lastOperator = operator;
        lastFrom = from;
        return this.onERC721Received.selector;
    }
}

/// @title ERC721WrapperTest
/// @notice Exercises the {ERC721Wrapper} facet through a REAL diamond assembled by {DeployERC721Wrapper}. The
///         underlying collection is itself a REAL base ERC-721 diamond (from {DeployERC721}). Both diamonds carry the
///         test-only {ERC721TestFacet}: on the underlying it mints, on the wrapper it exposes the internal
///         `_recover` that the production facet leaves unexposed (it needs access control).
contract ERC721WrapperTest is ERC721TestBase {
    ERC721Wrapper internal wrapper;

    address internal underlyingAddr;
    ERC721 internal underlyingToken;
    ERC721TestFacet internal underlyingHelper;

    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);

    uint256 constant TOKEN_1 = 1;
    uint256 constant TOKEN_2 = 2;
    uint256 constant TOKEN_3 = 3;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    function setUp() public override {
        underlyingAddr = _deployERC721("Underlying", "UND", new FacetCut[](0));
        underlyingToken = ERC721(underlyingAddr);
        underlyingHelper = ERC721TestFacet(underlyingAddr);
        underlyingHelper.mint(alice, TOKEN_1);
        underlyingHelper.mint(alice, TOKEN_2);
        underlyingHelper.mint(alice, TOKEN_3);

        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            new DeployERC721Wrapper().buildCuts("Wrapped Underlying", "wUND", underlyingAddr);
        diamond = _deployWithHelper(cuts, inits, initCalldatas);
        token = ERC721(diamond);
        helper = ERC721TestFacet(diamond);
        wrapper = ERC721Wrapper(diamond);

        vm.prank(alice);
        underlyingToken.setApprovalForAll(diamond, true);
    }

    function _ids(uint256 a, uint256 b) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](2);
        ids[0] = a;
        ids[1] = b;
    }

    function _id(uint256 a) internal pure returns (uint256[] memory ids) {
        ids = new uint256[](1);
        ids[0] = a;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              SETUP / ERC-165
    //////////////////////////////////////////////////////////////////////////*//

    function test_Underlying() public view {
        assertEq(wrapper.underlying(), underlyingAddr, "underlying recorded");
        assertEq(token.name(), "Wrapped Underlying");
        assertEq(token.symbol(), "wUND");
    }

    function test_SupportsInterface() public view {
        assertEq(type(IERC721Wrapper).interfaceId, bytes4(0xd9e5011d), "IERC721Wrapper id");
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC721Wrapper).interfaceId), "IERC721Wrapper");
        assertTrue(ERC165Facet(diamond).supportsInterface(0x80ac58cd), "EIP-721");
        // OpenZeppelin's ERC721Wrapper does not advertise IERC721Receiver; neither does the diamond.
        assertFalse(ERC165Facet(diamond).supportsInterface(type(IERC721Receiver).interfaceId), "no receiver id");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  DEPOSIT
    //////////////////////////////////////////////////////////////////////////*//

    function test_DepositForEscrowsUnderlyingAndMintsWrapped() public {
        vm.expectEmit(true, true, true, true, diamond);
        emit Transfer(address(0), bob, TOKEN_1);
        vm.prank(alice);
        bool ok = wrapper.depositFor(bob, _ids(TOKEN_1, TOKEN_2));

        assertTrue(ok);
        assertEq(underlyingToken.ownerOf(TOKEN_1), diamond, "underlying 1 escrowed");
        assertEq(underlyingToken.ownerOf(TOKEN_2), diamond, "underlying 2 escrowed");
        assertEq(token.ownerOf(TOKEN_1), bob, "wrapped 1 minted to account");
        assertEq(token.ownerOf(TOKEN_2), bob, "wrapped 2 minted to account");
        assertEq(token.balanceOf(bob), 2);
        assertEq(underlyingToken.balanceOf(alice), 1, "alice keeps token 3");
    }

    /// @notice The wrapped id's safe mint reports the depositor as `operator`, as OpenZeppelin v5.6.1 does.
    function test_DepositForReportsDepositorAsOperator() public {
        OperatorRecorder recorder = new OperatorRecorder();
        vm.prank(alice);
        wrapper.depositFor(address(recorder), _id(TOKEN_1));

        assertEq(token.ownerOf(TOKEN_1), address(recorder));
        assertEq(recorder.lastOperator(), alice, "operator is the depositor");
        assertEq(recorder.lastFrom(), address(0), "from is zero on mint");
    }

    function test_DepositForEmptyListIsANoop() public {
        vm.prank(alice);
        assertTrue(wrapper.depositFor(bob, new uint256[](0)));
        assertEq(underlyingToken.balanceOf(alice), 3);
    }

    function test_DepositForWithoutUnderlyingApprovalReverts() public {
        vm.prank(alice);
        underlyingToken.setApprovalForAll(diamond, false);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InsufficientApproval.selector, diamond, TOKEN_1));
        wrapper.depositFor(alice, _id(TOKEN_1));
    }

    function test_DepositForOtherUsersTokenReverts() public {
        // The pull is `transferFrom(msg.sender, ...)`, so bob cannot deposit alice's token even though the
        // wrapper holds her operator approval.
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721IncorrectOwner.selector, bob, TOKEN_1, alice));
        wrapper.depositFor(bob, _id(TOKEN_1));
    }

    function test_DepositForNonReceiverContractReverts() public {
        address sink = address(new NonReceiver());
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InvalidReceiver.selector, sink));
        wrapper.depositFor(sink, _id(TOKEN_1));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 WITHDRAW
    //////////////////////////////////////////////////////////////////////////*//

    function test_WithdrawToBurnsWrappedAndReleasesUnderlying() public {
        vm.prank(alice);
        wrapper.depositFor(alice, _ids(TOKEN_1, TOKEN_2));

        vm.expectEmit(true, true, true, true, diamond);
        emit Transfer(alice, address(0), TOKEN_1);
        vm.prank(alice);
        bool ok = wrapper.withdrawTo(charlie, _ids(TOKEN_1, TOKEN_2));

        assertTrue(ok);
        assertEq(token.balanceOf(alice), 0, "wrapped burned");
        assertEq(underlyingToken.ownerOf(TOKEN_1), charlie, "underlying 1 released");
        assertEq(underlyingToken.ownerOf(TOKEN_2), charlie, "underlying 2 released");
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, TOKEN_1));
        token.ownerOf(TOKEN_1);
    }

    function test_WithdrawToByApprovedOperator() public {
        vm.prank(alice);
        wrapper.depositFor(alice, _id(TOKEN_1));
        vm.prank(alice);
        token.setApprovalForAll(bob, true);

        vm.prank(bob);
        wrapper.withdrawTo(bob, _id(TOKEN_1));
        assertEq(underlyingToken.ownerOf(TOKEN_1), bob);
    }

    function test_WithdrawToByStrangerReverts() public {
        vm.prank(alice);
        wrapper.depositFor(alice, _id(TOKEN_1));

        vm.prank(charlie);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InsufficientApproval.selector, charlie, TOKEN_1));
        wrapper.withdrawTo(charlie, _id(TOKEN_1));
    }

    function test_WithdrawToUnwrappedIdReverts() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, TOKEN_1));
        wrapper.withdrawTo(alice, _id(TOKEN_1));
    }

    function test_WithdrawToNonReceiverContractReverts() public {
        vm.prank(alice);
        wrapper.depositFor(alice, _id(TOKEN_1));

        address sink = address(new NonReceiver());
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InvalidReceiver.selector, sink));
        wrapper.withdrawTo(sink, _id(TOKEN_1));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          DIRECT SAFE TRANSFER
    //////////////////////////////////////////////////////////////////////////*//

    function test_SafeTransferOfUnderlyingMintsWrappedToSender() public {
        vm.prank(alice);
        underlyingToken.safeTransferFrom(alice, diamond, TOKEN_3);

        assertEq(underlyingToken.ownerOf(TOKEN_3), diamond, "underlying escrowed");
        assertEq(token.ownerOf(TOKEN_3), alice, "wrapped minted to the sender");
    }

    /// @notice When an approved operator safe-transfers the underlying, the wrapped id goes to the owner (`from`),
    ///         not to the operator.
    function test_SafeTransferByApprovedOperatorMintsWrappedToOwner() public {
        vm.prank(alice);
        underlyingToken.setApprovalForAll(bob, true);

        vm.prank(bob);
        underlyingToken.safeTransferFrom(alice, diamond, TOKEN_3);

        assertEq(underlyingToken.ownerOf(TOKEN_3), diamond, "underlying escrowed");
        assertEq(token.ownerOf(TOKEN_3), alice, "wrapped minted to the owner");
        assertEq(token.balanceOf(bob), 0, "operator gets nothing");
    }

    function test_SafeTransferFromAnotherCollectionReverts() public {
        address other = _deployERC721("Other", "OTH", new FacetCut[](0));
        ERC721TestFacet(other).mint(alice, TOKEN_1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721Wrapper.ERC721UnsupportedToken.selector, other));
        ERC721(other).safeTransferFrom(alice, diamond, TOKEN_1);
    }

    function test_OnERC721ReceivedFromNonUnderlyingCallerReverts() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC721Wrapper.ERC721UnsupportedToken.selector, bob));
        wrapper.onERC721Received(bob, bob, TOKEN_1, "");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  RECOVER
    //////////////////////////////////////////////////////////////////////////*//

    function test_RecoverMintsForAnUnsafeTransfer() public {
        // A plain `transferFrom` skips `onERC721Received`, so no wrapped token is minted.
        vm.prank(alice);
        underlyingToken.transferFrom(alice, diamond, TOKEN_1);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, TOKEN_1));
        token.ownerOf(TOKEN_1);

        assertEq(helper.recoverWrapped(alice, TOKEN_1), TOKEN_1);
        assertEq(token.ownerOf(TOKEN_1), alice, "recovered");
    }

    function test_RecoverForATokenNotHeldReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721IncorrectOwner.selector, diamond, TOKEN_1, alice));
        helper.recoverWrapped(alice, TOKEN_1);
    }

    function test_RecoverForAnAlreadyWrappedTokenReverts() public {
        vm.prank(alice);
        wrapper.depositFor(alice, _id(TOKEN_1));

        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InvalidSender.selector, address(0)));
        helper.recoverWrapped(bob, TOKEN_1);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   FUZZ
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Wrapping then unwrapping any id returns the underlying to the chosen account and leaves no wrapped
    ///         token, and while wrapped the diamond holds exactly the wrapped ids.
    function testFuzz_DepositWithdrawRoundTrip(uint256 tokenId, address to) public {
        vm.assume(to != address(0) && to.code.length == 0);
        vm.assume(tokenId != TOKEN_1 && tokenId != TOKEN_2 && tokenId != TOKEN_3);
        underlyingHelper.mint(alice, tokenId);

        vm.prank(alice);
        wrapper.depositFor(alice, _id(tokenId));
        assertEq(underlyingToken.ownerOf(tokenId), diamond);
        assertEq(token.ownerOf(tokenId), alice);
        assertEq(underlyingToken.balanceOf(diamond), token.balanceOf(alice), "escrow matches wrapped supply");

        vm.prank(alice);
        wrapper.withdrawTo(to, _id(tokenId));
        assertEq(underlyingToken.ownerOf(tokenId), to);
        assertEq(token.balanceOf(alice), 0);
        assertEq(underlyingToken.balanceOf(diamond), 0);
    }
}

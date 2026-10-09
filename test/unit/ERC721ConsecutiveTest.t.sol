// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MultiInit} from "@diamond/initializers/MultiInit.sol";
import {IDiamondCut} from "@diamond/interfaces/IDiamondCut.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC721} from "@lattice-script/base/tokens/DeployERC721.s.sol";
import {DeployERC721Burnable} from "@lattice-script/base/tokens/DeployERC721Burnable.s.sol";
import {DeployERC721Consecutive} from "@lattice-script/base/tokens/DeployERC721Consecutive.s.sol";
import {DeployERC721Enumerable} from "@lattice-script/base/tokens/DeployERC721Enumerable.s.sol";
import {DeployERC721Pausable} from "@lattice-script/base/tokens/DeployERC721Pausable.s.sol";
import {
    ERC721BatchWithoutInit,
    ERC721ConsecutiveReinit,
    ERC721SingleMintInit
} from "@lattice-test/helpers/ERC721ConsecutiveTestInits.sol";
import {ERC721TestFacet} from "@lattice-test/helpers/ERC721TestFacet.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {IPausable} from "@lattice/interfaces/security/IPausable.sol";
import {IERC721} from "@lattice/interfaces/tokens/IERC721.sol";
import {IERC721Burnable} from "@lattice/interfaces/tokens/IERC721Burnable.sol";
import {IERC2309, IERC721Consecutive} from "@lattice/interfaces/tokens/IERC721Consecutive.sol";
import {IERC721Enumerable} from "@lattice/interfaces/tokens/IERC721Enumerable.sol";
import {ERC721ConsecutiveInit} from "@lattice/tokens/ERC721/ERC721ConsecutiveInit.sol";
import {ERC721EnumerableInit} from "@lattice/tokens/ERC721/ERC721EnumerableInit.sol";
import {ERC721VotesInit} from "@lattice/tokens/ERC721/ERC721VotesInit.sol";
import {ERC721ConsecutiveLib} from "@lattice/tokens/ERC721/libraries/ERC721ConsecutiveLib.sol";
import {InvalidInitialization} from "@lattice/utils/libraries/InitializableLib.sol";
import {stdError} from "forge-std/StdError.sol";
import {Test, Vm} from "forge-std/Test.sol";

/// @title ERC721ConsecutiveTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Builds batch-minting ERC-721 diamonds from the {DeployERC721Consecutive} recipe (or another ERC-721 recipe
///         plus {ERC721ConsecutiveInit}) with the test-only {ERC721TestFacet} cut on top. The helper selectors are
///         listed by hand rather than through `forge inspect`, so the fuzz test can deploy a diamond per run.
abstract contract ERC721ConsecutiveTestBase is Test {
    string internal constant NAME = "Non Fungible Token";
    string internal constant SYMBOL = "NFT";

    address internal alice = makeAddr("alice");
    address internal bruce = makeAddr("bruce");
    address internal chris = makeAddr("chris");
    address internal receiver = makeAddr("receiver");

    /// @dev The recipe's `(cuts, inits, datas)` for `firstId` and the batches, plus the helper facet.
    function _deployConsecutive(uint96 firstId, address[] memory receivers, uint96[] memory amounts)
        internal
        returns (address)
    {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory datas) =
            new DeployERC721Consecutive().buildCuts(NAME, SYMBOL, firstId, receivers, amounts);
        return _deploy(cuts, inits, datas);
    }

    /// @dev `cuts` plus the helper facet, with every init run in one window through {MultiInit}.
    function _deploy(FacetCut[] memory cuts, address[] memory inits, bytes[] memory datas) internal returns (address) {
        Lattice d = new Lattice();
        d.initialize(_withHelper(cuts), address(new MultiInit()), abi.encodeCall(MultiInit.multiInit, (inits, datas)));
        return address(d);
    }

    /// @dev Expects `initialize` to revert with `revertData`.
    function _expectDeployRevert(
        FacetCut[] memory cuts,
        address[] memory inits,
        bytes[] memory datas,
        bytes memory revertData
    ) internal {
        Lattice d = new Lattice();
        FacetCut[] memory all = _withHelper(cuts);
        address multiInit = address(new MultiInit());
        vm.expectRevert(revertData);
        d.initialize(all, multiInit, abi.encodeCall(MultiInit.multiInit, (inits, datas)));
    }

    function _withHelper(FacetCut[] memory cuts) internal returns (FacetCut[] memory all) {
        bytes4[] memory sels = new bytes4[](4);
        sels[0] = ERC721TestFacet.mint.selector;
        sels[1] = ERC721TestFacet.burnRaw.selector;
        sels[2] = ERC721TestFacet.transfer.selector;
        sels[3] = ERC721TestFacet.consecutiveMint.selector;
        all = new FacetCut[](cuts.length + 1);
        for (uint256 i; i < cuts.length; ++i) {
            all[i] = cuts[i];
        }
        all[cuts.length] = FacetCut({
            facetAddress: address(new ERC721TestFacet()), action: FacetCutAction.Add, functionSelectors: sels
        });
    }

    /// @dev `inits`/`datas` followed by `extra` with `extraData`.
    function _append(address[] memory inits, bytes[] memory datas, address extra, bytes memory extraData)
        internal
        pure
        returns (address[] memory allInits, bytes[] memory allDatas)
    {
        allInits = new address[](inits.length + 1);
        allDatas = new bytes[](datas.length + 1);
        for (uint256 i; i < inits.length; ++i) {
            (allInits[i], allDatas[i]) = (inits[i], datas[i]);
        }
        (allInits[inits.length], allDatas[inits.length]) = (extra, extraData);
    }

    function _consecutiveInitData(uint96 firstId, address to, uint96 amount) internal pure returns (bytes memory) {
        address[] memory receivers = new address[](1);
        receivers[0] = to;
        uint96[] memory amounts = new uint96[](1);
        amounts[0] = amount;
        return abi.encodeCall(ERC721ConsecutiveInit.init, (firstId, receivers, amounts));
    }

    function _oneBatch(address to, uint96 amount)
        internal
        pure
        returns (address[] memory receivers, uint96[] memory amounts)
    {
        receivers = new address[](1);
        receivers[0] = to;
        amounts = new uint96[](1);
        amounts[0] = amount;
    }
}

/// @title ERC721ConsecutiveOffsetTest
/// @notice Ports OpenZeppelin v5.6.1's `ERC721Consecutive.test.js` "with offset" suite: the same six batches (two of
///         them empty), minted in the diamond's first initialization from `_offset()`. The voting-power half of the
///         upstream balance test is not ported: batch mints and {ERC721Votes} do not compose here (see
///         CompositionHazardsTest).
abstract contract ERC721ConsecutiveOffsetTest is ERC721ConsecutiveTestBase {
    uint96 internal constant TOTAL = 15;

    address internal diamond;
    IERC721 internal token;
    ERC721TestFacet internal helper;

    uint256[] internal eventFrom;
    uint256[] internal eventTo;
    address[] internal eventOwner;
    uint256 internal transferEvents;

    function _offset() internal pure virtual returns (uint96);

    function _batches() internal view returns (address[] memory receivers, uint96[] memory amounts) {
        receivers = new address[](6);
        (receivers[0], receivers[1], receivers[2], receivers[3], receivers[4], receivers[5]) =
        (alice, alice, alice, bruce, chris, alice);
        amounts = new uint96[](6);
        (amounts[0], amounts[1], amounts[2], amounts[3], amounts[4], amounts[5]) = (0, 1, 2, 5, 0, 7);
    }

    function setUp() public {
        (address[] memory receivers, uint96[] memory amounts) = _batches();
        vm.recordLogs();
        diamond = _deployConsecutive(_offset(), receivers, amounts);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != diamond) continue;
            if (logs[i].topics[0] == IERC2309.ConsecutiveTransfer.selector) {
                eventFrom.push(uint256(logs[i].topics[1]));
                eventTo.push(abi.decode(logs[i].data, (uint256)));
                assertEq(address(uint160(uint256(logs[i].topics[2]))), address(0), "from the zero address");
                eventOwner.push(address(uint160(uint256(logs[i].topics[3]))));
            } else if (logs[i].topics[0] == IERC721.Transfer.selector) {
                ++transferEvents;
            }
        }
        token = IERC721(diamond);
        helper = ERC721TestFacet(diamond);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       MINTING DURING INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    function test_EventsAreEmittedAtInitialization() public view {
        (address[] memory receivers, uint96[] memory amounts) = _batches();
        uint256 first = _offset();
        uint256 n;
        for (uint256 i; i < receivers.length; ++i) {
            if (amounts[i] == 0) continue;
            assertEq(eventFrom[n], first, "fromTokenId");
            assertEq(eventTo[n], first + amounts[i] - 1, "toTokenId");
            assertEq(eventOwner[n], receivers[i], "toAddress");
            first += amounts[i];
            ++n;
        }
        assertEq(eventFrom.length, n, "one event per non-empty batch");
        assertEq(transferEvents, 0, "no per-token Transfer");
    }

    function test_OwnershipIsSet() public view {
        (address[] memory receivers, uint96[] memory amounts) = _batches();
        uint256 id = _offset();
        for (uint256 i; i < receivers.length; ++i) {
            for (uint256 j; j < amounts[i]; ++j) {
                assertEq(token.ownerOf(id++), receivers[i], "batch owner");
            }
        }
    }

    function test_BalancesAreSet() public view {
        assertEq(token.balanceOf(alice), 10, "alice");
        assertEq(token.balanceOf(bruce), 5, "bruce");
        assertEq(token.balanceOf(chris), 0, "chris");
        assertEq(token.balanceOf(receiver), 0, "receiver");
    }

    function test_RevertWhen_BatchMintsToZeroAddress() public {
        (address[] memory receivers, uint96[] memory amounts) = _oneBatch(address(0), 10);
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory datas) =
            new DeployERC721Consecutive().buildCuts(NAME, SYMBOL, _offset(), receivers, amounts);
        _expectDeployRevert(
            cuts, inits, datas, abi.encodeWithSelector(IERC721.ERC721InvalidReceiver.selector, address(0))
        );
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                       MINTING AFTER INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    function test_RevertWhen_BatchMintAfterInitialization() public {
        vm.expectRevert(IERC721Consecutive.ERC721ForbiddenBatchMint.selector);
        helper.consecutiveMint(alice, 10);
    }

    /// @notice An empty batch is a no-op upstream too: it returns the next id without checking the window.
    function test_EmptyBatchAfterInitializationReturnsNextId() public {
        assertEq(helper.consecutiveMint(alice, 0), _offset() + TOTAL);
    }

    function test_SingleMintAfterInitialization() public {
        uint256 tokenId = _offset() + TOTAL;
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, tokenId));
        token.ownerOf(tokenId);

        vm.expectEmit(true, true, true, true, diamond);
        emit IERC721.Transfer(address(0), alice, tokenId);
        helper.mint(alice, tokenId);
        assertEq(token.ownerOf(tokenId), alice);
        assertEq(token.balanceOf(alice), 11);
    }

    function test_RevertWhen_MintingABatchMintedToken() public {
        uint256 tokenId = _offset() + TOTAL - 1;
        assertEq(token.ownerOf(tokenId), alice);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InvalidSender.selector, address(0)));
        helper.mint(alice, tokenId);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             ERC-721 BEHAVIOR
    //////////////////////////////////////////////////////////////////////////*//

    function test_CoreTakesOverOwnershipOnTransfer() public {
        uint256 tokenId = _offset() + 1;
        vm.prank(alice);
        token.transferFrom(alice, receiver, tokenId);
        assertEq(token.ownerOf(tokenId), receiver);
        assertEq(token.balanceOf(alice), 9);
        assertEq(token.balanceOf(receiver), 1);
        assertEq(token.ownerOf(tokenId + 1), alice, "the neighbour keeps its batch owner");
    }

    function test_ApproveAndOperatorWorkOnBatchTokens() public {
        uint256 tokenId = _offset() + 2;
        vm.prank(alice);
        token.approve(bruce, tokenId);
        assertEq(token.getApproved(tokenId), bruce);
        vm.prank(bruce);
        token.safeTransferFrom(alice, receiver, tokenId);
        assertEq(token.ownerOf(tokenId), receiver);
        assertEq(token.getApproved(tokenId), address(0), "approval cleared");
    }

    function test_BurnAndRemintBatchToken() public {
        uint256 tokenId = _offset() + 1;
        vm.expectEmit(true, true, true, true, diamond);
        emit IERC721.Transfer(alice, address(0), tokenId);
        helper.burnRaw(tokenId);

        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, tokenId));
        token.ownerOf(tokenId);
        assertEq(token.balanceOf(alice), 9);

        vm.expectEmit(true, true, true, true, diamond);
        emit IERC721.Transfer(address(0), bruce, tokenId);
        helper.mint(bruce, tokenId);
        assertEq(token.ownerOf(tokenId), bruce);
    }

    function test_BurnAndRemintTokenPastTheBatches() public {
        uint256 tokenId = _offset() + TOTAL;
        helper.mint(alice, tokenId);
        assertEq(token.ownerOf(tokenId), alice);

        helper.burnRaw(tokenId);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, tokenId));
        token.ownerOf(tokenId);

        helper.mint(bruce, tokenId);
        assertEq(token.ownerOf(tokenId), bruce);
    }

    /// @notice A transferred batch token lives in `_owners`; burning it zeroes that entry, and only the burn bitmap
    ///         keeps the batch checkpoint from answering for it again.
    function test_BurnAfterTransferStaysBurned() public {
        uint256 tokenId = _offset() + 4;
        vm.prank(bruce);
        token.transferFrom(bruce, receiver, tokenId);
        helper.burnRaw(tokenId);

        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, tokenId));
        token.ownerOf(tokenId);
        assertEq(token.balanceOf(bruce), 4);
        assertEq(token.balanceOf(receiver), 0);
    }

    function test_IdsOutsideTheBatchesDoNotExist() public {
        if (_offset() > 0) {
            vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, _offset() - 1));
            token.ownerOf(_offset() - 1);
        }
        uint256 past = _offset() + TOTAL;
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, past));
        token.ownerOf(past);
        uint256 huge = uint256(type(uint96).max) + 1;
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, huge));
        token.ownerOf(huge);
    }
}

contract ERC721ConsecutiveOffset0Test is ERC721ConsecutiveOffsetTest {
    function _offset() internal pure override returns (uint96) {
        return 0;
    }
}

contract ERC721ConsecutiveOffset1Test is ERC721ConsecutiveOffsetTest {
    function _offset() internal pure override returns (uint96) {
        return 1;
    }
}

contract ERC721ConsecutiveOffset42Test is ERC721ConsecutiveOffsetTest {
    function _offset() internal pure override returns (uint96) {
        return 42;
    }
}

/// @title ERC721ConsecutiveInvalidUseTest
/// @notice OpenZeppelin's "invalid use" suite plus the Lattice-specific window rules: batches only in the diamond's
///         first initialization, never in an upgrade cut's reinitializer window.
contract ERC721ConsecutiveInvalidUseTest is ERC721ConsecutiveTestBase {
    function test_InterfaceIdIsZero() public pure {
        assertEq(type(IERC721Consecutive).interfaceId, bytes4(0), "no function, nothing to register");
    }

    function test_BatchOfExactlyMaxSize() public {
        (address[] memory receivers, uint96[] memory amounts) = _oneBatch(alice, ERC721ConsecutiveLib.MAX_BATCH_SIZE);
        IERC721 token = IERC721(_deployConsecutive(0, receivers, amounts));
        assertEq(token.balanceOf(alice), 5000);
        assertEq(token.ownerOf(4999), alice);
    }

    function test_RevertWhen_BatchLargerThan5000() public {
        (address[] memory receivers, uint96[] memory amounts) = _oneBatch(alice, 5001);
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory datas) =
            new DeployERC721Consecutive().buildCuts(NAME, SYMBOL, 0, receivers, amounts);
        _expectDeployRevert(
            cuts,
            inits,
            datas,
            abi.encodeWithSelector(IERC721Consecutive.ERC721ExceededMaxBatchMint.selector, 5001, 5000)
        );
    }

    /// @notice OpenZeppelin forbids single mints during construction; here, after {ERC721ConsecutiveInit} in the
    ///         first initialization.
    function test_RevertWhen_SingleMintDuringInitialization() public {
        (address[] memory receivers, uint96[] memory amounts) = _oneBatch(alice, 3);
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory datas) =
            new DeployERC721Consecutive().buildCuts(NAME, SYMBOL, 0, receivers, amounts);
        (inits, datas) = _append(
            inits, datas, address(new ERC721SingleMintInit()), abi.encodeCall(ERC721SingleMintInit.init, (bruce, 100))
        );
        _expectDeployRevert(cuts, inits, datas, abi.encodeWithSelector(IERC721Consecutive.ERC721ForbiddenMint.selector));
    }

    /// @notice Why no init order makes a single mint safe in the first initialization: one that runs BEFORE
    ///         {ERC721ConsecutiveInit} is not caught, and a batch covering its id counts the token twice. Mint after
    ///         `initialize` returns.
    function test_SingleMintBeforeConsecutiveInitDoubleCounts() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory datas) =
            new DeployERC721Consecutive().buildCuts(NAME, SYMBOL, 0, new address[](0), new uint96[](0));
        address[] memory reordered = new address[](3);
        bytes[] memory reorderedData = new bytes[](3);
        (reordered[0], reorderedData[0]) = (inits[0], datas[0]);
        (reordered[1], reorderedData[1]) =
        (address(new ERC721SingleMintInit()), abi.encodeCall(ERC721SingleMintInit.init, (bruce, 1)));
        (reordered[2], reorderedData[2]) = (inits[1], _consecutiveInitData(0, alice, 3));
        IERC721 token = IERC721(_deploy(cuts, reordered, reorderedData));

        assertEq(token.ownerOf(1), bruce, "the stored owner wins");
        assertEq(token.balanceOf(bruce) + token.balanceOf(alice), 4, "four balances for three ids");
    }

    /// @notice A batch without {ERC721ConsecutiveLib.__ERC721Consecutive_init} reverts even inside the first
    ///         initialization: the `_enabled` check, not only the window check, gates `_mintConsecutive`.
    function test_RevertWhen_BatchMintWithoutConsecutiveInit() public {
        (FacetCut[] memory cuts, address init, bytes memory data) = new DeployERC721().buildCuts(NAME, SYMBOL);
        address[] memory inits = new address[](2);
        bytes[] memory datas = new bytes[](2);
        (inits[0], datas[0]) = (init, data);
        (inits[1], datas[1]) =
        (address(new ERC721BatchWithoutInit()), abi.encodeCall(ERC721BatchWithoutInit.init, (alice, 3)));
        _expectDeployRevert(
            cuts, inits, datas, abi.encodeWithSelector(IERC721Consecutive.ERC721ForbiddenBatchMint.selector)
        );
    }

    /// @notice ERC721Votes added by a later upgrade cut to a batch-minting diamond reverts too, as
    ///         {ERC721EnumerableLib.__ERC721Enumerable_init} does for enumeration.
    function test_RevertWhen_VotesInitInUpgradeCutAfterBatchMint() public {
        address admin = makeAddr("admin");
        (address[] memory receivers, uint96[] memory amounts) = _oneBatch(alice, 3);
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory datas) =
            new DeployERC721Consecutive().buildCuts(NAME, SYMBOL, 0, receivers, amounts, admin);
        address diamond = _deploy(cuts, inits, datas);
        ERC721ConsecutiveReinit reinit = new ERC721ConsecutiveReinit();
        address votesInit = address(new ERC721VotesInit());

        vm.prank(admin);
        vm.expectRevert(IERC721Consecutive.ERC721VotesForbiddenBatchMint.selector);
        IDiamondCut(diamond)
            .diamondCut(new FacetCut[](0), address(reinit), abi.encodeCall(reinit.votes, (votesInit, NAME)));
    }

    /// @notice OpenZeppelin: "consecutive mint not compatible with enumerability".
    function test_RevertWhen_BatchMintOnEnumerableDiamond() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory datas) =
            new DeployERC721Enumerable().buildCuts(NAME, SYMBOL);
        (inits, datas) =
            _append(inits, datas, address(new ERC721ConsecutiveInit()), _consecutiveInitData(0, alice, 100));
        _expectDeployRevert(
            cuts, inits, datas, abi.encodeWithSelector(IERC721Enumerable.ERC721EnumerableForbiddenBatchMint.selector)
        );
    }

    /// @notice The other init order: enumeration initialized after batch minting reverts too.
    function test_RevertWhen_EnumerableInitAfterBatchMint() public {
        (address[] memory receivers, uint96[] memory amounts) = _oneBatch(alice, 3);
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory datas) =
            new DeployERC721Consecutive().buildCuts(NAME, SYMBOL, 0, receivers, amounts);
        (inits, datas) =
            _append(inits, datas, address(new ERC721EnumerableInit()), abi.encodeCall(ERC721EnumerableInit.init, ()));
        _expectDeployRevert(
            cuts, inits, datas, abi.encodeWithSelector(IERC721Enumerable.ERC721EnumerableForbiddenBatchMint.selector)
        );
    }

    function test_RevertWhen_InitializedTwice() public {
        (address[] memory receivers, uint96[] memory amounts) = _oneBatch(alice, 3);
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory datas) =
            new DeployERC721Consecutive().buildCuts(NAME, SYMBOL, 0, receivers, amounts);
        (inits, datas) = _append(inits, datas, inits[1], _consecutiveInitData(100, bruce, 3));
        _expectDeployRevert(cuts, inits, datas, abi.encodeWithSelector(InvalidInitialization.selector));
    }

    function test_RevertWhen_BatchLengthMismatch() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory datas) =
            new DeployERC721Consecutive().buildCuts(NAME, SYMBOL, 0, new address[](2), new uint96[](1));
        _expectDeployRevert(
            cuts,
            inits,
            datas,
            abi.encodeWithSelector(IERC721Consecutive.ERC721ConsecutiveBatchLengthMismatch.selector, 2, 1)
        );
    }

    /// @notice The documented id limit: a batch may end at `2**96 - 2`; ending at `2**96 - 1` overflows the stored
    ///         next id.
    function test_BatchesEndBelowTheLastUint96Id() public {
        uint96 max = type(uint96).max;
        (address[] memory receivers, uint96[] memory amounts) = _oneBatch(alice, 2);
        IERC721 token = IERC721(_deployConsecutive(max - 2, receivers, amounts));
        assertEq(token.ownerOf(uint256(max) - 1), alice);

        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory datas) =
            new DeployERC721Consecutive().buildCuts(NAME, SYMBOL, max - 1, receivers, amounts);
        _expectDeployRevert(cuts, inits, datas, stdError.arithmeticError);
    }

    /// @notice An upgrade cut's `_init` runs in a reinitializer window (version 2+), not the first initialization, so
    ///         it cannot batch mint, as OpenZeppelin forbids "subsequent upgrades". A single mint there is allowed.
    function test_RevertWhen_BatchMintInUpgradeCut() public {
        address admin = makeAddr("admin");
        (address[] memory receivers, uint96[] memory amounts) = _oneBatch(alice, 3);
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory datas) =
            new DeployERC721Consecutive().buildCuts(NAME, SYMBOL, 0, receivers, amounts, admin);
        address diamond = _deploy(cuts, inits, datas);
        ERC721ConsecutiveReinit reinit = new ERC721ConsecutiveReinit();

        vm.prank(admin);
        vm.expectRevert(IERC721Consecutive.ERC721ForbiddenBatchMint.selector);
        IDiamondCut(diamond).diamondCut(new FacetCut[](0), address(reinit), abi.encodeCall(reinit.batch, (bruce, 3)));

        vm.prank(admin);
        IDiamondCut(diamond).diamondCut(new FacetCut[](0), address(reinit), abi.encodeCall(reinit.single, (bruce, 3)));
        assertEq(IERC721(diamond).ownerOf(3), bruce, "a single mint in the upgrade window succeeds");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                  COMPOSITION WITH MOVEMENT EXTENSIONS (D25)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice ERC721Burnable burns a batch-minted token: `burn` reaches {ERC721Lib._update}, which marks the bit.
    function test_BurnableBurnsBatchToken() public {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory datas) =
            new DeployERC721Burnable().buildCuts(NAME, SYMBOL);
        (inits, datas) = _append(inits, datas, address(new ERC721ConsecutiveInit()), _consecutiveInitData(0, alice, 3));
        address diamond = _deploy(cuts, inits, datas);

        vm.prank(alice);
        IERC721Burnable(diamond).burn(1);
        vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, 1));
        IERC721(diamond).ownerOf(1);
        assertEq(IERC721(diamond).balanceOf(alice), 2);
        assertEq(IERC721(diamond).ownerOf(2), alice);
    }

    /// @notice ERC721Pausable gates transfers of batch-minted tokens like any other: its replaced selectors reach
    ///         {ERC721Lib._update}, whose owner lookup reads the batch checkpoints.
    function test_PausableGatesBatchTokenTransfers() public {
        address admin = makeAddr("admin");
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory datas) =
            new DeployERC721Pausable().buildCuts(NAME, SYMBOL, admin);
        (inits, datas) = _append(inits, datas, address(new ERC721ConsecutiveInit()), _consecutiveInitData(0, alice, 3));
        address diamond = _deploy(cuts, inits, datas);

        vm.prank(admin);
        IPausable(diamond).pause();
        vm.prank(alice);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        IERC721(diamond).transferFrom(alice, bruce, 1);

        vm.prank(admin);
        IPausable(diamond).unpause();
        vm.prank(alice);
        IERC721(diamond).transferFrom(alice, bruce, 1);
        assertEq(IERC721(diamond).ownerOf(1), bruce);
    }
}

/// @title ERC721ConsecutiveFuzzTest
/// @notice Ownership lookup against a reference model: random batches from a random first id, then random
///         transfers, burns and mints over the batch range and its edges. After every run each id's owner and each
///         account's balance must match the model.
contract ERC721ConsecutiveFuzzTest is ERC721ConsecutiveTestBase {
    uint256 internal constant BATCHES = 5;
    uint256 internal constant OPS = 24;

    function testFuzz_OwnershipMatchesReferenceModel(
        uint96 firstId,
        uint8[BATCHES] memory sizes,
        uint8[BATCHES] memory owners,
        uint256 seed
    ) public {
        firstId = uint96(bound(firstId, 0, type(uint96).max - 200));
        address[4] memory accounts = [alice, bruce, chris, receiver];

        address[] memory receivers = new address[](BATCHES);
        uint96[] memory amounts = new uint96[](BATCHES);
        uint256 total;
        for (uint256 i; i < BATCHES; ++i) {
            receivers[i] = accounts[owners[i] % 4];
            amounts[i] = uint96(sizes[i] % 21);
            total += amounts[i];
        }
        address diamond = _deployConsecutive(firstId, receivers, amounts);
        IERC721 token = IERC721(diamond);

        // The model covers [lo, lo + span): two ids below the batches (when they exist) and two above.
        uint256 lo = firstId >= 2 ? firstId - 2 : 0;
        uint256 span = firstId - lo + total + 2;
        address[] memory model = new address[](span);
        {
            uint256 id = firstId;
            for (uint256 i; i < BATCHES; ++i) {
                for (uint256 j; j < amounts[i]; ++j) {
                    model[id++ - lo] = receivers[i];
                }
            }
        }

        for (uint256 step; step < OPS; ++step) {
            uint256 r = uint256(keccak256(abi.encode(seed, step)));
            uint256 id = lo + r % span;
            address actor = accounts[(r >> 64) % 4];
            address owner = model[id - lo];
            uint256 op = (r >> 128) % 3;
            if (op == 0) {
                if (owner == address(0)) {
                    vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, id));
                    token.ownerOf(id);
                    continue;
                }
                vm.prank(owner);
                token.transferFrom(owner, actor, id);
                model[id - lo] = actor;
            } else if (op == 1) {
                if (owner == address(0)) {
                    vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, id));
                    ERC721TestFacet(diamond).burnRaw(id);
                    continue;
                }
                ERC721TestFacet(diamond).burnRaw(id);
                model[id - lo] = address(0);
            } else {
                if (owner != address(0)) {
                    vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721InvalidSender.selector, address(0)));
                    ERC721TestFacet(diamond).mint(actor, id);
                    continue;
                }
                ERC721TestFacet(diamond).mint(actor, id);
                model[id - lo] = actor;
            }
        }

        uint256[4] memory balances;
        for (uint256 k; k < span; ++k) {
            address expected = model[k];
            if (expected == address(0)) {
                vm.expectRevert(abi.encodeWithSelector(IERC721.ERC721NonexistentToken.selector, lo + k));
                token.ownerOf(lo + k);
            } else {
                assertEq(token.ownerOf(lo + k), expected, "owner matches the model");
                for (uint256 a; a < 4; ++a) {
                    if (accounts[a] == expected) ++balances[a];
                }
            }
        }
        for (uint256 a; a < 4; ++a) {
            assertEq(token.balanceOf(accounts[a]), balances[a], "balance matches the model");
        }
    }
}

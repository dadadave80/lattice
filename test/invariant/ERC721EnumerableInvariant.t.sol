// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC721Enumerable} from "@lattice-script/base/tokens/DeployERC721Enumerable.s.sol";
import {ERC721TestBase} from "@lattice-test/base/ERC721TestBase.sol";
import {ERC721TestFacet} from "@lattice-test/helpers/ERC721TestFacet.sol";
import {IERC721Enumerable} from "@lattice/interfaces/tokens/IERC721Enumerable.sol";
import {ERC721} from "@lattice/tokens/ERC721/ERC721.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  HANDLER
//////////////////////////////////////////////////////////////////////////*//

/// @notice Drives mint, burn and all three transfer selectors on a {DeployERC721Enumerable} diamond, and keeps a
///         ghost set of live ids with their owners.
/// @dev Inputs are bounded to valid calls (live ids, their real owner as caller, EOA receivers), so every action is
///      revert-free under `fail_on_revert`.
contract ERC721EnumerableHandler is Test {
    ERC721 public immutable token;
    ERC721TestFacet public immutable helper;

    address[4] internal _actors = [address(0xA1), address(0xA2), address(0xA3), address(0xA4)];
    uint256 internal constant ID_POOL = 32;

    uint256[] internal _live;
    mapping(uint256 id => uint256) internal _liveIndexPlusOne;
    mapping(uint256 id => address) public ghostOwner;

    constructor(address diamond) {
        token = ERC721(diamond);
        helper = ERC721TestFacet(diamond);
    }

    function actors() external view returns (address[4] memory) {
        return _actors;
    }

    function liveCount() external view returns (uint256) {
        return _live.length;
    }

    function isLive(uint256 id) external view returns (bool) {
        return _liveIndexPlusOne[id] != 0;
    }

    function mint(uint256 actorSeed, uint256 idSeed, bool safe) external {
        uint256 id = bound(idSeed, 0, ID_POOL - 1);
        if (_liveIndexPlusOne[id] != 0) return;
        address to = _actors[actorSeed % _actors.length];
        if (safe) helper.enumerableSafeMint(to, id);
        else helper.enumerableMint(to, id);
        _live.push(id);
        _liveIndexPlusOne[id] = _live.length;
        ghostOwner[id] = to;
    }

    function burn(uint256 idSeed) external {
        if (_live.length == 0) return;
        uint256 id = _live[idSeed % _live.length];
        helper.enumerableBurn(id);
        uint256 index = _liveIndexPlusOne[id] - 1;
        uint256 last = _live[_live.length - 1];
        _live[index] = last;
        _liveIndexPlusOne[last] = index + 1;
        _live.pop();
        delete _liveIndexPlusOne[id];
        delete ghostOwner[id];
    }

    /// @param mode 0 = `transferFrom`, 1 = `safeTransferFrom`, 2 = `safeTransferFrom` with data.
    function transfer(uint256 idSeed, uint256 toSeed, uint8 mode) external {
        if (_live.length == 0) return;
        uint256 id = _live[idSeed % _live.length];
        address from = ghostOwner[id];
        address to = _actors[toSeed % _actors.length];
        vm.prank(from);
        if (mode % 3 == 0) token.transferFrom(from, to, id);
        else if (mode % 3 == 1) token.safeTransferFrom(from, to, id);
        else token.safeTransferFrom(from, to, id, "data");
        ghostOwner[id] = to;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                               INVARIANT TEST
//////////////////////////////////////////////////////////////////////////*//

/// @title ERC721EnumerableInvariant
/// @notice On a recipe-built {DeployERC721Enumerable} diamond, across any sequence of mints, burns and transfers:
///         `totalSupply` equals the number of live tokens, `tokenByIndex` lists each live id exactly once, and
///         `tokenOfOwnerByIndex` walks exactly `balanceOf(owner)` distinct ids, each owned by `owner` (#236).
/// forge-config: ci.invariant.runs = 64
contract ERC721EnumerableInvariant is ERC721TestBase {
    ERC721EnumerableHandler internal handler;
    IERC721Enumerable internal enumerable;

    function setUp() public override {
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) =
            new DeployERC721Enumerable().buildCuts("Invariant NFT", "INFT");
        diamond = _deployWithHelper(cuts, inits, initCalldatas);
        token = ERC721(diamond);
        enumerable = IERC721Enumerable(diamond);

        handler = new ERC721EnumerableHandler(diamond);
        targetContract(address(handler));
    }

    /// @notice `totalSupply` equals the ghost live count and the sum of every actor's balance.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_TotalSupplyEqualsLiveTokens() public view {
        uint256 supply = enumerable.totalSupply();
        assertEq(supply, handler.liveCount(), "totalSupply != live tokens");
        address[4] memory actors = handler.actors();
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, supply, "balances do not sum to totalSupply");
    }

    /// @notice `tokenByIndex` lists each live id once, and the next index is out of bounds.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_GlobalListIsExactlyTheLiveIds() public view {
        uint256 supply = enumerable.totalSupply();
        uint256[] memory seen = new uint256[](supply);
        for (uint256 i; i < supply; ++i) {
            uint256 id = enumerable.tokenByIndex(i);
            assertTrue(handler.isLive(id), "listed id is not live");
            assertEq(token.ownerOf(id), handler.ghostOwner(id), "listed id has the wrong owner");
            for (uint256 j; j < i; ++j) {
                assertTrue(seen[j] != id, "duplicate id in the global list");
            }
            seen[i] = id;
        }
        (bool ok,) = diamond.staticcall(abi.encodeCall(IERC721Enumerable.tokenByIndex, (supply)));
        assertFalse(ok, "tokenByIndex(totalSupply) must revert");
    }

    /// @notice Each owner's list walks exactly `balanceOf(owner)` distinct ids, all owned by that owner.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_OwnerListsWalkTheirBalance() public view {
        address[4] memory actors = handler.actors();
        for (uint256 a; a < actors.length; ++a) {
            address owner = actors[a];
            uint256 balance = token.balanceOf(owner);
            uint256[] memory seen = new uint256[](balance);
            for (uint256 i; i < balance; ++i) {
                uint256 id = enumerable.tokenOfOwnerByIndex(owner, i);
                assertEq(token.ownerOf(id), owner, "owner list holds an id the owner does not own");
                for (uint256 j; j < i; ++j) {
                    assertTrue(seen[j] != id, "duplicate id in an owner list");
                }
                seen[i] = id;
            }
            (bool ok,) = diamond.staticcall(abi.encodeCall(IERC721Enumerable.tokenOfOwnerByIndex, (owner, balance)));
            assertFalse(ok, "tokenOfOwnerByIndex(owner, balance) must revert");
        }
    }
}

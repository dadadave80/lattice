// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MultiInit} from "@diamond/initializers/MultiInit.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC1155Supply} from "@lattice-script/base/tokens/DeployERC1155Supply.s.sol";
import {ERC1155SupplyTestFacet} from "@lattice-test/helpers/ERC1155SupplyTestFacet.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {IERC1155} from "@lattice/interfaces/tokens/IERC1155.sol";
import {IERC1155Burnable} from "@lattice/interfaces/tokens/IERC1155Burnable.sol";
import {IERC1155Supply} from "@lattice/interfaces/tokens/IERC1155Supply.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  HANDLER
//////////////////////////////////////////////////////////////////////////*//

/// @notice Drives every supply-moving and balance-moving path of a recipe-built {ERC1155Supply} diamond: single and
///         batch mints (through {ERC1155SupplyTestFacet}, which mints via {ERC1155SupplyLib}), single and batch
///         burns (the facet's `burn`/`burnBatch`), and single and batch transfers (the base facet), over a fixed set
///         of 4 actors and 3 ids.
/// @dev Inputs are bounded to valid calls, so every action is revert-free under `fail_on_revert`. Mint values are
///      capped so no counter can overflow within a run.
contract ERC1155SupplyHandler is Test {
    address public immutable token;

    uint256 public constant ID_COUNT = 3;
    uint256 internal constant CAP = 1e30;

    address[4] internal _actors;

    /// @notice Per-id ledger of everything minted and burned through the handler.
    mapping(uint256 id => uint256) public ghostMinted;
    mapping(uint256 id => uint256) public ghostBurned;

    constructor(address token_) {
        token = token_;
        _actors[0] = address(0xA1);
        _actors[1] = address(0xA2);
        _actors[2] = address(0xA3);
        _actors[3] = address(0xA4);
    }

    function actors() external view returns (address[4] memory) {
        return _actors;
    }

    function mint(uint256 actorSeed, uint256 idSeed, uint256 value) external {
        uint256 id = idSeed % ID_COUNT;
        value = bound(value, 0, CAP);
        ERC1155SupplyTestFacet(token).mint(_actor(actorSeed), id, value, "");
        ghostMinted[id] += value;
    }

    function mintBatch(uint256 actorSeed, uint256 idSeed, uint256 a, uint256 b) external {
        (uint256[] memory ids, uint256[] memory values) = _twoIds(idSeed, bound(a, 0, CAP), bound(b, 0, CAP));
        ERC1155SupplyTestFacet(token).mintBatch(_actor(actorSeed), ids, values, "");
        ghostMinted[ids[0]] += values[0];
        ghostMinted[ids[1]] += values[1];
    }

    function burn(uint256 actorSeed, uint256 idSeed, uint256 value) external {
        address from = _actor(actorSeed);
        uint256 id = idSeed % ID_COUNT;
        value = bound(value, 0, IERC1155(token).balanceOf(from, id));
        vm.prank(from);
        IERC1155Burnable(token).burn(from, id, value);
        ghostBurned[id] += value;
    }

    function burnBatch(uint256 actorSeed, uint256 idSeed, uint256 a, uint256 b) external {
        address from = _actor(actorSeed);
        (uint256[] memory ids,) = _twoIds(idSeed, 0, 0);
        uint256[] memory values = new uint256[](2);
        values[0] = bound(a, 0, IERC1155(token).balanceOf(from, ids[0]));
        values[1] = bound(b, 0, IERC1155(token).balanceOf(from, ids[1]));
        vm.prank(from);
        IERC1155Burnable(token).burnBatch(from, ids, values);
        ghostBurned[ids[0]] += values[0];
        ghostBurned[ids[1]] += values[1];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 idSeed, uint256 value) external {
        address from = _actor(fromSeed);
        uint256 id = idSeed % ID_COUNT;
        value = bound(value, 0, IERC1155(token).balanceOf(from, id));
        vm.prank(from);
        IERC1155(token).safeTransferFrom(from, _actor(toSeed), id, value, "");
    }

    function batchTransfer(uint256 fromSeed, uint256 toSeed, uint256 idSeed, uint256 a, uint256 b) external {
        address from = _actor(fromSeed);
        (uint256[] memory ids,) = _twoIds(idSeed, 0, 0);
        uint256[] memory values = new uint256[](2);
        values[0] = bound(a, 0, IERC1155(token).balanceOf(from, ids[0]));
        values[1] = bound(b, 0, IERC1155(token).balanceOf(from, ids[1]));
        vm.prank(from);
        IERC1155(token).safeBatchTransferFrom(from, _actor(toSeed), ids, values, "");
    }

    function _actor(uint256 seed) internal view returns (address) {
        return _actors[seed % _actors.length];
    }

    /// @dev Two distinct ids, so a batch burn's per-id bound is the whole balance it may debit.
    function _twoIds(uint256 idSeed, uint256 a, uint256 b)
        internal
        pure
        returns (uint256[] memory ids, uint256[] memory values)
    {
        ids = new uint256[](2);
        ids[0] = idSeed % ID_COUNT;
        ids[1] = (ids[0] + 1) % ID_COUNT;
        values = new uint256[](2);
        values[0] = a;
        values[1] = b;
    }
}

//*//////////////////////////////////////////////////////////////////////////
//                               INVARIANT TEST
//////////////////////////////////////////////////////////////////////////*//

/// @title ERC1155SupplyInvariant
/// @notice #237's Supply invariant on a diamond built by the {DeployERC1155Supply} recipe: across mint, burn and
///         transfer, `totalSupply()` equals the sum of `totalSupply(id)`, each `totalSupply(id)` equals the sum of
///         holder balances (and the handler's mint-minus-burn ledger), and `exists(id)` is `totalSupply(id) > 0`.
/// forge-config: ci.invariant.runs = 64
contract ERC1155SupplyInvariant is Test {
    address internal token;
    ERC1155SupplyHandler internal handler;

    function setUp() public {
        (FacetCut[] memory prod, address[] memory inits, bytes[] memory cds) =
            new DeployERC1155Supply().buildCuts("uri://");

        bytes4[] memory helperSelectors = new bytes4[](2);
        helperSelectors[0] = ERC1155SupplyTestFacet.mint.selector;
        helperSelectors[1] = ERC1155SupplyTestFacet.mintBatch.selector;
        FacetCut[] memory cuts = new FacetCut[](prod.length + 1);
        for (uint256 i; i < prod.length; ++i) {
            cuts[i] = prod[i];
        }
        cuts[prod.length] = FacetCut({
            facetAddress: address(new ERC1155SupplyTestFacet()),
            action: FacetCutAction.Add,
            functionSelectors: helperSelectors
        });

        MultiInit multiInit = new MultiInit();
        Lattice d = new Lattice();
        d.initialize(cuts, address(multiInit), abi.encodeCall(MultiInit.multiInit, (inits, cds)));
        token = address(d);

        handler = new ERC1155SupplyHandler(token);
        targetContract(address(handler));
    }

    /// @notice `totalSupply()` is the sum of `totalSupply(id)` over every id.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_TotalSupplyIsSumOfIdSupplies() public view {
        uint256 sum;
        for (uint256 id; id < handler.ID_COUNT(); ++id) {
            sum += IERC1155Supply(token).totalSupply(id);
        }
        assertEq(IERC1155Supply(token).totalSupply(), sum, "totalSupply() != sum of totalSupply(id)");
    }

    /// @notice Each `totalSupply(id)` is the sum of the holders' balances of `id`.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_IdSupplyIsSumOfBalances() public view {
        address[4] memory actors = handler.actors();
        for (uint256 id; id < handler.ID_COUNT(); ++id) {
            uint256 sum;
            for (uint256 i; i < actors.length; ++i) {
                sum += IERC1155(token).balanceOf(actors[i], id);
            }
            assertEq(IERC1155Supply(token).totalSupply(id), sum, "totalSupply(id) != sum of balances");
        }
    }

    /// @notice Each `totalSupply(id)` is everything minted minus everything burned for `id`.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_IdSupplyMatchesLedger() public view {
        for (uint256 id; id < handler.ID_COUNT(); ++id) {
            assertEq(
                IERC1155Supply(token).totalSupply(id),
                handler.ghostMinted(id) - handler.ghostBurned(id),
                "totalSupply(id) != minted - burned"
            );
        }
    }

    /// @notice `exists(id)` is exactly `totalSupply(id) > 0`.
    /// forge-config: default.invariant.fail-on-revert = true
    function invariant_ExistsMatchesSupply() public view {
        for (uint256 id; id < handler.ID_COUNT(); ++id) {
            assertEq(IERC1155Supply(token).exists(id), IERC1155Supply(token).totalSupply(id) > 0, "exists mismatch");
        }
    }
}

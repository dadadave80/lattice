// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MultiInit} from "@diamond/initializers/MultiInit.sol";
import {IDiamondCut} from "@diamond/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {CannotAddFunctionToDiamondThatAlreadyExists, FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {OwnableLib} from "@diamond/libraries/OwnableLib.sol";
import {DeployAccessManager} from "@lattice-script/base/access/DeployAccessManager.s.sol";
import {DeployBridgeERC20} from "@lattice-script/base/crosschain/DeployBridgeERC20.s.sol";
import {DeployGovernedDiamondCut} from "@lattice-script/base/governance/DeployGovernedDiamondCut.s.sol";
import {DeployGovernedSafeDiamondCut} from "@lattice-script/base/governance/DeployGovernedSafeDiamondCut.s.sol";
import {DeployChainlinkAdapter} from "@lattice-script/base/oracles/DeployChainlinkAdapter.s.sol";
import {DeployChainlinkVRF} from "@lattice-script/base/oracles/DeployChainlinkVRF.s.sol";
import {DeployERC1155Pausable} from "@lattice-script/base/tokens/DeployERC1155Pausable.s.sol";
import {DeployERC1155Supply} from "@lattice-script/base/tokens/DeployERC1155Supply.s.sol";
import {DeployERC20Capped} from "@lattice-script/base/tokens/DeployERC20Capped.s.sol";
import {DeployERC20Pausable} from "@lattice-script/base/tokens/DeployERC20Pausable.s.sol";
import {DeployERC20Votes} from "@lattice-script/base/tokens/DeployERC20Votes.s.sol";
import {DeployERC4626} from "@lattice-script/base/tokens/DeployERC4626.s.sol";
import {DeployERC721} from "@lattice-script/base/tokens/DeployERC721.s.sol";
import {ERC1155PausableTestFacet} from "@lattice-test/helpers/ERC1155PausableTestFacet.sol";
import {ERC1155SupplyTestFacet} from "@lattice-test/helpers/ERC1155SupplyTestFacet.sol";
import {ERC1155TestFacet} from "@lattice-test/helpers/ERC1155TestFacet.sol";
import {ERC20VotesTestFacet} from "@lattice-test/helpers/ERC20VotesTestFacet.sol";
import {TokenTestFacet} from "@lattice-test/helpers/TokenTestFacet.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessManager} from "@lattice/access/AccessManager.sol";
import {AccessManagerInit} from "@lattice/access/AccessManagerInit.sol";
import {BridgeERC20} from "@lattice/crosschain/BridgeERC20.sol";
import {BridgeERC20Init} from "@lattice/crosschain/BridgeERC20Init.sol";
import {CrosschainLink} from "@lattice/crosschain/CrosschainLink.sol";
import {CrosschainTimelockHandler} from "@lattice/crosschain/CrosschainTimelockHandler.sol";
import {GovernedVault} from "@lattice/defi/GovernedVault.sol";
import {GovernedDiamondCutInit} from "@lattice/governance/GovernedDiamondCutInit.sol";
import {TimelockController} from "@lattice/governance/TimelockController.sol";
import {Votes} from "@lattice/governance/Votes.sol";
import {UPGRADE_EXECUTOR_ROLE} from "@lattice/governance/libraries/GovernedDiamondCutLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IAccessManager} from "@lattice/interfaces/access/IAccessManager.sol";
import {IBridgeFungible} from "@lattice/interfaces/crosschain/IBridgeFungible.sol";
import {ICrosschainLink} from "@lattice/interfaces/crosschain/ICrosschainLink.sol";
import {IERC7786GatewaySource} from "@lattice/interfaces/external/ercs/IERC7786.sol";
import {IERC7802} from "@lattice/interfaces/external/ercs/IERC7802.sol";
import {IERC8153} from "@lattice/interfaces/external/ercs/IERC8153.sol";
import {IVotes} from "@lattice/interfaces/governance/IVotes.sol";
import {IPausable} from "@lattice/interfaces/security/IPausable.sol";
import {IERC1155} from "@lattice/interfaces/tokens/IERC1155.sol";
import {IERC1155Burnable} from "@lattice/interfaces/tokens/IERC1155Burnable.sol";
import {IERC1155Supply} from "@lattice/interfaces/tokens/IERC1155Supply.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC20Capped} from "@lattice/interfaces/tokens/IERC20Capped.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";
import {IVestingWallet} from "@lattice/interfaces/utils/IVestingWallet.sol";
import {PythAdapter} from "@lattice/oracles/pyth/PythAdapter.sol";
import {PythEntropyAdapter} from "@lattice/oracles/pyth/PythEntropyAdapter.sol";
import {Pausable} from "@lattice/security/Pausable.sol";
import {ERC1155} from "@lattice/tokens/ERC1155/ERC1155.sol";
import {ERC1155Burnable} from "@lattice/tokens/ERC1155/ERC1155Burnable.sol";
import {ERC1155Pausable} from "@lattice/tokens/ERC1155/ERC1155Pausable.sol";
import {ERC1155Supply} from "@lattice/tokens/ERC1155/ERC1155Supply.sol";
import {ERC20Burnable} from "@lattice/tokens/ERC20/ERC20Burnable.sol";
import {ERC20Pausable} from "@lattice/tokens/ERC20/ERC20Pausable.sol";
import {ERC20Votes} from "@lattice/tokens/ERC20/ERC20Votes.sol";
import {ERC20VotesInit} from "@lattice/tokens/ERC20/ERC20VotesInit.sol";
import {ERC7802} from "@lattice/tokens/ERC7802/ERC7802.sol";
import {CROSSCHAIN_BRIDGE_ROLE} from "@lattice/tokens/ERC7802/libraries/ERC7802Lib.sol";
import {VestingWallet} from "@lattice/utils/VestingWallet.sol";
import {InteroperableAddress} from "@lattice/utils/libraries/InteroperableAddress.sol";
import {VestingWalletLib} from "@lattice/utils/libraries/VestingWalletLib.sol";
import {Test} from "forge-std/Test.sol";

/// @dev A facet a test cuts in, to prove a cut landed.
contract HazardProbeFacet {
    function hazardProbe() external pure returns (uint256) {
        return 240;
    }
}

/// @dev Seeds the VestingWallet storage the custody test needs: the beneficiary (the ERC-173 owner) and schedule.
contract HazardVestingInit {
    function init(address beneficiary, uint64 start, uint64 duration) external {
        OwnableLib.setOwner(beneficiary);
        VestingWalletLib.__VestingWallet_init(start, duration);
    }
}

/// @dev Minimal ERC-20 asset for the custody test.
contract HazardAsset {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    uint256 public totalSupply;

    function decimals() external pure returns (uint8) {
        return 18;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

/// @dev ERC-7786 gateway that accepts every message, for the bridge escrow test.
contract HazardGateway is IERC7786GatewaySource {
    function supportsAttribute(bytes4) external pure returns (bool) {
        return false;
    }

    function sendMessage(bytes calldata, bytes calldata, bytes[] calldata) external payable returns (bytes32) {
        return bytes32(uint256(240));
    }
}

/// @title CompositionHazardsTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Pins TODAY's behaviour of the co-cut hazards documented in the guide's "Composition hazards" section
///         (#240), each on a diamond built from the production recipe. These are characterization tests, not
///         fixes: a test here fails when the behaviour changes, and the guide and NatSpec must change with it.
///         The guardian-liveness trust (D10) is already pinned by
///         `GovernedVaultUpgradeTest.test_GuardianTrustedForLivenessUntilFrozen`, and the full selector matrix by
///         {SelectorCompatibilityTest}.
contract CompositionHazardsTest is Test {
    address internal admin = makeAddr("admin");
    address internal amAdmin = makeAddr("accessManagerAdmin");
    address internal stranger = makeAddr("stranger");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    //*//////////////////////////////////////////////////////////////////////////
    //                  1. ONE IN-DIAMOND ERC-7786 HANDLER PER LINK
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice A link diamond hosts one handler facet: every handler exports `processMessage` (`0x902d5027`), so
    ///         adding CrosschainTimelockHandler to the BridgeERC20 recipe reverts at cut time.
    function test_SecondHandlerFacetRevertsAtCut() public {
        (FacetCut[] memory base, address init, bytes memory data) =
            new DeployBridgeERC20().buildCuts(admin, address(new HazardAsset()));
        FacetCut[] memory cuts = _append(base, _add(address(new CrosschainTimelockHandler())));
        _expectCutClash(cuts, init, data, 0x902d5027);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                      2. SELECTOR CLASHES AT CUT TIME
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice One price adapter per diamond: the adapters share `getFeed`/`latestAnswer`/... over separate
    ///         storage, so a second adapter reverts at cut time.
    function test_SecondPriceAdapterRevertsAtCut() public {
        (FacetCut[] memory base, address init, bytes memory data) = new DeployChainlinkAdapter().buildCuts(admin);
        FacetCut[] memory cuts = _append(base, _add(address(new PythAdapter())));
        _expectCutClash(cuts, init, data, _firstClash(base, cuts[cuts.length - 1]));
    }

    /// @notice Standard-imposed: ERC-721 and ERC-1155 share the approval-for-all pair over separate storage.
    function test_ERC721AndERC1155ClashAtCut() public {
        (FacetCut[] memory base, address init, bytes memory data) = new DeployERC721().buildCuts("N", "S");
        FacetCut[] memory cuts = _append(base, _add(address(new ERC1155())));
        bytes4 clash = _firstClash(base, cuts[cuts.length - 1]);
        assertTrue(clash == 0xa22cb465 || clash == 0xe985e9c5, "an approval-for-all selector clashes");
        _expectCutClash(cuts, init, data, clash);
    }

    /// @notice Lattice-chosen: GovernedSafeDiamondCut's operation views (ERC-165 id `0xacb1aeb6`) reuse
    ///         TimelockController's names with different meaning, so the two cannot share a diamond.
    function test_GovernedSafeCutAndTimelockClashAtCut() public {
        (FacetCut[] memory base, address init, bytes memory data) =
            new DeployGovernedSafeDiamondCut().buildCuts(admin, makeAddr("safe"), 2, 1 days);
        FacetCut[] memory cuts = _append(base, _add(address(new TimelockController())));
        bytes4 clash = _firstClash(base, cuts[cuts.length - 1]);
        assertTrue(
            clash == 0x13bc9f20 || clash == 0x2ab0f529 || clash == 0x584b153e || clash == 0xd45c4435,
            "an operation view clashes"
        );
        _expectCutClash(cuts, init, data, clash);
    }

    /// @notice Lattice-chosen: `getConfig()` (`0xc3f909d4`) returns a different struct on each randomness and
    ///         automation adapter, so ChainlinkVRF and PythEntropyAdapter cannot share a diamond.
    function test_GetConfigAdaptersClashAtCut() public {
        (FacetCut[] memory base, address init, bytes memory data) = new DeployChainlinkVRF().buildCuts(admin);
        FacetCut[] memory cuts = _append(base, _add(address(new PythEntropyAdapter())));
        _expectCutClash(cuts, init, data, _firstClash(base, cuts[cuts.length - 1]));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //        3. ERC-20 MOVEMENT-REPLACING EXTENSIONS ARE MUTUALLY EXCLUSIVE (D25)
    //////////////////////////////////////////////////////////////////////////*//

    // The hook model (docs/guides/selector-compatibility.md#token-extension-hook-model): base token libraries run
    // no extension hook, an extension that gates or observes movement replaces the base movement selectors, two
    // such extensions are mutually exclusive, and a facet that moves balances through the base library directly
    // bypasses them. These tests pin each way a diamond can lose pause, vote or supply-cap accounting today.

    /// @notice D25: ERC20Pausable and ERC20Votes both own `transfer`/`transferFrom`. Adding one next to the other
    ///         reverts on `transfer` (`0xa9059cbb`).
    function test_PausableAddedToVotesRevertsAtCut() public {
        (FacetCut[] memory base, address[] memory inits, bytes[] memory datas) =
            new DeployERC20Votes().buildCuts("Token", "TKN", admin);
        FacetCut[] memory cuts = _append(base, _add(address(new ERC20Pausable())));
        (address init, bytes memory data) = _multi(inits, datas);
        _expectCutClash(cuts, init, data, 0xa9059cbb);
    }

    /// @notice D25: a `Replace` is silent. ERC20Pausable replacing ERC20Votes' transfer builds fine, pause works,
    ///         but transfers stop moving voting units, so delegated votes exceed the supply.
    function test_PausableReplacingVotesDesyncsVotes() public {
        (FacetCut[] memory base, address[] memory inits, bytes[] memory datas) =
            new DeployERC20Votes().buildCuts("Token", "TKN", admin);
        address pausableFacet = address(new ERC20Pausable());
        FacetCut[] memory cuts = _append(
            _append(_append(base, _add(address(new Pausable()))), _replace(pausableFacet)),
            _selectors(address(new ERC20VotesTestFacet()), ERC20VotesTestFacet.mint.selector)
        );
        address token = _deploy(cuts, inits, datas);
        assertEq(IDiamondLoupe(token).facetAddress(IERC20.transfer.selector), pausableFacet, "Pausable owns transfer");

        ERC20VotesTestFacet(token).mint(alice, 100e18);
        vm.prank(alice);
        IVotes(token).delegate(alice);
        vm.prank(alice);
        IERC20(token).transfer(bob, 40e18);
        vm.prank(bob);
        IVotes(token).delegate(bob);

        assertEq(IVotes(token).getVotes(alice), 100e18, "alice keeps the votes of tokens she sent");
        assertEq(IVotes(token).getVotes(bob), 40e18, "bob's delegation counts his balance");
        assertEq(IERC20(token).totalSupply(), 100e18);

        vm.prank(admin);
        IPausable(token).pause();
        vm.prank(alice);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        IERC20(token).transfer(bob, 1);
    }

    /// @notice D25, the other order: ERC20Votes replacing ERC20Pausable's transfer builds fine, but the pause
    ///         no longer gates transfers.
    function test_VotesReplacingPausableBypassesPause() public {
        (FacetCut[] memory base, address[] memory inits, bytes[] memory datas) =
            new DeployERC20Pausable().buildCuts("Token", "TKN", admin);
        address votesFacet = address(new ERC20Votes());
        FacetCut[] memory cuts = _append(
            _append(
                _append(base, _add(address(new Votes()))),
                _selectors(votesFacet, ERC20Votes.transfer.selector, ERC20Votes.transferFrom.selector)
            ),
            _selectors(address(new TokenTestFacet()), TokenTestFacet.mint.selector)
        );
        cuts[cuts.length - 2].action = FacetCutAction.Replace;
        address[] memory allInits = new address[](inits.length + 1);
        bytes[] memory allDatas = new bytes[](inits.length + 1);
        for (uint256 i; i < inits.length; ++i) {
            (allInits[i], allDatas[i]) = (inits[i], datas[i]);
        }
        allInits[inits.length] = address(new ERC20VotesInit());
        allDatas[inits.length] = abi.encodeCall(ERC20VotesInit.init, ("Token", admin));
        address token = _deploy(cuts, allInits, allDatas);
        assertEq(IDiamondLoupe(token).facetAddress(IERC20.transfer.selector), votesFacet, "Votes owns transfer");

        TokenTestFacet(token).mint(alice, 100e18);
        vm.prank(admin);
        IPausable(token).pause();
        assertTrue(IPausable(token).paused());

        vm.prank(alice);
        IERC20(token).transfer(bob, 40e18);
        assertEq(IERC20(token).balanceOf(bob), 40e18, "the transfer went through while paused");
    }

    /// @notice D25 declares the ERC-20 movement-replacing family: every facet that replaces the base movement
    ///         selectors replaces BOTH `transfer` and `transferFrom`, so any two members collide on `Add` and
    ///         only an explicit `Replace` can co-install them. A future member (an ERC-20 Supply or Enumerable
    ///         style facet) joins this list and must keep the property.
    function test_MovementReplacingFamilyClaimsTheTransferPair() public {
        address[3] memory family =
            [address(new ERC20Pausable()), address(new ERC20Votes()), address(new GovernedVault())];
        for (uint256 i; i < family.length; ++i) {
            bytes4[] memory sels = _add(family[i]).functionSelectors;
            assertTrue(_contains(sels, IERC20.transfer.selector), "member replaces transfer");
            assertTrue(_contains(sels, IERC20.transferFrom.selector), "member replaces transferFrom");
        }
    }

    /// @notice D25 hook model: base libraries run no extension hook, so a facet that moves balances through
    ///         {ERC20Lib} directly bypasses a movement-replacing extension. ERC20Burnable next to ERC20Votes shares
    ///         no selector, so the cut succeeds with no signal, and burns leave the burner's votes in place:
    ///         delegated votes exceed the supply. The two are mutually exclusive.
    function test_BurnableNextToVotesDesyncsVotes() public {
        (FacetCut[] memory base, address[] memory inits, bytes[] memory datas) =
            new DeployERC20Votes().buildCuts("Token", "TKN", admin);
        FacetCut[] memory cuts = _append(
            _append(base, _add(address(new ERC20Burnable()))),
            _selectors(address(new ERC20VotesTestFacet()), ERC20VotesTestFacet.mint.selector)
        );
        address token = _deploy(cuts, inits, datas);

        ERC20VotesTestFacet(token).mint(alice, 100e18);
        vm.prank(alice);
        IVotes(token).delegate(alice);
        vm.prank(alice);
        ERC20Burnable(token).burn(40e18);

        assertEq(IERC20(token).totalSupply(), 60e18, "the burn reduced the supply");
        assertEq(IVotes(token).getVotes(alice), 100e18, "alice keeps the votes of the tokens she burned");
        assertGt(IVotes(token).getVotes(alice), IERC20(token).totalSupply(), "votes exceed the supply");
    }

    /// @notice The same bypass for the pause: ERC20Pausable gates only the `transfer`/`transferFrom` it replaces,
    ///         so ERC20Burnable cut next to it still burns while paused (OpenZeppelin's `_update` hook would
    ///         revert). The two are mutually exclusive when a pause must also stop burns.
    function test_BurnableNextToPausableBurnsWhilePaused() public {
        (FacetCut[] memory base, address[] memory inits, bytes[] memory datas) =
            new DeployERC20Pausable().buildCuts("Token", "TKN", admin);
        FacetCut[] memory cuts = _append(
            _append(base, _add(address(new ERC20Burnable()))),
            _selectors(address(new TokenTestFacet()), TokenTestFacet.mint.selector)
        );
        address token = _deploy(cuts, inits, datas);

        TokenTestFacet(token).mint(alice, 100e18);
        vm.prank(admin);
        IPausable(token).pause();
        vm.prank(alice);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        IERC20(token).transfer(bob, 1);

        vm.prank(alice);
        ERC20Burnable(token).burn(40e18);
        assertEq(IERC20(token).totalSupply(), 60e18, "the burn went through while paused");
    }

    /// @notice D25 for a mint-gating extension: ERC20Capped checks its cap only inside the `_mint` a composing
    ///         facet calls, and exports only `cap()`, so ERC7802 cut next to the capped recipe shares no selector.
    ///         The composing mint still reverts past the cap, but `crosschainMint` calls {ERC20Lib._mint} directly
    ///         and lifts the supply over it (OpenZeppelin's `_update` hook would revert). The two are mutually
    ///         exclusive, as is every other shipped direct minter.
    function test_DirectMinterNextToCappedExceedsCap() public {
        address bridge = makeAddr("bridge");
        (FacetCut[] memory base, address[] memory inits, bytes[] memory datas) =
            new DeployERC20Capped().buildCuts("Token", "TKN", 1000e18, admin);
        FacetCut[] memory cuts = _append(
            _append(base, _add(address(new ERC7802()))),
            _selectors(address(new TokenTestFacet()), TokenTestFacet.cappedMint.selector)
        );
        address token = _deploy(cuts, inits, datas);
        vm.prank(admin);
        IAccessControl(token).grantRole(CROSSCHAIN_BRIDGE_ROLE, bridge);

        vm.expectRevert(abi.encodeWithSelector(IERC20Capped.ERC20ExceededCap.selector, 5000e18, 1000e18));
        TokenTestFacet(token).cappedMint(alice, 5000e18);

        vm.prank(bridge);
        IERC7802(token).crosschainMint(alice, 5000e18);
        assertEq(IERC20(token).totalSupply(), 5000e18, "the crosschain mint went through");
        assertGt(IERC20(token).totalSupply(), IERC20Capped(token).cap(), "the supply exceeds the cap");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //         3b. ERC-1155 BURN AND MINT PATHS ARE ONE PER DIAMOND (D25)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice D25: ERC1155Supply and ERC1155Pausable both own `burn`/`burnBatch`. Adding Supply next to the
    ///         Pausable recipe reverts on `burn` (`0xf5298aca`).
    function test_ERC1155SupplyAddedToPausableRevertsAtCut() public {
        (FacetCut[] memory base, address[] memory inits, bytes[] memory datas) =
            new DeployERC1155Pausable().buildCuts("uri://", admin);
        FacetCut[] memory cuts = _append(base, _add(address(new ERC1155Supply())));
        assertEq(_firstClash(base, cuts[cuts.length - 1]), bytes4(0xf5298aca), "burn clashes first");
        (address init, bytes memory data) = _multi(inits, datas);
        _expectCutClash(cuts, init, data, 0xf5298aca);
    }

    /// @notice D25: ERC1155Supply's burns replacing ERC1155Pausable's build fine and track supply, but the pause no
    ///         longer gates burns.
    function test_ERC1155SupplyReplacingPausableBurnsBypassesPause() public {
        (FacetCut[] memory base, address[] memory inits, bytes[] memory datas) =
            new DeployERC1155Pausable().buildCuts("uri://", admin);
        address supplyFacet = address(new ERC1155Supply());
        FacetCut memory burns =
            _selectors(supplyFacet, IERC1155Burnable.burn.selector, IERC1155Burnable.burnBatch.selector);
        burns.action = FacetCutAction.Replace;
        FacetCut[] memory cuts = _append(
            _append(_append(base, _selectors(supplyFacet, bytes4(0x18160ddd), IERC1155Supply.exists.selector)), burns),
            _selectors(address(new ERC1155SupplyTestFacet()), ERC1155SupplyTestFacet.mint.selector)
        );
        address token = _deploy(cuts, inits, datas);
        assertEq(IDiamondLoupe(token).facetAddress(IERC1155Burnable.burn.selector), supplyFacet, "Supply owns burn");

        ERC1155SupplyTestFacet(token).mint(alice, 1, 100, "");
        vm.prank(admin);
        IPausable(token).pause();

        vm.prank(alice);
        IERC1155Burnable(token).burn(alice, 1, 40);
        assertEq(IERC1155(token).balanceOf(alice, 1), 60, "the burn went through while paused");
        assertEq(IERC1155Supply(token).totalSupply(), 60);
    }

    /// @notice D25, the other order: ERC1155Pausable's burns replacing ERC1155Supply's build fine and honour the
    ///         pause, but burns stop lowering the supply, so `totalSupply` exceeds the holders' balances.
    function test_ERC1155PausableReplacingSupplyBurnsDesyncsSupply() public {
        (FacetCut[] memory base, address[] memory inits, bytes[] memory datas) =
            new DeployERC1155Supply().buildCuts("uri://", admin);
        address pausableFacet = address(new ERC1155Pausable());
        FacetCut[] memory cuts = _append(
            _append(_append(base, _add(address(new Pausable()))), _replace(pausableFacet)),
            _selectors(address(new ERC1155SupplyTestFacet()), ERC1155SupplyTestFacet.mint.selector)
        );
        address token = _deploy(cuts, inits, datas);
        assertEq(IDiamondLoupe(token).facetAddress(IERC1155Burnable.burn.selector), pausableFacet, "Pausable owns burn");

        ERC1155SupplyTestFacet(token).mint(alice, 1, 100, "");
        vm.prank(alice);
        IERC1155Burnable(token).burn(alice, 1, 40);
        assertEq(IERC1155(token).balanceOf(alice, 1), 60);
        assertEq(IERC1155Supply(token).totalSupply(1), 100, "the burn left the supply behind");

        vm.prank(admin);
        IPausable(token).pause();
        vm.prank(alice);
        vm.expectRevert(IPausable.EnforcedPause.selector);
        IERC1155Burnable(token).burn(alice, 1, 1);
    }

    /// @notice D25: ERC1155Burnable's plain burns replacing ERC1155Pausable's build fine, but the pause no longer
    ///         gates burns.
    function test_ERC1155BurnableReplacingPausableBurnsBypassesPause() public {
        (FacetCut[] memory base, address[] memory inits, bytes[] memory datas) =
            new DeployERC1155Pausable().buildCuts("uri://", admin);
        address burnableFacet = address(new ERC1155Burnable());
        FacetCut[] memory cuts = _append(
            _append(base, _replace(burnableFacet)),
            _selectors(address(new ERC1155PausableTestFacet()), ERC1155PausableTestFacet.mint.selector)
        );
        address token = _deploy(cuts, inits, datas);
        assertEq(IDiamondLoupe(token).facetAddress(IERC1155Burnable.burn.selector), burnableFacet, "Burnable owns burn");

        ERC1155PausableTestFacet(token).mint(alice, 1, 100, "");
        vm.prank(admin);
        IPausable(token).pause();

        vm.prank(alice);
        IERC1155Burnable(token).burn(alice, 1, 40);
        assertEq(IERC1155(token).balanceOf(alice, 1), 60, "the burn went through while paused");
    }

    /// @notice A mint facet that mints through the base {ERC1155Lib} ignores the pause: only
    ///         {ERC1155PausableLib._mint} is gated.
    function test_ERC1155BaseLibMintBypassesPause() public {
        (FacetCut[] memory base, address[] memory inits, bytes[] memory datas) =
            new DeployERC1155Pausable().buildCuts("uri://", admin);
        address token = _deploy(
            _append(base, _selectors(address(new ERC1155TestFacet()), ERC1155TestFacet.mint.selector)), inits, datas
        );
        vm.prank(admin);
        IPausable(token).pause();

        ERC1155TestFacet(token).mint(alice, 1, 100, "");
        assertEq(IERC1155(token).balanceOf(alice, 1), 100, "the mint went through while paused");
    }

    /// @notice A mint facet that mints through the base {ERC1155Lib} leaves the supply behind, and a later
    ///         supply-tracking burn wraps OpenZeppelin's unchecked subtraction. The same happens when
    ///         ERC1155Supply is cut into a diamond that already holds balances.
    function test_ERC1155BaseLibMintDesyncsSupplyAndBurnWraps() public {
        (FacetCut[] memory base, address[] memory inits, bytes[] memory datas) =
            new DeployERC1155Supply().buildCuts("uri://");
        address token = _deploy(
            _append(base, _selectors(address(new ERC1155TestFacet()), ERC1155TestFacet.mint.selector)), inits, datas
        );

        ERC1155TestFacet(token).mint(alice, 1, 10, "");
        assertEq(IERC1155Supply(token).totalSupply(1), 0, "the base mint is not counted");

        vm.prank(alice);
        IERC1155Burnable(token).burn(alice, 1, 10);
        assertEq(IERC1155Supply(token).totalSupply(1), type(uint256).max - 9, "the burn wrapped the id supply");
        assertEq(IERC1155Supply(token).totalSupply(), type(uint256).max - 9, "the burn wrapped the total");
        assertTrue(IERC1155Supply(token).exists(1), "a wrapped id reads as existing");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //              4. A CO-CUT ACCESSMANAGER IS ROOT (D11, #219, #240)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice D11 pins the Lattice-only guard as NOT adopted: with AccessManager cut next to GovernedDiamondCut,
    ///         an outside ADMIN_ROLE holder cuts through `execute(address(this), diamondCut(...))`. The call
    ///         arrives as the diamond, which holds UPGRADE_EXECUTOR_ROLE, so it skips the vote and the delay.
    function test_CoCutAccessManagerAdminCutsThroughSelfExecute() public {
        address diamond = _governedCutWithAccessManager();
        (FacetCut[] memory probeCut, address probe) = _probeCut();
        bytes memory cutCall = abi.encodeCall(IDiamondCut.diamondCut, (probeCut, address(0), ""));

        // The manager's admin holds no cut role of its own...
        vm.prank(amAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, amAdmin, UPGRADE_EXECUTOR_ROLE
            )
        );
        IDiamondCut(diamond).diamondCut(probeCut, address(0), "");

        // ...and a stranger cannot use the relay...
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IAccessManager.AccessManagerUnauthorizedAccount.selector, stranger, 0));
        IAccessManager(diamond).execute(diamond, cutCall);

        // ...but the admin cuts at once through the manager's self-call.
        vm.prank(amAdmin);
        IAccessManager(diamond).execute(diamond, cutCall);
        assertEq(IDiamondLoupe(diamond).facetAddress(HazardProbeFacet.hazardProbe.selector), probe, "cut applied");
        assertEq(HazardProbeFacet(diamond).hazardProbe(), 240);
    }

    /// @notice The shipped ADMIN overload of {DeployAccessManager} is not exposed: the diamond holds no
    ///         AccessControl role, so the manager's self-call cannot pass AccessControlDiamondCut.
    function test_AccessManagerRecipeAdminOverloadIsNotExposed() public {
        (FacetCut[] memory cuts, address init, bytes memory data) = new DeployAccessManager().buildCuts(amAdmin, admin);
        Lattice d = new Lattice();
        d.initialize(cuts, init, data);
        address diamond = address(d);
        (FacetCut[] memory probeCut,) = _probeCut();

        vm.prank(amAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, diamond, bytes32(0))
        );
        IAccessManager(diamond).execute(diamond, abi.encodeCall(IDiamondCut.diamondCut, (probeCut, address(0), "")));
    }

    /// @notice The same relay reaches the ERC-7786 handlers: with AccessManager cut next to BridgeERC20, the
    ///         manager's admin cannot call `processMessage` directly, but `execute(address(this), ...)` releases
    ///         the bridge's escrow to any recipient with no inbound message.
    function test_CoCutAccessManagerAdminReleasesBridgeEscrow() public {
        HazardAsset asset = new HazardAsset();
        (FacetCut[] memory base, address bridgeInit, bytes memory bridgeData) =
            new DeployBridgeERC20().buildCuts(admin, address(asset));
        FacetCut[] memory cuts = _append(base, _add(address(new AccessManager())));
        address[] memory inits = new address[](2);
        bytes[] memory datas = new bytes[](2);
        (inits[0], datas[0]) = (bridgeInit, bridgeData);
        inits[1] = address(new AccessManagerInit());
        datas[1] = abi.encodeCall(AccessManagerInit.init, (amAdmin));
        address bridge = _deploy(cuts, inits, datas);
        asset.mint(bridge, 500e18);

        bytes memory payload = abi.encode(bytes(""), abi.encodePacked(amAdmin), uint256(500e18));
        vm.prank(amAdmin);
        vm.expectRevert(abi.encodeWithSelector(IBridgeFungible.BridgeUnauthorizedCaller.selector, amAdmin));
        BridgeERC20(bridge).processMessage(bytes32(uint256(240)), "", payload);

        vm.prank(amAdmin);
        IAccessManager(bridge)
            .execute(bridge, abi.encodeCall(BridgeERC20.processMessage, (bytes32(uint256(240)), "", payload)));
        assertEq(asset.balanceOf(amAdmin), 500e18, "the escrow went to the manager's admin");
        assertEq(asset.balanceOf(bridge), 0, "the bridge's custody is gone");
    }

    /// @notice Why the guide does not offer "make the governed diamond the co-cut manager's admin": the manager
    ///         accepts its own diamond as caller only inside an `execute` already running that selector, and
    ///         `execute` to itself goes through the same check, so that admin can never configure the manager.
    function test_CoCutAccessManagerAdminedByItsDiamondIsInert() public {
        (FacetCut[] memory base, address cutInit, bytes memory cutData) =
            new DeployGovernedDiamondCut().buildCuts(admin);
        FacetCut[] memory cuts = _append(base, _add(address(new AccessManager())));
        Lattice d = new Lattice();
        address diamond = address(d);
        address[] memory inits = new address[](2);
        bytes[] memory datas = new bytes[](2);
        (inits[0], datas[0]) = (cutInit, cutData);
        inits[1] = address(new AccessManagerInit());
        datas[1] = abi.encodeCall(AccessManagerInit.init, (diamond));
        (address init, bytes memory data) = _multi(inits, datas);
        d.initialize(cuts, init, data);
        (bool isAdmin,) = IAccessManager(diamond).hasRole(0, diamond);
        assertTrue(isAdmin, "the diamond holds ADMIN_ROLE");

        // The diamond's self-call, as a timelock relays a passed proposal, is refused directly...
        bytes memory unauthorized =
            abi.encodeWithSelector(IAccessManager.AccessManagerUnauthorizedAccount.selector, diamond, uint64(0));
        vm.prank(diamond);
        vm.expectRevert(unauthorized);
        IAccessManager(diamond).grantRole(1, alice, 0);

        // ...and through `execute`.
        vm.prank(diamond);
        vm.expectRevert(unauthorized);
        IAccessManager(diamond).execute(diamond, abi.encodeCall(IAccessManager.grantRole, (1, alice, 0)));
    }

    /// @notice The recommended layout: the manager in its own authority diamond ({DeployAccessManager}) with the
    ///         governed diamond as its initial admin. Governance configures the authority, and the authority's
    ///         calls reach the governed diamond as the authority, which holds no upgrade role.
    function test_SeparateAuthorityAdminedByGovernedDiamond() public {
        (FacetCut[] memory cuts, address init, bytes memory data) = new DeployGovernedDiamondCut().buildCuts(admin);
        Lattice g = new Lattice();
        g.initialize(cuts, init, data);
        address governed = address(g);
        (cuts, init, data) = new DeployAccessManager().buildCuts(governed);
        Lattice m = new Lattice();
        m.initialize(cuts, init, data);
        address manager = address(m);

        // The governed diamond's self-call (what its timelock relays) configures the authority...
        vm.prank(governed);
        IAccessManager(manager).grantRole(1, alice, 0);
        (bool inRole,) = IAccessManager(manager).hasRole(1, alice);
        assertTrue(inRole, "governance granted a role on the authority");

        // ...and the authority cannot cut the governed diamond: it calls as itself, not as the governed diamond.
        (FacetCut[] memory probeCut,) = _probeCut();
        vm.prank(governed);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, manager, UPGRADE_EXECUTOR_ROLE
            )
        );
        IAccessManager(manager).execute(governed, abi.encodeCall(IDiamondCut.diamondCut, (probeCut, address(0), "")));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    5. ONE CUSTODIAN PER ASSET PER DIAMOND
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice VestingWallet counts the diamond's whole balance as its allocation and `release` is open, so next
    ///         to an ERC-4626 vault over the same asset, anyone can pay the depositors' assets to the beneficiary.
    function test_VestingWalletReleasesVaultDeposits() public {
        HazardAsset asset = new HazardAsset();
        address beneficiary = makeAddr("beneficiary");
        (FacetCut[] memory base, address vaultInit, bytes memory vaultData) =
            new DeployERC4626().buildCuts(address(asset), "Vault", "vTKN", 0);

        bytes4[] memory vesting = new bytes4[](4);
        vesting[0] = bytes4(keccak256("release(address)"));
        vesting[1] = bytes4(keccak256("releasable(address)"));
        vesting[2] = bytes4(keccak256("released(address)"));
        vesting[3] = IVestingWallet.end.selector;
        FacetCut[] memory cuts = _append(
            base,
            FacetCut({
                facetAddress: address(new VestingWallet()), action: FacetCutAction.Add, functionSelectors: vesting
            })
        );
        address[] memory inits = new address[](2);
        bytes[] memory datas = new bytes[](2);
        (inits[0], datas[0]) = (vaultInit, vaultData);
        inits[1] = address(new HazardVestingInit());
        datas[1] = abi.encodeCall(HazardVestingInit.init, (beneficiary, uint64(block.timestamp), 30 days));
        address vault = _deploy(cuts, inits, datas);

        asset.mint(alice, 1000e18);
        vm.startPrank(alice);
        asset.approve(vault, 1000e18);
        IERC4626(vault).deposit(1000e18, alice);
        vm.stopPrank();
        assertEq(IERC4626(vault).totalAssets(), 1000e18);

        vm.warp(block.timestamp + 30 days);
        vm.prank(stranger);
        IVestingWallet(vault).release(address(asset));

        assertEq(asset.balanceOf(beneficiary), 1000e18, "the depositors' assets vested to the beneficiary");
        assertEq(IERC4626(vault).totalAssets(), 0, "the vault is empty");
        assertEq(IERC4626(vault).previewRedeem(IERC20(vault).balanceOf(alice)), 0, "alice's shares are worthless");
    }

    /// @notice An ERC-4626 vault next to BridgeERC20 over the same asset prices the bridge's escrow into its
    ///         shares: a lock raises `totalAssets`, and a shareholder redeems the locked tokens.
    function test_VaultPricesBridgeEscrowIntoShares() public {
        HazardAsset asset = new HazardAsset();
        (FacetCut[] memory base, address vaultInit, bytes memory vaultData) =
            new DeployERC4626().buildCuts(address(asset), "Vault", "vTKN", 0);
        FacetCut[] memory cuts = _append(
            _append(_append(base, _add(address(new AccessControl()))), _add(address(new CrosschainLink()))),
            _add(address(new BridgeERC20()))
        );
        address[] memory inits = new address[](2);
        bytes[] memory datas = new bytes[](2);
        (inits[0], datas[0]) = (vaultInit, vaultData);
        inits[1] = address(new BridgeERC20Init());
        datas[1] = abi.encodeCall(BridgeERC20Init.init, (admin, address(asset)));
        address vault = _deploy(cuts, inits, datas);
        address gateway = address(new HazardGateway());
        bytes memory counterpart = InteroperableAddress.formatEvmV1(10, makeAddr("remoteBridge"));
        vm.prank(admin);
        ICrosschainLink(vault).setLink(gateway, counterpart, false);

        asset.mint(alice, 1000e18);
        vm.startPrank(alice);
        asset.approve(vault, 1000e18);
        uint256 shares = IERC4626(vault).deposit(1000e18, alice);
        vm.stopPrank();

        asset.mint(bob, 500e18);
        vm.startPrank(bob);
        asset.approve(vault, 500e18);
        IBridgeFungible(vault).crosschainTransfer(InteroperableAddress.formatEvmV1(10, bob), 500e18);
        vm.stopPrank();
        assertEq(IERC4626(vault).totalAssets(), 1500e18, "the bridge's escrow counts as vault assets");

        vm.prank(alice);
        IERC4626(vault).redeem(shares, alice, alice);
        assertApproxEqAbs(asset.balanceOf(alice), 1500e18, 1, "alice redeemed bob's locked tokens");
        assertLe(asset.balanceOf(vault), 1, "the bridge's custody is gone");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev The GovernedDiamondCut recipe plus an AccessManager facet whose ADMIN_ROLE is `amAdmin`, an outside key
    ///      that is neither the AccessControl admin nor an upgrade executor.
    function _governedCutWithAccessManager() internal returns (address) {
        (FacetCut[] memory base, address cutInit, bytes memory cutData) =
            new DeployGovernedDiamondCut().buildCuts(admin);
        FacetCut[] memory cuts = _append(base, _add(address(new AccessManager())));
        address[] memory inits = new address[](2);
        bytes[] memory datas = new bytes[](2);
        (inits[0], datas[0]) = (cutInit, cutData);
        inits[1] = address(new AccessManagerInit());
        datas[1] = abi.encodeCall(AccessManagerInit.init, (amAdmin));
        address diamond = _deploy(cuts, inits, datas);
        assertFalse(IAccessControl(diamond).hasRole(UPGRADE_EXECUTOR_ROLE, amAdmin));
        assertTrue(IAccessControl(diamond).hasRole(UPGRADE_EXECUTOR_ROLE, diamond));
        return diamond;
    }

    function _probeCut() internal returns (FacetCut[] memory cut, address probe) {
        probe = address(new HazardProbeFacet());
        cut = new FacetCut[](1);
        cut[0] = _selectors(probe, HazardProbeFacet.hazardProbe.selector);
    }

    function _deploy(FacetCut[] memory cuts, address[] memory inits, bytes[] memory datas) internal returns (address) {
        (address init, bytes memory data) = _multi(inits, datas);
        Lattice d = new Lattice();
        d.initialize(cuts, init, data);
        return address(d);
    }

    function _multi(address[] memory inits, bytes[] memory datas) internal returns (address, bytes memory) {
        return (address(new MultiInit()), abi.encodeCall(MultiInit.multiInit, (inits, datas)));
    }

    function _expectCutClash(FacetCut[] memory cuts, address init, bytes memory data, bytes4 selector) internal {
        Lattice d = new Lattice();
        vm.expectRevert(abi.encodeWithSelector(CannotAddFunctionToDiamondThatAlreadyExists.selector, selector));
        d.initialize(cuts, init, data);
    }

    /// @dev The first selector of `added`, in its order, that one of `base`'s Add cuts already carries: the
    ///      selector diamond-lib reports when `added` is cut after `base`.
    function _firstClash(FacetCut[] memory base, FacetCut memory added) internal pure returns (bytes4) {
        for (uint256 i; i < added.functionSelectors.length; ++i) {
            for (uint256 j; j < base.length; ++j) {
                if (base[j].action != FacetCutAction.Add) continue;
                for (uint256 k; k < base[j].functionSelectors.length; ++k) {
                    if (base[j].functionSelectors[k] == added.functionSelectors[i]) return added.functionSelectors[i];
                }
            }
        }
        revert("no clash");
    }

    function _add(address facet) internal pure returns (FacetCut memory) {
        bytes memory packed = IERC8153(facet).exportSelectors();
        bytes4[] memory sels = new bytes4[](packed.length / 4);
        for (uint256 i; i < sels.length; ++i) {
            bytes4 sel;
            assembly ("memory-safe") {
                sel := mload(add(add(packed, 0x20), mul(i, 4)))
            }
            sels[i] = sel;
        }
        return FacetCut({facetAddress: facet, action: FacetCutAction.Add, functionSelectors: sels});
    }

    function _replace(address facet) internal pure returns (FacetCut memory cut) {
        cut = _add(facet);
        cut.action = FacetCutAction.Replace;
    }

    function _selectors(address facet, bytes4 a) internal pure returns (FacetCut memory) {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = a;
        return FacetCut({facetAddress: facet, action: FacetCutAction.Add, functionSelectors: sels});
    }

    function _selectors(address facet, bytes4 a, bytes4 b) internal pure returns (FacetCut memory) {
        bytes4[] memory sels = new bytes4[](2);
        (sels[0], sels[1]) = (a, b);
        return FacetCut({facetAddress: facet, action: FacetCutAction.Add, functionSelectors: sels});
    }

    function _contains(bytes4[] memory sels, bytes4 sel) internal pure returns (bool) {
        for (uint256 i; i < sels.length; ++i) {
            if (sels[i] == sel) return true;
        }
        return false;
    }

    function _append(FacetCut[] memory cuts, FacetCut memory cut) internal pure returns (FacetCut[] memory out) {
        out = new FacetCut[](cuts.length + 1);
        for (uint256 i; i < cuts.length; ++i) {
            out[i] = cuts[i];
        }
        out[cuts.length] = cut;
    }
}

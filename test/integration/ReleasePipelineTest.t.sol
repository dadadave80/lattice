// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Selectors} from "@diamond-test/helpers/Selectors.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {IFacet} from "@diamond/interfaces/IFacet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployRelease} from "@lattice-script/deploy/DeployRelease.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {MockCreateX} from "@lattice-test/helpers/MockCreateX.sol";
import {DiamondFactory} from "@lattice/factory/DiamondFactory.sol";
import {RecipeEntry} from "@lattice/interfaces/factory/IDiamondFactory.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";

/// @notice One-shot initializer for the release-composed ERC-20 diamond: seeds name/symbol (registering
///         IERC20 via ERC-165) and mints an opening balance so the pipeline test can exercise a real
///         transfer. Delegatecalled by {Diamond.initialize} inside the initializing window, so
///         `address(this)` is the diamond.
contract ReleaseErc20Init {
    function init(string memory name_, string memory symbol_, address to, uint256 amount) external {
        ERC20Lib.__ERC20_init(name_, symbol_);
        ERC20Lib._mint(to, amount);
    }
}

/// @title ReleasePipelineTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice THE issue #120 story end-to-end: {DeployRelease.release} stands up the whole canonical release
///         (registry + factory + all 95 facets, registered and flagged latest) against CreateX, then —
///         using ONLY the release outputs — the {DiamondFactory} resolves `latest("lattice.ERC20")` off the
///         registry and assembles a live ERC-20 diamond in one call. Proves: release → registry-resolved
///         latest → one-tx diamond → live token. Inherits {DeployRelease} and drives `this.release(...)` as
///         an external self-call so the broadcaster the registry sees is this contract (see
///         DeployReleaseTest for the sender-alignment rationale).
contract ReleasePipelineTest is GetSelectors, DeployRelease {
    address internal constant CANONICAL = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

    /// @dev Curated Tier-B name key for the base ERC-20 share facet.
    bytes32 internal constant ERC20_NAME = keccak256("lattice.ERC20");

    function setUp() public {
        MockCreateX impl = new MockCreateX();
        vm.etch(CANONICAL, address(impl).code);
    }

    /// @notice release("0.1.0") -> factory.deploy(latest lattice.ERC20 + classic ERC165 cut + init) -> a
    ///         live ERC-20 diamond, all resolved off the release outputs alone.
    function test_ReleaseThenFactoryAssemblesLiveErc20Diamond() public {
        // 1. The whole canonical release in one call.
        DeployRelease.ReleaseOutput memory out = this.release("0.1.0", address(this));
        DiamondFactory factory = DiamondFactory(out.factory);

        // 2. The deployer's whole job: one recipe entry resolving the curator's LATEST pointer (version 0)...
        RecipeEntry[] memory entries = new RecipeEntry[](1);
        entries[0] = RecipeEntry({nameHash: ERC20_NAME, version: 0});

        // ...one custom cut for the diamond-lib ERC165Facet, selectors from its OWN ERC-8153 export
        //    (diamond-lib >=0.2.0; the export excludes exportSelectors() itself, which the factory refuses)...
        address erc165Facet = address(new ERC165Facet());
        FacetCut[] memory customCuts = new FacetCut[](1);
        customCuts[0] = FacetCut({
            facetAddress: erc165Facet,
            action: FacetCutAction.Add,
            functionSelectors: Selectors.decode(IFacet(erc165Facet).exportSelectors())
        });

        // ...and the recipe's init. The factory resolves, deploys, and initializes in ONE call.
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        ReleaseErc20Init init = new ReleaseErc20Init();
        bytes32 salt = keccak256("lattice.release.erc20");

        address predicted = factory.predict(address(this), salt);
        address diamond = factory.deploy(
            entries,
            customCuts,
            address(init),
            abi.encodeCall(ReleaseErc20Init.init, ("Lattice Token", "LAT", alice, 1_000e18)),
            salt
        );
        assertEq(diamond, predicted, "deploy lands at the predicted CREATE2 address");

        // 3. The assembled diamond is a live ERC-20: metadata is wired and a real transfer moves balances.
        IERC20 token = IERC20(diamond);
        assertEq(token.name(), "Lattice Token", "name wired via init");
        assertEq(token.symbol(), "LAT", "symbol wired via init");
        assertEq(token.totalSupply(), 1_000e18, "opening supply minted");
        assertEq(token.balanceOf(alice), 1_000e18, "opening balance");

        vm.prank(alice);
        assertTrue(token.transfer(bob, 400e18), "transfer returns true");
        assertEq(token.balanceOf(alice), 600e18, "sender debited");
        assertEq(token.balanceOf(bob), 400e18, "recipient credited");

        // 4. The custom ERC165Facet cut dispatches too: init registered IERC20 via ERC-165.
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC20).interfaceId), "ERC-165 custom cut live");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DiamondFactory} from "@lattice/factory/DiamondFactory.sol";
import {RecipeEntry} from "@lattice/interfaces/factory/IDiamondFactory.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {LatticeRegistry} from "@lattice/registry/LatticeRegistry.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";

/// @notice One-shot initializer for the factory-composed ERC-20 diamond: seeds name/symbol (registering IERC20
///         via ERC-165) and mints an opening balance so the smoke test can exercise a real transfer. Delegatecalled
///         by {Diamond.initialize} inside the initializing window, so `address(this)` is the diamond.
contract FactoryErc20Init {
    function init(string memory name_, string memory symbol_, address to, uint256 amount) external {
        ERC20Lib.__ERC20_init(name_, symbol_);
        ERC20Lib._mint(to, amount);
    }
}

/// @title DiamondFactoryCompositionTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice The end-to-end issue #120 story, one transaction deeper than the issue #118 composition test: a
///         curator registers a recipe's ERC-8153 facet in a {LatticeRegistry}, and a deployer hands the
///         {DiamondFactory} a recipe entry + a classic {ERC165Facet} custom cut + the recipe's init — the
///         factory resolves the cut off the registry, CREATE2-deploys a {Diamond}, and initializes it, all in
///         ONE call. Proves the full pipeline: register -> deploy(entries, customCuts, init) -> live ERC-20.
contract DiamondFactoryCompositionTest is GetSelectors {
    LatticeRegistry internal registry;
    DiamondFactory internal factory;

    address internal owner = makeAddr("registryOwner");

    /// @dev Curated Tier-B name key for the base ERC-20 share facet.
    bytes32 internal constant ERC20_NAME = keccak256("lattice.ERC20");

    /// @dev Pack a semver triple the way {LatticeRegistry} documents: `major<<48 | minor<<24 | patch`.
    function _v(uint16 major, uint24 minor, uint24 patch) internal pure returns (uint64) {
        return (uint64(major) << 48) | (uint64(minor) << 24) | uint64(patch);
    }

    /// @notice register -> factory.deploy -> a live ERC-20 diamond at the predicted CREATE2 address.
    function test_FactoryAssemblesRegistryErc20DiamondInOneCall() public {
        uint64 version = _v(1, 0, 0);

        // 1. Deploy the standalone registry singleton and the stateless factory bound to it.
        registry = new LatticeRegistry(owner);
        factory = new DiamondFactory(registry);

        // 2. Curate the base ERC-20 facet (an ERC-8153 Lattice facet). register pulls + pins its exported
        //    selectors and mirrors the codehash into the permissionless Tier-A resolver.
        address erc20Facet = address(new ERC20());
        vm.prank(owner);
        registry.register(ERC20_NAME, version, erc20Facet);

        // 3. The deployer's whole job: one recipe entry pinning (name, version)...
        RecipeEntry[] memory entries = new RecipeEntry[](1);
        entries[0] = RecipeEntry({nameHash: ERC20_NAME, version: version});

        // ...one classic custom cut for the diamond-lib ERC165Facet (no ERC-8153 surface)...
        FacetCut[] memory customCuts = new FacetCut[](1);
        customCuts[0] = FacetCut({
            facetAddress: address(new ERC165Facet()),
            action: FacetCutAction.Add,
            functionSelectors: _getSelectors("ERC165Facet")
        });

        // ...and the recipe's init. The factory resolves, deploys, and initializes in ONE call.
        address alice = makeAddr("alice");
        address bob = makeAddr("bob");
        FactoryErc20Init init = new FactoryErc20Init();
        bytes32 salt = keccak256("lattice.factory.erc20");

        address predicted = factory.predict(address(this), salt);
        address diamond = factory.deploy(
            entries,
            customCuts,
            address(init),
            abi.encodeCall(FactoryErc20Init.init, ("Lattice Token", "LAT", alice, 1_000e18)),
            salt
        );
        assertEq(diamond, predicted, "deploy lands at the predicted CREATE2 address");

        // 4. The assembled diamond is a live ERC-20: metadata is wired and a real transfer moves balances.
        IERC20 token = IERC20(diamond);
        assertEq(token.name(), "Lattice Token", "name wired via init");
        assertEq(token.symbol(), "LAT", "symbol wired via init");
        assertEq(token.decimals(), 18, "default decimals");
        assertEq(token.totalSupply(), 1_000e18, "opening supply minted");
        assertEq(token.balanceOf(alice), 1_000e18, "opening balance");

        vm.prank(alice);
        assertTrue(token.transfer(bob, 400e18), "transfer returns true");
        assertEq(token.balanceOf(alice), 600e18, "sender debited");
        assertEq(token.balanceOf(bob), 400e18, "recipient credited");

        // 5. The custom ERC165Facet cut dispatches too: init registered IERC20 via ERC-165.
        assertTrue(ERC165Facet(diamond).supportsInterface(type(IERC20).interfaceId), "ERC-165 custom cut live");
    }
}

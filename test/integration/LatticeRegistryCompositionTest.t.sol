// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {ILatticeRegistry} from "@lattice/interfaces/ILatticeRegistry.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";

/// @notice One-shot initializer for the registry-composed ERC-20 diamond: seeds name/symbol (registering IERC20
///         via ERC-165) and mints an opening balance so the smoke test can exercise a real transfer. Delegatecalled
///         by {Diamond.initialize} inside the initializing window, so `address(this)` is the diamond.
contract RegistryErc20Init {
    function init(string memory name_, string memory symbol_, address to, uint256 amount) external {
        ERC20Lib.__ERC20_init(name_, symbol_);
        ERC20Lib._mint(to, amount);
    }
}

/// @title LatticeRegistryCompositionTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice The end-to-end issue #118 story: a curator registers a recipe's ERC-8153 facet in a {LatticeRegistry},
///         a deployer resolves the ready-to-apply {FacetCut} straight off the registry (no FFI, no re-`CREATE`),
///         assembles a real {Diamond} from that cut plus the classic diamond-lib {ERC165Facet} cut, initializes it
///         with the recipe's init, and the result is a working ERC-20. Proves the full pipeline:
///         register -> resolve -> getCut -> cut -> live diamond.
contract LatticeRegistryCompositionTest is GetSelectors {
    LatticeRegistry internal registry;

    address internal owner = makeAddr("registryOwner");

    /// @dev Curated Tier-B name key for the base ERC-20 share facet.
    bytes32 internal constant ERC20_NAME = keccak256("lattice.ERC20");

    /// @dev Pack a semver triple the way {LatticeRegistry} documents: `major<<48 | minor<<24 | patch`.
    function _v(uint16 major, uint24 minor, uint24 patch) internal pure returns (uint64) {
        return (uint64(major) << 48) | (uint64(minor) << 24) | uint64(patch);
    }

    /// @notice register -> resolve/getCut -> assemble a diamond -> transfer through registry-sourced selectors.
    function test_RegisterResolveGetCutAssembleAndTransfer() public {
        uint64 version = _v(1, 0, 0);

        // 1. Deploy the standalone registry singleton.
        registry = new LatticeRegistry(owner);

        // 2. Curate the base ERC-20 facet (an ERC-8153 Lattice facet). register pulls + pins its exported selectors
        //    and mirrors the codehash into the permissionless Tier-A resolver.
        address erc20Facet = address(new ERC20());
        vm.prank(owner);
        registry.register(ERC20_NAME, version, erc20Facet);

        // The record resolves both ways: curated get() and permissionless resolve(codehash).
        assertEq(registry.get(ERC20_NAME, version).facet, erc20Facet, "curated record facet");
        assertEq(registry.resolve(erc20Facet.codehash), erc20Facet, "Tier-A auto-attest");

        // 3. Resolve a ready-to-apply cut straight off the registry (live selector drift-check happens here).
        FacetCut memory erc20Cut = registry.getCut(ERC20_NAME, version);
        assertEq(erc20Cut.facetAddress, erc20Facet, "cut points at the registered facet");
        assertEq(uint256(erc20Cut.action), uint256(FacetCutAction.Add), "registry cuts are Add");
        assertEq(erc20Cut.functionSelectors.length, 9, "ERC-20 exports 9 selectors");

        // 4. ERC165Facet is a diamond-lib facet with no ERC-8153 surface, so it is cut the classic way.
        FacetCut memory erc165Cut = FacetCut({
            facetAddress: address(new ERC165Facet()),
            action: FacetCutAction.Add,
            functionSelectors: _getSelectors("ERC165Facet")
        });

        // 5. Assemble a real diamond from [ERC165 (classic) + ERC20 (registry)] and the recipe's init.
        FacetCut[] memory cuts = new FacetCut[](2);
        cuts[0] = erc165Cut;
        cuts[1] = erc20Cut;

        address alice = makeAddr("alice");
        address bob = makeAddr("bob");

        RegistryErc20Init init = new RegistryErc20Init();
        Diamond diamond = new Diamond();
        diamond.initialize(
            cuts, address(init), abi.encodeCall(RegistryErc20Init.init, ("Lattice Token", "LAT", alice, 1_000e18))
        );

        // 6. The assembled diamond is a live ERC-20: metadata is wired and a real transfer moves balances.
        IERC20 token = IERC20(address(diamond));
        assertEq(token.name(), "Lattice Token", "name wired via init");
        assertEq(token.symbol(), "LAT", "symbol wired via init");
        assertEq(token.decimals(), 18, "default decimals");
        assertEq(token.totalSupply(), 1_000e18, "opening supply minted");
        assertEq(token.balanceOf(alice), 1_000e18, "opening balance");

        vm.prank(alice);
        assertTrue(token.transfer(bob, 400e18), "transfer returns true");
        assertEq(token.balanceOf(alice), 600e18, "sender debited");
        assertEq(token.balanceOf(bob), 400e18, "recipient credited");
    }

    /// @notice A consumer that pins an exact `(name, version)` gets a cut whose selectors are live-verified against
    ///         the registration-time pin — the registry never hands back a drifted selector set.
    function test_GetCutMatchesFacetLiveExport() public {
        uint64 version = _v(1, 0, 0);
        registry = new LatticeRegistry(owner);

        ERC20 erc20Facet = new ERC20();
        vm.prank(owner);
        registry.register(ERC20_NAME, version, address(erc20Facet));

        // getCut's live-verified selectors equal the facet's own ERC-8153 export, decoded 4 bytes at a time.
        FacetCut memory cut = registry.getCut(ERC20_NAME, version);
        bytes memory packed = erc20Facet.exportSelectors();
        assertEq(cut.functionSelectors.length, packed.length / 4, "selector count parity");
        for (uint256 i; i < cut.functionSelectors.length; ++i) {
            bytes4 sel;
            assembly ("memory-safe") {
                sel := mload(add(add(packed, 0x20), mul(i, 4)))
            }
            assertEq(cut.functionSelectors[i], sel, "selector parity with live export");
        }
    }
}

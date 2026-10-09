// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC20Wrapper} from "@lattice-script/base/tokens/DeployERC20Wrapper.s.sol";
import {DeployERC721URIStorage} from "@lattice-script/base/tokens/DeployERC721URIStorage.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {ERC6551Account} from "@lattice/accounts/ERC6551Account.sol";
import {SessionKey} from "@lattice/accounts/SessionKey.sol";
import {ERC7579ModuleConfig} from "@lattice/accounts/erc7579/ERC7579ModuleConfig.sol";
import {AaveV3Adapter} from "@lattice/defi/AaveV3Adapter.sol";
import {CompoundV3Adapter} from "@lattice/defi/CompoundV3Adapter.sol";
import {CurveStableSwapAdapter} from "@lattice/defi/CurveStableSwapAdapter.sol";
import {ERC4626Adapter} from "@lattice/defi/ERC4626Adapter.sol";
import {LidoAdapter} from "@lattice/defi/LidoAdapter.sol";
import {UniswapV3Adapter} from "@lattice/defi/UniswapV3Adapter.sol";
import {RecipeEntry} from "@lattice/interfaces/ILatticeFactory.sol";
import {IERC8153} from "@lattice/interfaces/external/ercs/IERC8153.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Wrapper} from "@lattice/tokens/ERC20/ERC20Wrapper.sol";
import {ERC721} from "@lattice/tokens/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@lattice/tokens/ERC721/ERC721URIStorage.sol";
import {Nonces} from "@lattice/utils/Nonces.sol";
import {VestingWallet} from "@lattice/utils/VestingWallet.sol";

/// @title LatticeRegistryNewExportsTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice #176: the 13 facets that gained an ERC-8153 `exportSelectors()` can be registry entries. Each one
///         registers in a {LatticeRegistry} (so its export passes the registry's checks and its bounded exporter
///         read), and `getCut` returns an `Add` of exactly the selectors the facet was custom-cut with before:
///         the recipe's hand-written mixed cut for ERC20Wrapper and ERC721URIStorage, and the `forge inspect`
///         cut ({BaseDeploy}'s name-based `_cut`) for the rest. The two facets that replace a base selector
///         (`decimals()`, `tokenURI(uint256)`) deploy through the factory from registry entries alone, with the
///         base entry excluding the replaced selector.
contract LatticeRegistryNewExportsTest is GetSelectors {
    LatticeRegistry internal registry;
    LatticeFactory internal factory;

    uint64 internal constant V1 = 1 << 48;
    bytes4 internal constant EXPORT_SELECTOR = 0x0ef22643;

    function setUp() public {
        registry = new LatticeRegistry(address(this));
        factory = new LatticeFactory(registry, address(0), address(0));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    REGISTER + getCut == THE CUSTOM CUT
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice ERC20Wrapper: `getCut` covers the recipe's Add (`underlying`, `depositFor`, `withdrawTo`) and
    ///         Replace (`decimals`) cuts of the same facet.
    function test_ERC20WrapperGetCutMatchesRecipeCut() public {
        (FacetCut[] memory cuts,,) = new DeployERC20Wrapper().buildCuts("Wrapped", "W", makeAddr("underlying"));
        address facet = cuts[cuts.length - 1].facetAddress;
        _assertRegistryCutEquals("ERC20Wrapper", facet, _selectorsOf(cuts, facet));
    }

    /// @notice ERC721URIStorage: `getCut` covers the recipe's Add (`setTokenURI`) and Replace (`tokenURI`) cuts.
    function test_ERC721URIStorageGetCutMatchesRecipeCut() public {
        (FacetCut[] memory cuts,,) = new DeployERC721URIStorage().buildCuts("Name", "N", makeAddr("admin"));
        address facet = cuts[2].facetAddress;
        _assertRegistryCutEquals("ERC721URIStorage", facet, _selectorsOf(cuts, facet));
    }

    /// @notice The other eleven facets: `getCut` equals the `forge inspect` cut they were custom-cut with.
    function test_OtherNewExportersGetCutMatchesInspectCut() public {
        _assertRegistryCutEqualsInspect("Nonces", address(new Nonces()));
        _assertRegistryCutEqualsInspect("VestingWallet", address(new VestingWallet()));
        _assertRegistryCutEqualsInspect("ERC7579ModuleConfig", address(new ERC7579ModuleConfig()));
        _assertRegistryCutEqualsInspect("SessionKey", address(new SessionKey()));
        _assertRegistryCutEqualsInspect("ERC6551Account", address(new ERC6551Account()));
        _assertRegistryCutEqualsInspect("AaveV3Adapter", address(new AaveV3Adapter()));
        _assertRegistryCutEqualsInspect("CompoundV3Adapter", address(new CompoundV3Adapter()));
        _assertRegistryCutEqualsInspect("CurveStableSwapAdapter", address(new CurveStableSwapAdapter()));
        _assertRegistryCutEqualsInspect("ERC4626Adapter", address(new ERC4626Adapter()));
        _assertRegistryCutEqualsInspect("LidoAdapter", address(new LidoAdapter()));
        _assertRegistryCutEqualsInspect("UniswapV3Adapter", address(new UniswapV3Adapter()));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                REPLACING FACETS AS REGISTRY-ONLY RECIPES
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice An ERC-20 wrapper diamond from registry entries alone: ERC20 excludes `decimals()`, which
    ///         ERC20Wrapper then supplies, so every selector routes to the facet that owns it.
    function test_ERC20WrapperDeploysFromRegistryEntries() public {
        address erc20 = address(new ERC20());
        address wrapper = address(new ERC20Wrapper());
        _register("ERC20", erc20);
        _register("ERC20Wrapper", wrapper);
        address loupe = _registerLoupe();

        RecipeEntry[] memory entries = new RecipeEntry[](3);
        entries[0] = _entry("ERC20", _one(ERC20Wrapper.decimals.selector));
        entries[1] = _entry("ERC20Wrapper", new bytes4[](0));
        entries[2] = _entry("DiamondLoupeFacet", new bytes4[](0));
        address diamond = factory.deployStrict(entries, new FacetCut[](0), address(0), "", keccak256("wrapper"));

        IDiamondLoupe l = IDiamondLoupe(diamond);
        assertEq(l.facetAddress(ERC20Wrapper.decimals.selector), wrapper, "decimals() not routed to the wrapper");
        assertEq(l.facetAddress(ERC20Wrapper.underlying.selector), wrapper, "underlying() not routed");
        assertEq(l.facetAddress(ERC20.transfer.selector), erc20, "transfer() not routed to ERC20");
        assertEq(l.facetAddress(IDiamondLoupe.facets.selector), loupe, "loupe not routed");
        assertEq(l.facetAddress(EXPORT_SELECTOR), address(0), "exportSelectors() routed");
    }

    /// @notice An ERC-721 URI-storage diamond from registry entries alone: ERC721 excludes `tokenURI(uint256)`,
    ///         which ERC721URIStorage then supplies.
    function test_ERC721URIStorageDeploysFromRegistryEntries() public {
        address erc721 = address(new ERC721());
        address uri = address(new ERC721URIStorage());
        _register("ERC721", erc721);
        _register("ERC721URIStorage", uri);
        _registerLoupe();

        RecipeEntry[] memory entries = new RecipeEntry[](3);
        entries[0] = _entry("ERC721", _one(ERC721URIStorage.tokenURI.selector));
        entries[1] = _entry("ERC721URIStorage", new bytes4[](0));
        entries[2] = _entry("DiamondLoupeFacet", new bytes4[](0));
        address diamond = factory.deployStrict(entries, new FacetCut[](0), address(0), "", keccak256("uri"));

        IDiamondLoupe l = IDiamondLoupe(diamond);
        assertEq(l.facetAddress(ERC721URIStorage.tokenURI.selector), uri, "tokenURI() not routed to URI storage");
        assertEq(l.facetAddress(ERC721URIStorage.setTokenURI.selector), uri, "setTokenURI() not routed");
        assertEq(l.facetAddress(ERC721.ownerOf.selector), erc721, "ownerOf() not routed to ERC721");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Registers `facet` as `name` v1, then checks `getCut`: an `Add` of `facet` whose selectors are the
    ///      facet's export in order, and set-equal to `expected` (the custom cut).
    function _assertRegistryCutEquals(string memory name, address facet, bytes4[] memory expected) internal {
        registry.register(name, V1, facet);
        FacetCut memory cut = registry.getCut(name, V1);
        assertEq(cut.facetAddress, facet, string.concat(name, ": cut facet"));
        assertEq(uint8(cut.action), uint8(FacetCutAction.Add), string.concat(name, ": cut action"));
        assertEq(
            _pack(cut.functionSelectors), IERC8153(facet).exportSelectors(), string.concat(name, ": getCut != export")
        );
        assertTrue(_setEq(cut.functionSelectors, expected), string.concat(name, ": getCut != custom cut"));
    }

    /// @dev {_assertRegistryCutEquals} against the `forge inspect` selector set minus `exportSelectors()`.
    function _assertRegistryCutEqualsInspect(string memory name, address facet) internal {
        bytes4[] memory all = _getSelectors(name);
        bytes4[] memory kept = new bytes4[](all.length);
        uint256 n;
        for (uint256 i; i < all.length; ++i) {
            if (all[i] != EXPORT_SELECTOR) kept[n++] = all[i];
        }
        assembly ("memory-safe") {
            mstore(kept, n)
        }
        _assertRegistryCutEquals(name, facet, kept);
    }

    /// @dev Every selector the cuts route to `facet`, across all of its cuts (Add and Replace).
    function _selectorsOf(FacetCut[] memory cuts, address facet) internal pure returns (bytes4[] memory sels) {
        uint256 n;
        for (uint256 i; i < cuts.length; ++i) {
            if (cuts[i].facetAddress == facet) n += cuts[i].functionSelectors.length;
        }
        sels = new bytes4[](n);
        n = 0;
        for (uint256 i; i < cuts.length; ++i) {
            if (cuts[i].facetAddress != facet) continue;
            for (uint256 j; j < cuts[i].functionSelectors.length; ++j) {
                sels[n++] = cuts[i].functionSelectors[j];
            }
        }
    }

    function _register(string memory name, address facet) internal {
        registry.register(name, V1, facet);
    }

    function _registerLoupe() internal returns (address loupe) {
        loupe = address(new DiamondLoupeFacet());
        _register("DiamondLoupeFacet", loupe);
    }

    function _entry(string memory name, bytes4[] memory exclude) internal view returns (RecipeEntry memory) {
        return RecipeEntry({nameHash: registry.nameHash(name), version: V1, exclude: exclude});
    }

    /// @dev Tightly packs `sels` (4 bytes each), the ERC-8153 export encoding.
    function _pack(bytes4[] memory sels) internal pure returns (bytes memory packed) {
        for (uint256 i; i < sels.length; ++i) {
            packed = bytes.concat(packed, sels[i]);
        }
    }

    function _one(bytes4 sel) internal pure returns (bytes4[] memory s) {
        s = new bytes4[](1);
        s[0] = sel;
    }

    /// @dev Order-insensitive equality of two duplicate-free selector sets.
    function _setEq(bytes4[] memory a, bytes4[] memory b) internal pure returns (bool) {
        if (a.length != b.length) return false;
        for (uint256 i; i < a.length; ++i) {
            bool found;
            for (uint256 j; j < b.length; ++j) {
                if (a[i] == b[j]) {
                    found = true;
                    break;
                }
            }
            if (!found) return false;
        }
        return true;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {MultiInit} from "@diamond/initializers/MultiInit.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {IERC8153} from "@lattice/interfaces/external/IERC8153.sol";
import {Script} from "forge-std/Script.sol";

/// @title BaseDeploy
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Generic building blocks every ready-to-deploy Lattice diamond script shares: turn a facet contract
///         into an `Add`/`Replace` {FacetCut}, and assemble a {Diamond} proxy from cuts + an initializer.
///         Two selector sources coexist: the STRING helpers (`_cut(addr, "Name")`) resolve selectors from the
///         facet's real ABI via diamond-lib {GetSelectors}/`forge inspect` — used for the diamond-lib facets
///         ({ERC165Facet}, {DiamondCutFacet}, {DiamondLoupeFacet}) that cannot implement ERC-8153; the ADDRESS
///         helpers (`_cut(addr)`) read the facet's own {IERC8153-exportSelectors}, so a facet self-reports the
///         selectors it owns with no FFI. Both paths strip `exportSelectors()` (0x0ef22643): the diamond never
///         exposes ERC-8153 introspection. `_assemble*` are broadcast-free so tests reuse the exact production
///         composition; concrete scripts wrap their `run()` in `vm.startBroadcast()`. Mirrors the intent of
///         diamond-lib's {DeployDiamond} but factored so per-family scripts ({DeployAccount}, {DeployERC20}, …)
///         stay tiny.
abstract contract BaseDeploy is Script, GetSelectors {
    /// @dev `IERC8153.exportSelectors()` selector. The diamond never exposes ERC-8153 introspection, so this
    ///      selector is stripped from every FFI (`forge inspect`) selector set: once a facet implements
    ///      {IERC8153}, `forge inspect` lists `exportSelectors()` in its ABI, and cutting it onto a second facet
    ///      of the same recipe would revert `CannotAddFunctionToDiamondThatAlreadyExists`. The address-based
    ///      helpers read the runtime `exportSelectors()` return, which already excludes it by the ERC-8153 rule.
    bytes4 private constant _EXPORT_SELECTORS = 0x0ef22643;

    //*//////////////////////////////////////////////////////////////////////////
    //                      STRING (forge inspect) CUTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice An `Add` cut for `facet` covering every selector `name`'s ABI declares (minus `exportSelectors()`).
    /// @param facet The deployed facet address.
    /// @param name The facet contract name (for `forge inspect`).
    function _cut(address facet, string memory name) internal returns (FacetCut memory) {
        return FacetCut({
            facetAddress: facet,
            action: FacetCutAction.Add,
            functionSelectors: _withoutExportSelector(_getSelectors(name))
        });
    }

    /// @notice A `Replace` cut for `facet` (its selectors must already exist on the diamond).
    function _replace(address facet, string memory name) internal returns (FacetCut memory) {
        return FacetCut({
            facetAddress: facet,
            action: FacetCutAction.Replace,
            functionSelectors: _withoutExportSelector(_getSelectors(name))
        });
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                      ERC-8153 (exportSelectors) CUTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice An `Add` cut for an ERC-8153 `facet`, selectors sourced from its own `exportSelectors()` — no
    ///         `forge inspect`/FFI, no contract name. The facet self-reports exactly the selectors it owns.
    /// @param facet The deployed facet address (MUST implement {IERC8153}).
    function _cut(address facet) internal view returns (FacetCut memory) {
        return FacetCut({facetAddress: facet, action: FacetCutAction.Add, functionSelectors: _exportedSelectors(facet)});
    }

    /// @notice A `Replace` cut for an ERC-8153 `facet` (its exported selectors must already exist on the diamond).
    function _replace(address facet) internal view returns (FacetCut memory) {
        return
            FacetCut({
                facetAddress: facet, action: FacetCutAction.Replace, functionSelectors: _exportedSelectors(facet)
            });
    }

    /// @notice An `Add` cut of an ERC-8153 `facet`'s exported selectors MINUS `excluded` — for facets whose
    ///         reconciled selectors are owned by a sibling facet (or a reconciliation facet) in a shared diamond.
    /// @param facet The deployed facet address (MUST implement {IERC8153}).
    /// @param excluded The selectors to drop from `facet`'s cut.
    function _cutExcept(address facet, bytes4[] memory excluded) internal view returns (FacetCut memory) {
        bytes4[] memory all = _exportedSelectors(facet);
        bytes4[] memory kept = new bytes4[](all.length);
        uint256 n;
        for (uint256 i; i < all.length; ++i) {
            if (!_containsSelector(excluded, all[i])) kept[n++] = all[i];
        }
        assembly ("memory-safe") {
            mstore(kept, n)
        }
        return FacetCut({facetAddress: facet, action: FacetCutAction.Add, functionSelectors: kept});
    }

    /// @notice Reads, validates, and decodes an ERC-8153 facet's tightly packed `exportSelectors()` bytes.
    /// @dev Staticcalls {IERC8153-exportSelectors}; requires the call to succeed, a non-empty return, and a
    ///      length that is a whole number of 4-byte selectors. Each 4-byte chunk becomes one `bytes4` selector.
    /// @param facet The deployed facet address (MUST implement {IERC8153}).
    /// @return selectors The decoded selectors, one per packed 4-byte chunk.
    function _exportedSelectors(address facet) internal view returns (bytes4[] memory selectors) {
        (bool ok, bytes memory ret) = facet.staticcall(abi.encodeCall(IERC8153.exportSelectors, ()));
        require(ok, "BaseDeploy: exportSelectors() staticcall reverted");
        bytes memory packed = abi.decode(ret, (bytes));
        uint256 len = packed.length;
        require(len != 0, "BaseDeploy: exportSelectors() returned no selectors");
        require(len % 4 == 0, "BaseDeploy: exportSelectors() length not a multiple of 4");

        uint256 count = len / 4;
        selectors = new bytes4[](count);
        for (uint256 i; i < count; ++i) {
            bytes4 sel;
            assembly ("memory-safe") {
                sel := mload(add(add(packed, 0x20), mul(i, 4)))
            }
            selectors[i] = sel;
        }
    }

    /// @dev Returns `sels` without the ERC-8153 `exportSelectors()` selector (never cut onto the diamond).
    function _withoutExportSelector(bytes4[] memory sels) private pure returns (bytes4[] memory kept) {
        kept = new bytes4[](sels.length);
        uint256 n;
        for (uint256 i; i < sels.length; ++i) {
            if (sels[i] != _EXPORT_SELECTORS) kept[n++] = sels[i];
        }
        assembly ("memory-safe") {
            mstore(kept, n)
        }
    }

    /// @dev True if `set` contains `sel`.
    function _containsSelector(bytes4[] memory set, bytes4 sel) private pure returns (bool) {
        for (uint256 i; i < set.length; ++i) {
            if (set[i] == sel) return true;
        }
        return false;
    }

    /// @notice Deploys a {Diamond} and initializes it with `cuts` + a single `init` delegatecall.
    /// @dev Broadcast-free — a production `run()` wraps the call in `vm.startBroadcast()`; tests call directly.
    function _assemble(FacetCut[] memory cuts, address init, bytes memory initCalldata)
        internal
        returns (address diamond)
    {
        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond = address(d);
    }

    /// @notice Deploys a {Diamond} whose init runs SEVERAL initializers in order via {MultiInit} — the way to
    ///         seed a multi-facet diamond (e.g. a permit token: ERC-20 + EIP-712 + Nonces) without a bespoke
    ///         per-recipe init contract. Each `inits[i]` is delegatecalled inside the same initializing window.
    /// @param cuts The facet cuts.
    /// @param inits The initializer contracts, run in order.
    /// @param initCalldatas The calldata for each initializer (must match `inits` length).
    function _assembleMulti(FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas)
        internal
        returns (address diamond)
    {
        MultiInit multiInit = new MultiInit();
        diamond = _assemble(cuts, address(multiInit), abi.encodeCall(MultiInit.multiInit, (inits, initCalldatas)));
    }
}

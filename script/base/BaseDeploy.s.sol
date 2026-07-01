// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {MultiInit} from "@diamond/initializers/MultiInit.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {Script} from "forge-std/Script.sol";

/// @title BaseDeploy
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Generic building blocks every ready-to-deploy Lattice diamond script shares: turn a facet contract
///         into an `Add`/`Replace` {FacetCut} (selectors resolved from the facet's real ABI via
///         diamond-lib {GetSelectors}/`forge inspect`), and assemble a {Diamond} proxy from cuts + an
///         initializer. `_assemble*` are broadcast-free so tests reuse the exact production composition;
///         concrete scripts wrap their `run()` in `vm.startBroadcast()`. Mirrors the intent of diamond-lib's
///         {DeployDiamond} but factored so per-family scripts ({DeployAccount}, {DeployERC20}, …) stay tiny.
abstract contract BaseDeploy is Script, GetSelectors {
    /// @notice An `Add` cut for `facet` covering every selector `name`'s ABI declares.
    /// @param facet The deployed facet address.
    /// @param name The facet contract name (for `forge inspect`).
    function _cut(address facet, string memory name) internal returns (FacetCut memory) {
        return FacetCut({facetAddress: facet, action: FacetCutAction.Add, functionSelectors: _getSelectors(name)});
    }

    /// @notice A `Replace` cut for `facet` (its selectors must already exist on the diamond).
    function _replace(address facet, string memory name) internal returns (FacetCut memory) {
        return FacetCut({facetAddress: facet, action: FacetCutAction.Replace, functionSelectors: _getSelectors(name)});
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

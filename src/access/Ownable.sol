// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// Re-export of diamond-lib's `OwnableFacet` (no Lattice code). It is the only import of that facet under
// src/, script/ and test/, so it is what compiles the `OwnableFacet.sol:OwnableFacet` artifact that
// `script/lib/FacetInventory.sol` (DeployRelease, ExportSelectorsParityTest) loads. Keep it.
import {OwnableFacet as Ownable} from "@diamond/facets/OwnableFacet.sol";

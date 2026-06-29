// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {DiamondCutFacet} from "@diamond/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {ERC1271Signature} from "@lattice/accounts/ERC1271Signature.sol";
import {ERC4337Validation} from "@lattice/accounts/ERC4337Validation.sol";
import {AccountInit} from "@lattice/accounts/erc7579/AccountInit.sol";
import {AccountSigner} from "@lattice/accounts/erc7579/AccountSigner.sol";
import {ERC7821Executor} from "@lattice/accounts/erc7579/ERC7821Executor.sol";

/// @notice Builds the canonical single-owner ERC-4337 account blueprint (8 facets + initializer) used by the
///         factory, 7702, and EntryPoint integration tests. Selectors come from diamond-lib `GetSelectors`
///         (`forge inspect` over FFI), matching `DeployDiamond`.
abstract contract AccountBlueprintHelper is GetSelectors {
    /// @param entryPoint_ The EntryPoint the account's `AccountInit` seeds.
    /// @return cuts The facet cuts (Add) wiring a complete account.
    /// @return init The matching initializer (`init(address)` / `init7702()`).
    function _accountBlueprint(address entryPoint_) internal returns (FacetCut[] memory cuts, AccountInit init) {
        cuts = new FacetCut[](8);
        cuts[0] = _cut(address(new DiamondCutFacet()), "DiamondCutFacet");
        cuts[1] = _cut(address(new DiamondLoupeFacet()), "DiamondLoupeFacet");
        cuts[2] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[3] = _cut(address(new AccessControl()), "AccessControl");
        cuts[4] = _cut(address(new AccountSigner()), "AccountSigner");
        cuts[5] = _cut(address(new ERC4337Validation()), "ERC4337Validation");
        cuts[6] = _cut(address(new ERC1271Signature()), "ERC1271Signature");
        cuts[7] = _cut(address(new ERC7821Executor()), "ERC7821Executor");
        init = new AccountInit(entryPoint_);
    }

    function _cut(address facet, string memory name) private returns (FacetCut memory) {
        return FacetCut({facetAddress: facet, action: FacetCutAction.Add, functionSelectors: _getSelectors(name)});
    }
}

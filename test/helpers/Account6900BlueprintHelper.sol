// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {DiamondCutFacet} from "@diamond/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccountInit6900} from "@lattice/accounts/erc6900/AccountInit6900.sol";
import {ERC6900AccountView} from "@lattice/accounts/erc6900/ERC6900AccountView.sol";
import {ERC6900Executor} from "@lattice/accounts/erc6900/ERC6900Executor.sol";
import {ERC6900ModuleManager} from "@lattice/accounts/erc6900/ERC6900ModuleManager.sol";
import {ERC6900Signature} from "@lattice/accounts/erc6900/ERC6900Signature.sol";
import {ERC6900Validation} from "@lattice/accounts/erc6900/ERC6900Validation.sol";

/// @notice Builds the canonical ERC-6900 modular-account blueprint (9 facets + initializer) for the
///         {AccountFactory6900}. The shared Diamond core (cut/loupe/erc165/access) plus the five 6900 facets
///         (module manager, executor, userOp validation, signature, account view) replace the ERC-7579 stack's
///         AccountSigner / ERC4337Validation / ERC1271Signature / ERC7821Executor. Selectors come from diamond-lib
///         `GetSelectors` (`forge inspect` over FFI).
abstract contract Account6900BlueprintHelper is GetSelectors {
    /// @param entryPoint_ The EntryPoint the account's {AccountInit6900} seeds.
    /// @return cuts The facet cuts (Add) wiring a complete ERC-6900 account.
    /// @return init The matching initializer (`init(address owner)`).
    function _accountBlueprint6900(address entryPoint_)
        internal
        returns (FacetCut[] memory cuts, AccountInit6900 init)
    {
        cuts = new FacetCut[](9);
        cuts[0] = _cut6900(address(new DiamondCutFacet()), "DiamondCutFacet");
        cuts[1] = _cut6900(address(new DiamondLoupeFacet()), "DiamondLoupeFacet");
        cuts[2] = _cut6900(address(new ERC165Facet()), "ERC165Facet");
        cuts[3] = _cut6900(address(new AccessControl()), "AccessControl");
        cuts[4] = _cut6900(address(new ERC6900ModuleManager()), "ERC6900ModuleManager");
        cuts[5] = _cut6900(address(new ERC6900Executor()), "ERC6900Executor");
        cuts[6] = _cut6900(address(new ERC6900Validation()), "ERC6900Validation");
        cuts[7] = _cut6900(address(new ERC6900Signature()), "ERC6900Signature");
        cuts[8] = _cut6900(address(new ERC6900AccountView()), "ERC6900AccountView");
        init = new AccountInit6900(entryPoint_);
    }

    function _cut6900(address facet, string memory name) private returns (FacetCut memory) {
        return FacetCut({facetAddress: facet, action: FacetCutAction.Add, functionSelectors: _getSelectors(name)});
    }
}

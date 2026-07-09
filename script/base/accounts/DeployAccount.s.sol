// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {DiamondCutFacet} from "@diamond/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {ERC1271Signature} from "@lattice/accounts/ERC1271Signature.sol";
import {ERC4337Validation} from "@lattice/accounts/ERC4337Validation.sol";
import {AccountInit} from "@lattice/accounts/erc7579/AccountInit.sol";
import {AccountSigner} from "@lattice/accounts/erc7579/AccountSigner.sol";
import {ERC7821Executor} from "@lattice/accounts/erc7579/ERC7821Executor.sol";

/// @title DeployAccount
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Canonical single-owner ERC-4337/7579 account composition (8 facets + {AccountInit}) — the ONE
///         source of truth for "which facets make an account", shared by production deploys (this script,
///         or `new AccountFactory(buildCuts(...), init)`) and the account test blueprints. This mirrors
///         diamond-lib's {DeployDiamond}/{DeployedDiamondState} split: {buildCuts} is the broadcast-free
///         primitive tests reuse; {run} is the broadcasting deploy entrypoint. The Lattice account facets
///         self-report their selectors via {BaseDeploy}'s ERC-8153 address cut (`exportSelectors()`, no FFI);
///         the diamond-lib core facets keep the `forge inspect` string cut.
/// @dev {AccountFactory} takes the blueprint as a constructor arg — it deliberately does NOT hardcode the
///      facet set — so this script is where the account's canonical facet list actually lives.
contract DeployAccount is BaseDeploy {
    /// @notice Builds the canonical account facet cuts + initializer. No broadcast, no proxy deploy — the
    ///         reusable primitive both {run} and the test blueprint helper consume.
    /// @param entryPoint_ The EntryPoint the account's {AccountInit} seeds.
    /// @return cuts The 8 facet cuts (Add) wiring a complete single-owner account.
    /// @return init The matching initializer (`init(address owner)` / `init7702()`).
    function buildCuts(address entryPoint_) public returns (FacetCut[] memory cuts, AccountInit init) {
        cuts = new FacetCut[](8);
        cuts[0] = _cut(address(new DiamondCutFacet()), "DiamondCutFacet");
        cuts[1] = _cut(address(new DiamondLoupeFacet()), "DiamondLoupeFacet");
        cuts[2] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[3] = _cut(address(new AccessControl()));
        cuts[4] = _cut(address(new AccountSigner()));
        cuts[5] = _cut(address(new ERC4337Validation()));
        cuts[6] = _cut(address(new ERC1271Signature()));
        cuts[7] = _cut(address(new ERC7821Executor()));
        init = new AccountInit(entryPoint_);
    }

    /// @notice Deploys a complete single-owner account diamond and initializes it for `owner`.
    /// @dev Broadcasting entrypoint for `forge script ... --broadcast`. Tests call {buildCuts} directly.
    /// @param entryPoint_ The EntryPoint seeded into the account.
    /// @param owner The account's initial owner.
    /// @return account The deployed account diamond address.
    function run(address entryPoint_, address owner) external returns (address account) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, AccountInit init) = buildCuts(entryPoint_);
        Diamond diamond = new Diamond();
        diamond.initialize(cuts, address(init), abi.encodeCall(AccountInit.init, (owner)));
        vm.stopBroadcast();
        account = address(diamond);
    }
}

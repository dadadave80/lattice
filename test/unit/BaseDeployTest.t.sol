// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {Base} from "@lattice-test/Base.t.sol";
import {AccountSigner} from "@lattice/accounts/erc7579/AccountSigner.sol";

/// @notice Proves the shared-deploy pattern end-to-end: {Base}.setUp composes the account through the SAME
///         {DeployAccount} blueprint production uses, so a passing assertion here means test setup and the
///         deploy path cannot silently diverge (a facet added to/removed from the canonical blueprint moves
///         this count and fails the test).
contract BaseDeployTest is Base {
    function test_BaseAssemblesAccountThroughSharedDeployScript() public view {
        assertGt(account.code.length, 0, "account diamond not deployed via shared DeployAccount");
        assertEq(DiamondLoupeFacet(account).facetAddresses().length, 8, "canonical 8-facet blueprint not wired");
        assertEq(AccountSigner(account).owner(), owner, "initializer did not run through the deploy path");
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC20Permit} from "@lattice-script/base/tokens/DeployERC20Permit.s.sol";
import {ERC20TestBase} from "@lattice-test/base/ERC20TestBase.sol";

/// @title ERC20PermitTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for {ERC20Permit} facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `_deployERC20Permit` builds the production {DeployERC20Permit} recipe (ERC165 + ERC20 +
///         ERC20Permit, with the EIP-712 domain + nonce storage seeded by {ERC20PermitInit}) and appends the
///         test-only {TokenTestFacet} (inherited `_deployWithHelper`) for balance seeding — so every
///         `permit`/`nonces`/`DOMAIN_SEPARATOR` call routes through the diamond's `delegatecall` dispatch.
abstract contract ERC20PermitTestBase is ERC20TestBase {
    /// @notice Assembles the production permit ERC-20 diamond + the test helper facet.
    /// @param name_ Token name (also the EIP-712 domain name). @param symbol_ Token symbol.
    /// @return diamond_ The deployed permit token diamond.
    function _deployERC20Permit(string memory name_, string memory symbol_) internal returns (address diamond_) {
        DeployERC20Permit d = new DeployERC20Permit();
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory initCalldatas) = d.buildCuts(name_, symbol_);
        diamond_ = _deployWithHelper(cuts, inits, initCalldatas);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC7802} from "@lattice-script/base/tokens/DeployERC7802.s.sol";
import {Test} from "forge-std/Test.sol";

/// @title ERC7802TestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for ERC-7802 facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `setUp` assembles the production {DeployERC7802} recipe (ERC165 + ERC20 + AccessControl +
///         ERC7802 + {ERC7802Init}) so every crosschain mint/burn routes through the diamond's `delegatecall`
///         dispatch, catching selector/storage/init bugs a mock hides. No test-only helper facet is needed:
///         the tests drive the public, role-gated `crosschainMint`/`crosschainBurn` (not raw internal libs).
abstract contract ERC7802TestBase is Test, GetSelectors {
    DeployERC7802 internal deployer;
    address internal diamond; // the assembled crosschain-native ERC-20 diamond

    /// @notice Assembles the production ERC-7802 diamond with `admin` as admin and `bridge` as the bridge.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param bridge The address granted `CROSSCHAIN_BRIDGE_ROLE`.
    /// @param name_ Token name. @param symbol_ Token symbol.
    /// @return diamond_ The deployed token diamond.
    function _deployERC7802(address admin, address bridge, string memory name_, string memory symbol_)
        internal
        returns (address diamond_)
    {
        deployer = new DeployERC7802();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            deployer.buildCuts(admin, bridge, name_, symbol_);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}

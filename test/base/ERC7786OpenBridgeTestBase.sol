// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC7786OpenBridge} from "@lattice-script/base/DeployERC7786OpenBridge.s.sol";
import {ERC7786OpenBridge} from "@lattice/crosschain/ERC7786OpenBridge.sol";
import {Test} from "forge-std/Test.sol";

/// @title ERC7786OpenBridgeTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for ERC-7786 open-bridge facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `setUp` assembles the production {DeployERC7786OpenBridge} recipe (ERC165 +
///         AccessControl + ERC7786OpenBridge + {ERC7786OpenBridgeInit}) and exposes a typed `bridge` handle — so
///         every fan-out send, N-of-M receive and admin config call routes through the diamond's `delegatecall`
///         dispatch, catching selector/storage/init bugs a mock hides. The external `MockSourceGateway` and
///         `MockRecipient` stay test fixtures (they are NOT the facet under test).
abstract contract ERC7786OpenBridgeTestBase is Test, GetSelectors {
    DeployERC7786OpenBridge internal deployer;
    address internal diamond; // the assembled open-bridge diamond
    ERC7786OpenBridge internal bridge; // typed handle on the diamond (all calls dispatch through it)

    /// @notice Assembles the production open-bridge diamond with `admin` as the bridge admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed open-bridge diamond.
    function _deployERC7786OpenBridge(address admin) internal returns (address diamond_) {
        deployer = new DeployERC7786OpenBridge();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}

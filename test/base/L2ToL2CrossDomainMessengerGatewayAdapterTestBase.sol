// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GetSelectors} from "@diamond-test/helpers/GetSelectors.sol";
import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {
    DeployL2ToL2CrossDomainMessengerGatewayAdapter
} from "@lattice-script/base/crosschain/DeployL2ToL2CrossDomainMessengerGatewayAdapter.s.sol";
import {
    L2ToL2CrossDomainMessengerGatewayAdapter
} from "@lattice/crosschain/L2ToL2CrossDomainMessengerGatewayAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title L2ToL2CrossDomainMessengerGatewayAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for OP Superchain `L2ToL2CrossDomainMessenger` gateway-adapter facet tests that exercise a REAL
///         {Diamond} rather than a flattened inheritance mock. `setUp` assembles the production
///         {DeployL2ToL2CrossDomainMessengerGatewayAdapter} recipe (ERC165 + AccessControl +
///         L2ToL2CrossDomainMessengerGatewayAdapter + {L2ToL2CrossDomainMessengerGatewayAdapterInit}) and exposes
///         a typed `adapter` handle — so every send / receive / config call routes through the diamond's
///         `delegatecall` dispatch, catching selector/storage/init bugs a mock hides. The messenger is the fixed
///         predeploy constant, so the test etches a `MockL2ToL2Messenger` at that address (NOT the facet under
///         test).
abstract contract L2ToL2CrossDomainMessengerGatewayAdapterTestBase is Test, GetSelectors {
    DeployL2ToL2CrossDomainMessengerGatewayAdapter internal deployer;
    address internal diamond; // the assembled L2ToL2 adapter diamond
    L2ToL2CrossDomainMessengerGatewayAdapter internal adapter; // typed handle (all calls dispatch through it)

    /// @notice Assembles the production L2ToL2 adapter diamond with `admin` as the adapter admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed L2ToL2 adapter diamond.
    function _deployL2ToL2CrossDomainMessengerGatewayAdapter(address admin) internal returns (address diamond_) {
        deployer = new DeployL2ToL2CrossDomainMessengerGatewayAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}

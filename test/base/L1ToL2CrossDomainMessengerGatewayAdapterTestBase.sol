// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {
    DeployL1ToL2CrossDomainMessengerGatewayAdapter
} from "@lattice-script/base/crosschain/DeployL1ToL2CrossDomainMessengerGatewayAdapter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {
    L1ToL2CrossDomainMessengerGatewayAdapter
} from "@lattice/crosschain/optimism/L1ToL2CrossDomainMessengerGatewayAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title L1ToL2CrossDomainMessengerGatewayAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for canonical OP Stack L1<->L2 `CrossDomainMessenger` gateway-adapter facet tests that exercise a
///         REAL {Diamond} rather than a flattened inheritance mock. `setUp` assembles the production
///         {DeployL1ToL2CrossDomainMessengerGatewayAdapter} recipe (ERC165 + AccessControl +
///         L1ToL2CrossDomainMessengerGatewayAdapter + {L1ToL2CrossDomainMessengerGatewayAdapterInit}) and exposes
///         a typed `adapter` handle — so every send / receive / config call routes through the diamond's
///         `delegatecall` dispatch, catching selector/storage/init bugs a mock hides. The messenger is the fixed
///         predeploy constant, so the test etches a `MockCrossDomainMessenger` at that address (NOT the facet under
///         test).
abstract contract L1ToL2CrossDomainMessengerGatewayAdapterTestBase is Test, GetSelectors {
    DeployL1ToL2CrossDomainMessengerGatewayAdapter internal deployer;
    address internal diamond; // the assembled L1<->L2 adapter diamond
    L1ToL2CrossDomainMessengerGatewayAdapter internal adapter; // typed handle (all calls dispatch through it)

    /// @notice Assembles the production L1<->L2 adapter diamond with the given counterpart config.
    /// @param admin              The address granted `DEFAULT_ADMIN_ROLE`.
    /// @param counterpartChainId The paired-domain chain id.
    /// @param counterpartAdapter The sibling adapter on the paired domain.
    /// @param minGasLimit        The relay `minGasLimit`.
    /// @return diamond_ The deployed L1<->L2 adapter diamond.
    function _deployL1ToL2CrossDomainMessengerGatewayAdapter(
        address admin,
        uint256 counterpartChainId,
        address counterpartAdapter,
        uint32 minGasLimit
    ) internal returns (address diamond_) {
        deployer = new DeployL1ToL2CrossDomainMessengerGatewayAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) =
            deployer.buildCuts(admin, counterpartChainId, counterpartAdapter, minGasLimit);

        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}

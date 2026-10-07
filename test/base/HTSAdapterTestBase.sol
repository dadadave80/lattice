// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployHTSAdapter} from "@lattice-script/base/tokens/DeployHTSAdapter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {HTSAdapter} from "@lattice/tokens/hedera/HTSAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title HTSAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for Hedera Token Service facet tests that exercise a REAL {Diamond} rather than a flattened
///         inheritance mock. `setUp` assembles the production {DeployHTSAdapter} recipe (ERC165 + AccessControl
///         + HTSAdapter + DiamondLoupe + AccessControlDiamondCut + Receive + {HTSAdapterInit}) and exposes a
///         typed `htsAdapter` handle — so every HTS call routes through the diamond's `delegatecall` dispatch,
///         which is also the frame semantics HTS itself keys on (only `delegatableContractId` keys activate).
///         Role gating is enforced by the cut-in `AccessControl` facet; `supportsInterface` by `ERC165Facet`.
abstract contract HTSAdapterTestBase is Test, GetSelectors {
    DeployHTSAdapter internal deployer;
    address internal diamond; // the assembled HTS diamond
    HTSAdapter internal htsAdapter; // typed handle on the diamond (HTS calls dispatch through it)

    /// @notice Assembles the production HTS diamond with `admin` as the HTS manager / operator admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`, `HTS_MANAGER_ROLE` and `HTS_OPERATOR_ROLE`.
    /// @return diamond_ The deployed HTS diamond.
    function _deployHTSAdapter(address admin) internal returns (address diamond_) {
        deployer = new DeployHTSAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}

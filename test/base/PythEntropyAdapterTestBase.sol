// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployPythEntropyAdapter} from "@lattice-script/base/oracles/DeployPythEntropyAdapter.s.sol";
import {GetSelectors} from "@lattice-test/helpers/GetSelectors.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {PythEntropyAdapter} from "@lattice/oracles/pyth/PythEntropyAdapter.sol";
import {Test} from "forge-std/Test.sol";

/// @title PythEntropyAdapterTestBase
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Base for Pyth Entropy facet tests that exercise a REAL {Diamond} rather than a flattened inheritance
///         mock. `setUp` assembles the production {DeployPythEntropyAdapter} recipe (ERC165 + AccessControl +
///         PythEntropyAdapter + {PythEntropyAdapterInit}) and exposes a typed `entropyContract` handle — so
///         every entropy call routes through the diamond's `delegatecall` dispatch, catching selector/storage/
///         init bugs a mock hides. Admin gating is enforced by the cut-in `AccessControl` facet;
///         `supportsInterface` by `ERC165Facet`.
abstract contract PythEntropyAdapterTestBase is Test, GetSelectors {
    DeployPythEntropyAdapter internal deployer;
    address internal diamond; // the assembled entropy diamond
    PythEntropyAdapter internal entropyContract; // typed handle on the diamond (entropy calls dispatch through it)

    /// @notice Assembles the production Pyth Entropy diamond with `admin` as the entropy admin.
    /// @param admin The address granted `DEFAULT_ADMIN_ROLE`.
    /// @return diamond_ The deployed entropy diamond.
    function _deployPythEntropyAdapter(address admin) internal returns (address diamond_) {
        deployer = new DeployPythEntropyAdapter();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCuts(admin);

        Lattice d = new Lattice();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }
}

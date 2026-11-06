// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {Receive as LatticeReceive} from "@lattice/Receive.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlDiamondCut} from "@lattice/governance/AccessControlDiamondCut.sol";
import {HSSAdapter} from "@lattice/oracles/hedera/HSSAdapter.sol";
import {HSSAdapterInit} from "@lattice/oracles/hedera/HSSAdapterInit.sol";
import {HSSAdapterRecovery} from "@lattice/oracles/hedera/HSSAdapterRecovery.sol";

/// @title DeployHSSAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice HSS diamond with scheduler access, generation-bound recovery, upgrades and HBAR funding.
/// @dev Native callback sender remains unverified; this recipe's offline tests do not establish it.
contract DeployHSSAdapter is BaseDeploy {
    function buildCuts(address admin) public returns (FacetCut[] memory cuts, address init, bytes memory data) {
        cuts = new FacetCut[](7);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new HSSAdapter()));
        cuts[3] = _cut(address(new HSSAdapterRecovery()));
        cuts[4] = _cut(address(new DiamondLoupeFacet()));
        cuts[5] = _cut(address(new AccessControlDiamondCut()));
        cuts[6] = _cut(address(new LatticeReceive()));
        (init, data) =
            _withUpgradeableIntrospection(address(new HSSAdapterInit()), abi.encodeCall(HSSAdapterInit.init, (admin)));
    }

    function run(address admin) external returns (address diamond) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory data) = buildCuts(admin);
        diamond = _assemble(cuts, init, data);
        vm.stopBroadcast();
    }
}

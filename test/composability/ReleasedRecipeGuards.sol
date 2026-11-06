// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {MultiInit} from "@diamond/initializers/MultiInit.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {AccountReleaseInventory} from "@lattice-script/lib/AccountReleaseInventory.sol";
import {ArachnidDeployer} from "@lattice-script/lib/ArachnidDeployer.sol";
import {FacetInventory} from "@lattice-script/lib/FacetInventory.sol";
import {InitInventory} from "@lattice-script/lib/InitInventory.sol";
import {RecipeGuards} from "@lattice-test/composability/RecipeGuards.sol";
import {ArachnidProxy} from "@lattice-test/helpers/ArachnidProxy.sol";
import {LatticeVersion} from "@lattice/LatticeVersion.sol";

/// @title ReleasedRecipeGuards
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Applies the release address contract to every canonical recipe guard, including nested initializers.
/// @dev The interface-routing harness intentionally keeps its separate custom, unreleased fixture contracts.
abstract contract ReleasedRecipeGuards is RecipeGuards {
    error UnreleasedRecipeFacet(address facet);
    error UnreleasedRecipeInitializer(address initializer);
    error InvalidRecipeMultiInitCalldata();

    mapping(address => bool) private _releasedFacets;
    mapping(address => bool) private _releasedInitializers;
    address private _multiInit;

    constructor() {
        vm.etch(ArachnidProxy.PROXY, ArachnidProxy.RUNTIME);
        (string[] memory names, string[] memory paths) = FacetInventory.inventory();
        for (uint256 i; i < names.length; ++i) {
            _releasedFacets[_releaseAddress(names[i], paths[i])] = true;
        }
        (names, paths) = InitInventory.inventory();
        for (uint256 i; i < names.length; ++i) {
            address at = _releaseAddress(names[i], paths[i]);
            _releasedInitializers[at] = true;
            if (keccak256(bytes(names[i])) == keccak256("MultiInit")) _multiInit = at;
        }
    }

    function _releaseAddress(string memory name, string memory artifact) private view returns (address) {
        return ArachnidDeployer.predict(
            keccak256(abi.encodePacked("lattice.", name, ".", LatticeVersion.VERSION)), keccak256(vm.getCode(artifact))
        );
    }

    function _assertReleasedCuts(FacetCut[] memory cuts) internal view {
        for (uint256 i; i < cuts.length; ++i) {
            if (!_releasedFacets[cuts[i].facetAddress]) revert UnreleasedRecipeFacet(cuts[i].facetAddress);
            assertGt(cuts[i].facetAddress.code.length, 0, "released facet code missing");
        }
    }

    /// @dev Account initializers bind an EntryPoint in their constructor and are not stateless inventory entries.
    function _assertReleasedAccount(bool modular, address entryPoint, FacetCut[] memory cuts, address init)
        internal
        view
    {
        _assertReleasedCuts(cuts);
        AccountReleaseInventory.Entry memory entry = AccountReleaseInventory.describe(modular, entryPoint);
        address expected = ArachnidDeployer.predict(
            keccak256(abi.encodePacked("lattice.", entry.initializer, ".", LatticeVersion.VERSION)),
            keccak256(abi.encodePacked(vm.getCode(entry.initializerArtifact), abi.encode(entryPoint)))
        );
        assertEq(init, expected, "constructor-bound account initializer");
        assertGt(init.code.length, 0, "account initializer code missing");
    }

    function _assertReleasedInitializer(address init, bytes memory data) internal view {
        if (!_releasedInitializers[init]) revert UnreleasedRecipeInitializer(init);
        assertGt(init.code.length, 0, "released initializer code missing");
        if (init != _multiInit) return;
        if (data.length < 4 || bytes4(data) != MultiInit.multiInit.selector) {
            revert InvalidRecipeMultiInitCalldata();
        }
        bytes memory args = new bytes(data.length - 4);
        for (uint256 i; i < args.length; ++i) {
            args[i] = data[i + 4];
        }
        (address[] memory inits, bytes[] memory calldatas) = abi.decode(args, (address[], bytes[]));
        assertEq(inits.length, calldatas.length, "initializer count");
        for (uint256 i; i < inits.length; ++i) {
            _assertReleasedInitializer(inits[i], calldatas[i]);
        }
    }

    function _assemble(FacetCut[] memory cuts, address init, bytes memory data)
        internal
        virtual
        override
        returns (address)
    {
        _assertReleasedCuts(cuts);
        _assertReleasedInitializer(init, data);
        return super._assemble(cuts, init, data);
    }

    function _assembleMulti(FacetCut[] memory cuts, address[] memory inits, bytes[] memory calldatas)
        internal
        virtual
        override
        returns (address)
    {
        if (_multiInit.code.length == 0) {
            ArachnidDeployer.deploy(
                keccak256(abi.encodePacked("lattice.MultiInit.", LatticeVersion.VERSION)),
                vm.getCode("MultiInit.sol:MultiInit")
            );
        }
        return _assemble(cuts, _multiInit, abi.encodeCall(MultiInit.multiInit, (inits, calldatas)));
    }
}

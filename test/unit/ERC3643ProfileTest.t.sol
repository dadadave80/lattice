// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {ERC3643TestBase} from "@lattice-test/base/ERC3643TestBase.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {RecipeEntry} from "@lattice/interfaces/ILatticeFactory.sol";
import {IERC8153} from "@lattice/interfaces/external/ercs/IERC8153.sol";
import {ERC3643Init} from "@lattice/tokens/ERC3643/ERC3643Init.sol";
import {ERC3643Params} from "@lattice/tokens/ERC3643/ERC3643Params.sol";
import {
    ERC3643MissingRoutes,
    ERC3643UnexpectedFacet,
    ERC3643UnexpectedHost
} from "@lattice/tokens/ERC3643/libraries/ERC3643ProfileLib.sol";

contract ERC3643UnknownMover {
    function unreviewedMovement(address, uint256) external {}
}

contract ERC3643BindingSentinel {
    error BindingReached();

    function getTokenBound() external pure returns (address) {
        return address(0);
    }

    function bindToken(address) external pure {
        revert BindingReached();
    }
}

contract ERC3643NativeExecutionHost is Lattice {
    function nativeExecute(address target, bytes calldata data) external {
        (bool ok,) = target.delegatecall(data);
        require(ok);
    }
}

contract ERC3643ProfileTest is ERC3643TestBase {
    function deployCuts(FacetCut[] memory cuts, address init, bytes memory data) external returns (address) {
        return factory.deploy(new RecipeEntry[](0), cuts, init, data, bytes32(++nonce));
    }

    function _reject(FacetCut[] memory cuts, address init, bytes memory data, bytes4 errorSelector) internal {
        (bool ok, bytes memory result) = address(this).call(abi.encodeCall(this.deployCuts, (cuts, init, data)));
        assertFalse(ok, "unreviewed composition admitted");
        assertEq(bytes4(result), errorSelector, "must reach profile rejection, not a kernel selector collision");
    }

    function _append(FacetCut[] memory cuts, FacetCut memory last) internal pure returns (FacetCut[] memory all) {
        all = new FacetCut[](cuts.length + 1);
        for (uint256 i; i < cuts.length; ++i) {
            all[i] = cuts[i];
        }
        all[cuts.length] = last;
    }

    function _selectors(address facet) internal view returns (bytes4[] memory selectors) {
        bytes memory packed = IERC8153(facet).exportSelectors();
        selectors = new bytes4[](packed.length / 4);
        for (uint256 i; i < selectors.length; ++i) {
            bytes4 sel;
            assembly ("memory-safe") { sel := mload(add(add(packed, 32), mul(i, 4))) }
            selectors[i] = sel;
        }
    }

    function test_ActualCodeHashRequiredNotSelfReportedSelectors() public {
        (FacetCut[] memory cuts, address init, bytes memory data) = recipe.buildCuts(_config(false));
        bytes4[] memory one = new bytes4[](1);
        one[0] = ERC3643UnknownMover.unreviewedMovement.selector;
        cuts = _append(cuts, FacetCut(address(new ERC3643UnknownMover()), FacetCutAction.Add, one));
        _reject(cuts, init, data, ERC3643UnexpectedFacet.selector);
    }

    function test_AdmissionRunsBeforeExternalBinding() public {
        ERC3643Params memory config = _config(false);
        config.compliance = address(new ERC3643BindingSentinel());
        (FacetCut[] memory cuts, address init, bytes memory data) = recipe.buildCuts(config);
        bytes4[] memory one = new bytes4[](1);
        one[0] = ERC3643UnknownMover.unreviewedMovement.selector;
        cuts = _append(cuts, FacetCut(address(new ERC3643UnknownMover()), FacetCutAction.Add, one));
        _reject(cuts, init, data, ERC3643UnexpectedFacet.selector);
    }

    function test_MissingRequiredFacetRejected() public {
        (FacetCut[] memory cuts, address init, bytes memory data) = recipe.buildCuts(_config(false));
        // Mandatory-route admission detects an absent ERC165 facet independently of initializer calls.
        FacetCut[] memory all = new FacetCut[](cuts.length - 1);
        uint256 n;
        for (uint256 i; i < cuts.length; ++i) {
            if (i != 0) all[n++] = cuts[i];
        }
        assertEq(n, all.length);
        _reject(all, init, data, ERC3643MissingRoutes.selector);
    }

    function test_ExtraSelectorOnApprovedCodeRejected() public {
        (FacetCut[] memory cuts, address init, bytes memory data) = recipe.buildCuts(_config(false));
        bytes4[] memory extra = new bytes4[](cuts[3].functionSelectors.length + 1);
        for (uint256 i; i < extra.length - 1; ++i) {
            extra[i] = cuts[3].functionSelectors[i];
        }
        extra[extra.length - 1] = bytes4(0xdeadbeef);
        cuts[3].functionSelectors = extra;
        _reject(cuts, init, data, ERC3643UnexpectedFacet.selector);
    }

    function test_SplitRequiredRoutesAcrossDuplicateApprovedCodeRejected() public {
        (FacetCut[] memory cuts, address init, bytes memory data) = recipe.buildCuts(_config(false));
        bytes4[] memory one = new bytes4[](1);
        one[0] = cuts[3].functionSelectors[0];
        bytes4[] memory rest = new bytes4[](cuts[3].functionSelectors.length - 1);
        for (uint256 i; i < rest.length; ++i) {
            rest[i] = cuts[3].functionSelectors[i + 1];
        }
        cuts[3].functionSelectors = rest;
        cuts = _append(cuts, FacetCut(deployCode("ERC3643.sol:ERC3643"), FacetCutAction.Add, one));
        _reject(cuts, init, data, ERC3643UnexpectedFacet.selector);
    }

    function test_MissingReadOnlyRegistryRouteRejected() public {
        (FacetCut[] memory cuts, address init, bytes memory data) = recipe.buildCuts(_config(false));
        bytes4[] memory rest = new bytes4[](cuts[5].functionSelectors.length - 1);
        uint256 n;
        for (uint256 i; i < cuts[5].functionSelectors.length; ++i) {
            bytes4 sel = cuts[5].functionSelectors[i];
            if (sel != bytes4(keccak256("isVerified(address)"))) rest[n++] = sel;
        }
        assertEq(n, rest.length);
        cuts[5].functionSelectors = rest;
        _reject(cuts, init, data, ERC3643UnexpectedFacet.selector);
    }

    function test_OptionalApprovalRouteMustMatchConfigurationInBothDirections() public {
        (FacetCut[] memory cuts, address init,) = recipe.buildCuts(_config(true));
        _reject(cuts, init, abi.encodeCall(ERC3643Init.init, (_config(false))), ERC3643UnexpectedFacet.selector);
        (cuts, init,) = recipe.buildCuts(_config(false));
        _reject(cuts, init, abi.encodeCall(ERC3643Init.init, (_config(true))), ERC3643MissingRoutes.selector);
    }

    function test_AllAlternateMoversAndControlRoutesAreRejectedByActualAdmission() public {
        string[17] memory facets = [
            "ERC20",
            "ERC20Burnable",
            "ERC20Votes",
            "ERC20Wrapper",
            "ERC4626",
            "ERC20FlashMint",
            "ERC20Crosschain",
            "ERC7802",
            "ERC1363",
            "ERC20Permit",
            "VaultCore",
            "GovernedVault",
            "Pausable",
            "AccessControl",
            "AccessControlDiamondCut",
            "GovernedDiamondCut",
            "SafeDiamondCut"
        ];
        for (uint256 f; f < facets.length; ++f) {
            (FacetCut[] memory cuts, address init, bytes memory data) = recipe.buildCuts(_config(false));
            address facet = deployCode(string.concat(facets[f], ".sol:", facets[f]));
            bytes4[] memory selectors = _selectors(facet);
            // Remove existing owners for overlapping selectors before adding the actual alternate facet.
            // This reaches canonical profile admission instead of passing on a kernel Add collision.
            for (uint256 i; i < cuts.length; ++i) {
                bytes4[] memory kept = new bytes4[](cuts[i].functionSelectors.length);
                uint256 n;
                for (uint256 j; j < cuts[i].functionSelectors.length; ++j) {
                    bool overlap;
                    for (uint256 k; k < selectors.length; ++k) {
                        if (cuts[i].functionSelectors[j] == selectors[k]) overlap = true;
                    }
                    if (!overlap) kept[n++] = cuts[i].functionSelectors[j];
                }
                assembly ("memory-safe") { mstore(kept, n) }
                cuts[i].functionSelectors = kept;
            }
            // Drop empty cuts because the kernel rightly rejects them before admission.
            uint256 nonempty;
            for (uint256 i; i < cuts.length; ++i) {
                if (cuts[i].functionSelectors.length != 0) ++nonempty;
            }
            FacetCut[] memory all = new FacetCut[](nonempty + 1);
            uint256 cursor;
            for (uint256 i; i < cuts.length; ++i) {
                if (cuts[i].functionSelectors.length != 0) all[cursor++] = cuts[i];
            }
            all[cursor] = FacetCut(facet, FacetCutAction.Add, selectors);
            _reject(all, init, data, ERC3643UnexpectedFacet.selector);
        }
    }

    function test_RejectsNativeExecutionAndAccountHosts() public {
        (FacetCut[] memory cuts, address init, bytes memory data) = recipe.buildCuts(_config(false));
        address[3] memory hosts = [
            address(new ERC3643NativeExecutionHost()),
            deployCode("AccountDiamond.sol:AccountDiamond"),
            deployCode("ModularAccount6900.sol:ModularAccount6900")
        ];
        for (uint256 i; i < hosts.length; ++i) {
            (bool ok, bytes memory result) = hosts[i].call(abi.encodeCall(Lattice.initialize, (cuts, init, data)));
            assertFalse(ok);
            assertEq(bytes4(result), ERC3643UnexpectedHost.selector);
        }
        // Model an account delegation host executing the same ABI at a different runtime address.
        address delegated = address(0xD3136A7E);
        vm.etch(delegated, hosts[0].code);
        (bool success, bytes memory reason) = delegated.call(abi.encodeCall(Lattice.initialize, (cuts, init, data)));
        assertFalse(success);
        assertEq(bytes4(reason), ERC3643UnexpectedHost.selector);
    }

    function test_ProfileCannotBeReinitializedOrAdvertiseArbitraryCutAuthority() public {
        (FacetCut[] memory cuts, address init, bytes memory data) = recipe.buildCuts(_config(false));
        vm.expectRevert();
        Lattice(payable(diamond)).initialize(cuts, init, data);
        (bool ok,) = diamond.call(
            abi.encodeWithSignature("diamondCut((address,uint8,bytes4[])[],address,bytes)", cuts, init, data)
        );
        assertFalse(ok);
        (ok,) = diamond.call(abi.encodeWithSignature("grantRole(bytes32,address)", bytes32(0), alice));
        assertFalse(ok);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {CreateXDeployer} from "@lattice-script/lib/CreateXDeployer.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/governance/IGovernedDiamondCut.sol";
import {Script, console} from "forge-std/Script.sol";

/// @title ProposeGovernedCut
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Dependency-free helper that assembles the EXACT calldata an operator pastes into
///         OpenZeppelin Defender (Admin / Proposals) to drive a governed diamond cut. It produces the
///         two artifacts a Defender proposal needs and NOTHING else: (1) the deterministic on-chain
///         TARGET, and (2) the `diamondCut(0x1f931c1c)` CALLDATA. It deliberately imports no Defender
///         SDK and broadcasts nothing — it only logs.
///
/// @dev WHY NO SDK: the OpenZeppelin Defender Solidity SDK (`Defender.proposeUpgrade`-style helpers in
///      `openzeppelin-foundry-upgrades`) is an OPTIONAL external dependency and is intentionally NOT
///      vendored into Lattice (see `docs/upgrades/OZ_DEFENDER_AND_UPGRADES.md`). Defender consumes
///      raw `(target, value, data)` for a custom proposal, so this calldata is sufficient on its own.
///
/// The on-chain effect of executing the produced proposal is EXACTLY:
///   GovernedDiamondCut.diamondCut(cuts, init, initCalldata)
/// gated by EmergencyStop -> UPGRADE_EXECUTOR_ROLE inside the diamond (see {GovernedDiamondCutLib}).
///
/// Usage — single-selector "Add" cut, deriving the diamond's deterministic CreateX address:
///   forge script script/governance/ProposeGovernedCut.s.sol \
///     --sig "addSelector(bytes11,address,bytes4)" <DIAMOND_ENTROPY> <NEW_FACET> <SELECTOR>
///
/// Usage — single-selector "Add" cut against a known diamond address:
///   forge script script/governance/ProposeGovernedCut.s.sol \
///     --sig "addSelectorAt(address,address,bytes4)" <DIAMOND> <NEW_FACET> <SELECTOR>
contract ProposeGovernedCut is Script {
    /// @notice Build the Defender payload for adding ONE selector, resolving the diamond's
    ///         deterministic CreateX CREATE3 address from `diamondEntropy` (broadcast by `msg.sender`).
    /// @dev The address derivation matches {CreateXDeployer.predict} used by `UpgradeDiamond.s.sol`, so
    ///      the target is identical on every chain the diamond was deployed to.
    /// @param diamondEntropy 11 bytes identifying the diamond deployment (same entropy used to deploy it).
    /// @param newFacet The CreateX-deployed facet contract providing the new function.
    /// @param selector The function selector to add.
    function addSelector(bytes11 diamondEntropy, address newFacet, bytes4 selector) external view {
        bytes32 salt = CreateXDeployer._guardedSalt(msg.sender, diamondEntropy);
        address diamond = CreateXDeployer.predict(salt);
        _logProposal(diamond, _singleCut(newFacet, selector, FacetCutAction.Add));
    }

    /// @notice Build the Defender payload for adding ONE selector against an explicit diamond address.
    /// @param diamond The governed diamond proxy (Defender proposal TARGET).
    /// @param newFacet The facet contract providing the new function.
    /// @param selector The function selector to add.
    function addSelectorAt(address diamond, address newFacet, bytes4 selector) external pure {
        _logProposal(diamond, _singleCut(newFacet, selector, FacetCutAction.Add));
    }

    /// @notice Build the Defender payload for REPLACING one selector against an explicit diamond.
    /// @dev A `Replace` is the cut a storage-layout compatibility check must precede (see the docs'
    ///      pre-cut checklist): the new facet must keep every prior ERC-7201 struct field append-only.
    /// @param diamond The governed diamond proxy (Defender proposal TARGET).
    /// @param newFacet The replacement facet contract.
    /// @param selector The function selector to replace.
    function replaceSelectorAt(address diamond, address newFacet, bytes4 selector) external pure {
        _logProposal(diamond, _singleCut(newFacet, selector, FacetCutAction.Replace));
    }

    /// @notice Logs the deterministic TARGET and the `diamondCut` CALLDATA for a no-init cut.
    /// @dev `_init`/`_calldata` are zeroed here (no post-cut delegatecall). For a cut that DOES carry a
    ///      reinitializer `_init`, encode it off-script and remember to run the reinitializer-monotonic
    ///      pre-flight (`DiamondValidationLib.assertReinitializerMonotonic`) first — see the docs.
    function _logProposal(address diamond, FacetCut[] memory cuts) private pure {
        bytes memory cutCalldata =
            abi.encodeWithSelector(IGovernedDiamondCut.diamondCut.selector, cuts, address(0), bytes(""));

        console.log("=== OpenZeppelin Defender custom-proposal payload ===");
        console.log("Target (to):     ", diamond);
        console.log("Value (wei):     ", uint256(0));
        console.log("Function:         diamondCut(0x1f931c1c)");
        console.log("Calldata (data): ");
        console.logBytes(cutCalldata);
    }

    function _singleCut(address facet, bytes4 selector, FacetCutAction action)
        private
        pure
        returns (FacetCut[] memory cuts)
    {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = selector;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: facet, action: action, functionSelectors: sels});
    }
}

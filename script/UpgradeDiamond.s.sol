// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {CreateXDeployer} from "@lattice-script/lib/CreateXDeployer.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/IGovernedDiamondCut.sol";
import {IGovernor} from "@lattice/interfaces/IGovernor.sol";
import {Script, console} from "forge-std/Script.sol";

/// @title UpgradeDiamond
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Helper script to (1) deterministically DEPLOY the Diamond + facets cross-chain via CreateX
///         CREATE3, and (2) assemble/submit a governance-gated diamond upgrade.
///
/// Deterministic deploy: facets and the Diamond are deployed through {CreateXDeployer} (CreateX
/// CREATE3). The resulting address depends only on `(CreateX, guardedSalt)` — NOT on the contract
/// initcode — so the Diamond proxy and every facet land at the SAME address on every chain and
/// survive bytecode/compiler changes. `predict()` pre-computes the Diamond address before broadcast.
///
/// A governed cut is just a normal governance proposal whose single action calls the diamond's own
/// `diamondCut(0x1f931c1c)`:
///
///   targets   = [diamond]
///   values    = [0]
///   calldatas = [abi.encodeWithSelector(IGovernedDiamondCut.diamondCut.selector, cuts, init, initCalldata)]
///
/// The proposal then follows the normal lifecycle: propose -> vote -> queue -> timelock delay ->
/// execute, at which point the timelock relays the call back into the diamond, the
/// EmergencyStop + UPGRADE_EXECUTOR_ROLE guard passes (caller == timelock == executor, role held by
/// the diamond), and `DiamondLib.diamondCut` applies the cut.
///
/// Usage (predict the deterministic Diamond address for an entropy tag):
///   forge script script/UpgradeDiamond.s.sol \
///     --sig "predictDiamond(bytes11)" 0x0102030405060708090a0b
///
/// Usage (dry-run governed-cut assembly + log):
///   forge script script/UpgradeDiamond.s.sol \
///     --sig "run(address,address,bytes4)" <DIAMOND> <NEW_FACET> <SELECTOR>
///
/// To broadcast deploys/proposals, set PRIVATE_KEY / RPC and add `--broadcast`, then uncomment the
/// `vm.startBroadcast()` blocks below.
contract UpgradeDiamond is Script {
    //*//////////////////////////////////////////////////////////////////////////
    //                     DETERMINISTIC DEPLOY (CreateX CREATE3)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Pre-computes the deterministic CREATE3 address the Diamond will occupy on EVERY chain
    ///         for a given entropy tag, broadcast by `msg.sender` (the script's deployer).
    /// @dev Pure prediction — no broadcast. The same `(deployer, entropy)` yields the same address on
    ///      every chain because CREATE3 ignores initcode.
    /// @param entropy 11 bytes distinguishing this Diamond deployment from others by the same deployer.
    /// @return diamond The deterministic Diamond address.
    function predictDiamond(bytes11 entropy) external view returns (address diamond) {
        bytes32 salt = CreateXDeployer._guardedSalt(msg.sender, entropy);
        diamond = CreateXDeployer.predict(salt);
        console.log("Predicted Diamond (all chains):", diamond);
    }

    /// @notice Deploys one facet deterministically via CreateX CREATE3.
    /// @dev Same `(deployer, entropy, _)` ⇒ same facet address on every chain, independent of the
    ///      facet's bytecode (so a recompiled facet keeps its address — upgrade-stable).
    /// @param entropy 11 bytes of per-facet entropy (distinct per facet to avoid salt collisions).
    /// @param creationCode The facet's full creation bytecode (`type(Facet).creationCode`, no args —
    ///        facets are stateless and constructor-less in Lattice's three-layer model).
    /// @return facet The deterministic facet address.
    function deployFacet(bytes11 entropy, bytes memory creationCode) public returns (address facet) {
        bytes32 salt = CreateXDeployer._guardedSalt(msg.sender, entropy);
        facet = CreateXDeployer.deploy(salt, creationCode);
        console.log("Deployed facet:", facet);
    }

    /// @notice Deploys the Diamond deterministically via CreateX CREATE3 at the predicted address.
    /// @dev The Diamond's initcode embeds its constructor args (owner + initial DiamondCutFacet, or
    ///      the GovernedDiamondCut facet for a governed deployment). Because CREATE3 ignores initcode,
    ///      the Diamond address is identical on every chain regardless of those args. Asserts the
    ///      deployed address equals {predictDiamond} to catch any deployer/entropy mismatch.
    /// @param entropy 11 bytes identifying this Diamond deployment.
    /// @param diamondInitCode The Diamond's full creation bytecode incl. ABI-encoded constructor args.
    /// @return diamond The deterministic Diamond address (== predicted).
    function deployDiamond(bytes11 entropy, bytes memory diamondInitCode) public returns (address diamond) {
        bytes32 salt = CreateXDeployer._guardedSalt(msg.sender, entropy);
        address predicted = CreateXDeployer.predict(salt);
        diamond = CreateXDeployer.deploy(salt, diamondInitCode);
        require(diamond == predicted, "UpgradeDiamond: deployed != predicted");
        console.log("Deployed Diamond (deterministic, all chains):", diamond);
    }

    /// @notice Example end-to-end deterministic deploy: deploy a facet then the Diamond, both via
    ///         CREATE3, and log the predicted-vs-deployed Diamond address. Broadcast-guarded.
    /// @dev Wire your real Diamond + facet creation code in place of the placeholders before use.
    function deployAll(
        bytes11 diamondEntropy,
        bytes11 facetEntropy,
        bytes memory facetCode,
        bytes memory diamondInitCode
    ) external {
        vm.startBroadcast();
        address facet = deployFacet(facetEntropy, facetCode);
        address diamond = deployDiamond(diamondEntropy, diamondInitCode);
        vm.stopBroadcast();
        console.log("facet:", facet);
        console.log("diamond:", diamond);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            GOVERNED CUT ASSEMBLY
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Build a single-selector "Add" cut and emit the proposal payload.
    /// @param diamond The governed Diamond proxy (also the proposal target).
    /// @param newFacet The facet contract providing the new function.
    /// @param selector The function selector to add.
    function run(address diamond, address newFacet, bytes4 selector) external {
        FacetCut[] memory cuts = _singleAddCut(newFacet, selector);
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory description) =
            buildProposal(diamond, cuts, address(0), bytes(""), "Governed cut: add selector");

        console.log("Diamond / proposal target:", targets[0]);
        console.log("Proposal value[0]:", values[0]);
        console.log("Proposal description:", description);
        console.logBytes(calldatas[0]);

        // --- To actually submit, uncomment and supply a funded proposer with voting power: ---
        // vm.startBroadcast();
        // uint256 proposalId = IGovernor(diamond).propose(targets, values, calldatas, description);
        // console.log("proposalId:", proposalId);
        // vm.stopBroadcast();
    }

    /// @notice Assembles the governance proposal arrays for a governed cut.
    /// @param diamond The governed Diamond (proposal target and cut subject).
    /// @param cuts The FacetCut array to apply.
    /// @param init The init address delegatecalled after the cut (address(0) to skip).
    /// @param initCalldata The calldata for `init`.
    /// @param description Human-readable proposal description.
    function buildProposal(
        address diamond,
        FacetCut[] memory cuts,
        address init,
        bytes memory initCalldata,
        string memory description
    )
        public
        pure
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory desc)
    {
        targets = new address[](1);
        targets[0] = diamond;
        values = new uint256[](1);
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(IGovernedDiamondCut.diamondCut.selector, cuts, init, initCalldata);
        desc = description;
    }

    function _singleAddCut(address facet, bytes4 selector) internal pure returns (FacetCut[] memory cuts) {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = selector;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: facet, action: FacetCutAction.Add, functionSelectors: sels});
    }
}

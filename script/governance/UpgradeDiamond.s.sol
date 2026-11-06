// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {CreateXDeployer} from "@lattice-script/lib/CreateXDeployer.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/governance/IGovernedDiamondCut.sol";
import {IGovernor} from "@lattice/interfaces/governance/IGovernor.sol";
import {Script, console} from "forge-std/Script.sol";

/// @title UpgradeDiamond
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Helper script to (1) deterministically DEPLOY the Diamond + facets cross-chain via CreateX
///         CREATE3, and (2) assemble/submit a governance-gated diamond upgrade.
///
/// Deterministic deploy: facets and the Diamond are deployed through {CreateXDeployer} (CreateX
/// CREATE3). The resulting address depends only on `(CreateX, guardedSalt)` — NOT on the contract
/// initcode. The guarded salt includes the deployer and `block.chainid`, so each chain gets a different
/// address. Changing bytecode leaves that chain's prediction unchanged; an occupied address cannot be
/// deployed again. {predictDiamond} pre-computes the address on the selected chain before broadcast.
///
/// A governed cut is just a normal governance proposal whose single action calls the diamond's own
/// `diamondCut(0x1f931c1c)`:
///
///   targets   = [diamond]
///   values    = [0]
///   calldatas = [abi.encodeWithSelector(IGovernedDiamondCut.diamondCut.selector, cuts, init, initCalldata)]
///
/// The proposal then follows the normal lifecycle: propose -> vote -> queue -> timelock delay ->
/// execute. With a co-located TimelockController, its external call back to the diamond makes the caller
/// the diamond itself, which holds UPGRADE_EXECUTOR_ROLE; the unstopped GovernedDiamondCut then applies
/// the cut. Governor's zero/self timelock topologies support this route. An external timelock requires
/// the explicit topology opt-out and deliberate external executor setup; the opt-out grants no role.
///
/// Usage (predict the deterministic Diamond address for an entropy tag):
///   forge script script/governance/UpgradeDiamond.s.sol \
///     --sig "predictDiamond(bytes11)" 0x0102030405060708090a0b
///
/// Usage (dry-run governed-cut assembly + log):
///   forge script script/governance/UpgradeDiamond.s.sol \
///     --sig "run(address,address,bytes4)" <DIAMOND> <NEW_FACET> <SELECTOR>
///
/// To broadcast deploys/proposals, set PRIVATE_KEY / RPC and add `--broadcast`, then uncomment the
/// `vm.startBroadcast()` blocks below.
contract UpgradeDiamond is Script {
    //*//////////////////////////////////////////////////////////////////////////
    //                     DETERMINISTIC DEPLOY (CreateX CREATE3)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Pre-computes the deterministic CREATE3 address the Diamond will occupy on this chain
    ///         for a given entropy tag, broadcast by `msg.sender` (the script's deployer).
    /// @dev Prediction only — no broadcast. The same `(deployer, entropy, block.chainid)` yields the
    ///      same address independent of initcode; the guarded salt makes it differ across chains.
    /// @param entropy 11 bytes distinguishing this Diamond deployment from others by the same deployer.
    /// @return diamond The deterministic Diamond address.
    function predictDiamond(bytes11 entropy) external view returns (address diamond) {
        bytes32 salt = CreateXDeployer._guardedSalt(msg.sender, entropy);
        diamond = CreateXDeployer.predict(salt);
        console.log("Predicted Diamond (this chain):", diamond);
    }

    /// @notice Deploys one facet deterministically via CreateX CREATE3.
    /// @dev The same `(deployer, entropy, block.chainid)` yields the same prediction independent of
    ///      facet bytecode. Recompilation does not replace code already deployed at that address.
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
    /// @dev `diamondInitCode` contains creation code and any constructor args required by the chosen
    ///      host. Lattice itself is configured through its atomic initializer, not constructor args.
    ///      CREATE3 ignores initcode, while the guarded salt binds the selected chain and deployer.
    ///      Asserts the deployed address equals {predictDiamond} to catch a deployer/entropy mismatch.
    /// @param entropy 11 bytes identifying this Diamond deployment.
    /// @param diamondInitCode The Diamond's full creation bytecode incl. ABI-encoded constructor args.
    /// @return diamond The deterministic Diamond address (== predicted).
    function deployDiamond(bytes11 entropy, bytes memory diamondInitCode) public returns (address diamond) {
        bytes32 salt = CreateXDeployer._guardedSalt(msg.sender, entropy);
        address predicted = CreateXDeployer.predict(salt);
        diamond = CreateXDeployer.deploy(salt, diamondInitCode);
        require(diamond == predicted, "UpgradeDiamond: deployed != predicted");
        console.log("Deployed Diamond (deterministic, this chain):", diamond);
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

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {RecipePlanLib} from "@lattice-script/lib/RecipePlanLib.sol";
import {
    RecipeAuthority,
    RecipeDeploymentContext,
    RecipeFacet,
    RecipeInitOutputKind,
    RecipeParameter,
    RecipeProxyKind,
    RecipeSeam,
    RecipeSpec,
    RecipeVariant
} from "@lattice-script/lib/RecipeSpec.sol";
import {RecipeSpecLib} from "@lattice-script/lib/RecipeSpecLib.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {GovernedVaultInit, GovernedVaultParams} from "@lattice/defi/GovernedVaultInit.sol";
import {DiamondValidationLib} from "@lattice/governance/libraries/DiamondValidationLib.sol";
import {RecipeEntry} from "@lattice/interfaces/ILatticeFactory.sol";
import {IEmergencyCut} from "@lattice/interfaces/governance/IEmergencyCut.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/governance/IGovernedDiamondCut.sol";
import {IGovernor} from "@lattice/interfaces/governance/IGovernor.sol";
import {ITimelockController} from "@lattice/interfaces/governance/ITimelockController.sol";
import {IVotes} from "@lattice/interfaces/governance/IVotes.sol";

/// @title DeployGovernedVault
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a SELF-GOVERNED ERC-4626 vault: ONE diamond whose vote-weighted shares
///         elect an on-chain Governor + Timelock that governs the vault itself, with no external admin. The
///         diamond hosts the NATURAL facets — each owning ONLY its own selectors (the composability principle):
///         {ERC20} (the share token), {ERC4626} (the vault over the shares), {VaultCore} (strategy hooks),
///         {Votes} (ERC-5805 delegation + clock), {ERC20Votes} (checkpointed vote weight), {Governor},
///         {TimelockController} — plus a thin {GovernedVault} reconciliation facet, and the
///         anti-frozen-diamond set: {DiamondLoupeFacet} (introspection), {EmergencyStop} (guardian surface)
///         and {GovernedDiamondCut} (upgrades, executable ONLY by a passed, timelock-executed proposal).
///         {GovernedVaultInit} wires the Governor's `token`/`timelock` and the vault's admin to the diamond,
///         so share-holders propose → vote → queue → (delay) → execute — including upgrades.
/// @dev A single mega-facet inheriting all of these would blow past EIP-170, so each facet is cut for its OWN
///      selectors and {GovernedVault} owns the handful that either CLASH across facets or are MODIFIED for the
///      single-diamond topology. Those selectors are EXCLUDED from the base facets' cuts (via {_cutExcept}) and
///      provided once by {GovernedVault}:
///      - `name` — excluded from ERC20 and Governor (the share name wins).
///      - `decimals` — excluded from ERC20 (the ERC4626 share-offset variant wins).
///      - `transfer`/`transferFrom` — excluded from ERC20 and ERC20Votes (the checkpoint-seam versions win).
///      - `totalAssets` — excluded from ERC4626 (the VaultCore strategy-aware version wins).
///      - `maxDeposit`/`maxMint` — excluded from ERC4626 (the VaultCore deposit-latch-aware versions win).
///      - `deposit`/`mint`/`withdraw`/`redeem` — excluded from ERC4626 and VaultCore (the checkpoint-seam
///        versions on {GovernedVault} win).
///      - `delegate`/`delegateBySig` — excluded from Votes (the balance-aware {ERC20Votes} versions win).
///      - `clock`/`CLOCK_MODE` — excluded from Votes and Governor (the Votes clock serves both).
///      - `castVoteBySig` — excluded from Governor (the namespaced-nonce version on {GovernedVault} wins).
contract DeployGovernedVault is BaseDeploy {
    /// @notice Builds the self-governed vault diamond cuts + initializer (no broadcast, no proxy deploy).
    function buildCuts(GovernedVaultParams memory p)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        DiamondValidationLib.assertNamespacesDisjoint(storageNamespaces());
        cuts = _buildBaseCuts();
        init = _init("GovernedVaultInit");
        initCalldata = abi.encodeCall(GovernedVaultInit.init, (p));
    }

    /// @notice Both the self-governed builder topology and its public deployment entrypoints as data.
    function recipeSpec() public pure virtual returns (RecipeSpec memory result) {
        result = RecipeSpecLib.spec("DeployGovernedVault", "script/base/defi/DeployGovernedVault.s.sol", 1);
        RecipeVariant memory variant;
        variant.id =
        "DeployGovernedVault:buildCuts((address,string,string,uint8,uint256,uint48,uint32,uint256,uint256))";
        variant.buildSignature = "buildCuts((address,string,string,uint8,uint256,uint48,uint32,uint256,uint256))";
        variant.proxyKind = RecipeProxyKind.Lattice;
        variant.initOutputKind = RecipeInitOutputKind.Single;
        variant.facets = _cutPlan(0);
        variant.seams = _recipeSeams(0);
        variant.inputs = new RecipeParameter[](9);
        variant.inputs[0] = RecipeParameter(
            "p.asset",
            "address",
            "ERC20-contract",
            "target-configured-asset",
            "caller authenticates usable asset and token semantics; initialization permits zero and defaults decimals on failed reads"
        );
        variant.inputs[1] = RecipeParameter(
            "p.name",
            "string",
            "metadata",
            "Example Governed Vault",
            "enforced: nonempty EIP712 domain name; shared by share token and governor"
        );
        variant.inputs[2] = RecipeParameter("p.symbol", "string", "metadata", "EGV", "no length constraint");
        variant.inputs[3] = RecipeParameter(
            "p.decimalsOffset",
            "uint8",
            "decimal-places",
            "0",
            "ABI uint8 only; caller chooses usable asset-decimal and virtual-share arithmetic; no extra initialization clamp"
        );
        variant.inputs[4] = RecipeParameter("p.minDelay", "uint256", "seconds", "300", "zero permitted");
        variant.inputs[5] =
            RecipeParameter("p.votingDelay", "uint48", "seconds", "60", "timestamp clock; zero permitted");
        variant.inputs[6] = RecipeParameter("p.votingPeriod", "uint32", "seconds", "600", "enforced greater than zero");
        variant.inputs[7] = RecipeParameter("p.proposalThreshold", "uint256", "raw-share-votes", "0", "zero permitted");
        variant.inputs[8] = RecipeParameter(
            "p.quorumNumerator", "uint256", "percent-of-vote-supply", "4", "enforced range 0..100; fixed denominator100"
        );
        string[] memory bindings = new string[](9);
        for (uint256 i; i < bindings.length; ++i) {
            bindings[i] = variant.inputs[i].name;
        }
        variant.initPlan = RecipeSpecLib.leaf(
            "GovernedVaultInit",
            "init((address,string,string,uint8,uint256,uint48,uint32,uint256,uint256))",
            variant.inputs,
            bindings
        );
        variant.authorities = new RecipeAuthority[](5);
        variant.authorities[0] = RecipeSpecLib.role(
            "AccessControl",
            "DEFAULT_ADMIN_ROLE",
            "bytes32",
            bytes32(0),
            "diamond-self",
            "self-administered vault and timelock"
        );
        variant.authorities[1] = RecipeSpecLib.role(
            "GovernedDiamondCut",
            "UPGRADE_EXECUTOR_ROLE",
            "bytes32",
            keccak256("UPGRADE_EXECUTOR_ROLE"),
            "diamond-self",
            "self-administered upgrade role; proposals reach the cut through the same diamond"
        );
        variant.authorities[2] = RecipeSpecLib.role(
            "TimelockController",
            "PROPOSER_ROLE",
            "bytes32",
            keccak256("PROPOSER_ROLE"),
            "diamond-self",
            "governor queues operations through the same diamond"
        );
        variant.authorities[3] = RecipeSpecLib.role(
            "TimelockController",
            "CANCELLER_ROLE",
            "bytes32",
            keccak256("CANCELLER_ROLE"),
            "diamond-self",
            "governor cancels its queued operations"
        );
        variant.authorities[4] = RecipeSpecLib.role(
            "TimelockController",
            "EXECUTOR_ROLE",
            "bytes32",
            keccak256("EXECUTOR_ROLE"),
            "address(0)",
            "explicitly open execution of ready non-expired operations"
        );
        variant.conditions = new string[](5);
        variant.conditions[0] = "Governor vote token and timelock are diamond-self; the shared clock is timestamp-based";
        variant.conditions[1] =
            "The governed-cut Governor policy phase and later full Governor initialization retain their original metadata order";
        variant.conditions[2] =
        "UPGRADE_EXECUTOR_ROLE administers itself; DEFAULT_ADMIN_ROLE cannot mint another executor";
        variant.conditions[3] =
            "No emergency guardian is appointed during initialization; later guardians remain trusted for unfrozen-selector liveness";
        variant.conditions[4] =
        "No selectors are frozen at initialization; recommendedFreezeSelectors is a separate governance action";
        result.variants[0] = variant;
        result.deploymentContexts = new RecipeDeploymentContext[](2);
        result.deploymentContexts[0] = RecipeSpecLib.deploymentContext(
            "DeployGovernedVault",
            "run((address,string,string,uint8,uint256,uint48,uint32,uint256,uint256))",
            variant,
            "buildCuts(p)"
        );
        RecipeDeploymentContext memory atomicContext;
        atomicContext.id =
            "DeployGovernedVault:deployAtomic((address,string,string,uint8,uint256,uint48,uint32,uint256,uint256),address,bytes32)";
        atomicContext.signature =
        "deployAtomic((address,string,string,uint8,uint256,uint48,uint32,uint256,uint256),address,bytes32)";
        atomicContext.createsProxy = true;
        atomicContext.variants = new string[](1);
        atomicContext.variants[0] = variant.id;
        atomicContext.inputs = new RecipeParameter[](11);
        for (uint256 i; i < 9; ++i) {
            atomicContext.inputs[i] = variant.inputs[i];
        }
        atomicContext.inputs[9] = RecipeParameter(
            "factory",
            "address",
            "LatticeFactory-contract",
            "target-configured-factory",
            "caller authenticates the supplied factory; no code identity check in this helper"
        );
        atomicContext.inputs[10] = RecipeParameter(
            "salt",
            "bytes32",
            "factory-caller-bound-salt",
            "0x0000000000000000000000000000000000000000000000000000000000000001",
            "factory binds salt to its immediate caller"
        );
        atomicContext.bindings = new string[](2);
        atomicContext.bindings[0] = "buildCuts(p)";
        atomicContext.bindings[1] = "factory.deploy([],cuts,init,calldata,salt)";
        atomicContext.conditions = new string[](1);
        atomicContext.conditions[0] =
        "create and initialize are one factory transaction; an occupied caller-bound salt reverts";
        result.deploymentContexts[1] = atomicContext;
    }

    /// @notice The recommended `freezeSelectors` payload for a deployed vault's first governance proposal: the
    ///         loupe, the cut and emergency entrypoints, and every selector the Governor -> Timelock ->
    ///         `diamondCut` path calls back into the diamond.
    /// @dev Nothing is frozen at init, and an `EMERGENCY_GUARDIAN_ROLE` holder can `emergencyRemoveCut`
    ///      any unfrozen selector except `diamondCut` itself and the stop-recovery selectors
    ///      (`emergencyResume`, `removeGuardian`, `revokeRole`), which the cut library refuses outright
    ///      and so are not listed here. Until this list is frozen the guardian is therefore TRUSTED for
    ///      governance liveness: removing, say, Governor `execute` or Timelock `executeBatch` leaves
    ///      `diamondCut` bound but unreachable. Freezing closes that Governor -> Timelock -> `diamondCut`
    ///      path, so a proposal can still resume a stopped vault and upgrade it, at a cost: a
    ///      frozen selector can never be `Replace`d or `Remove`d again, even by governance, so a bug in a
    ///      frozen function can only be worked around by adding a new selector. `delegate` and the
    ///      share-token movers stay unfrozen; holders who have already delegated can still vote.
    /// @return selectors The 23 selectors to freeze.
    function recommendedFreezeSelectors() public pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](23);
        // Introspection, the upgrade entrypoint and the emergency path.
        selectors[0] = IDiamondLoupe.facets.selector;
        selectors[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        selectors[2] = IDiamondLoupe.facetAddresses.selector;
        selectors[3] = IDiamondLoupe.facetAddress.selector;
        selectors[4] = IGovernedDiamondCut.diamondCut.selector;
        selectors[5] = IEmergencyCut.emergencyRemoveCut.selector;
        // Governor entrypoints: propose -> vote -> queue -> execute.
        selectors[6] = IGovernor.propose.selector;
        selectors[7] = IGovernor.castVote.selector;
        selectors[8] = IGovernor.castVoteWithReason.selector;
        selectors[9] = IGovernor.castVoteWithReasonAndParams.selector;
        selectors[10] = IGovernor.castVoteBySig.selector;
        selectors[11] = IGovernor.queue.selector;
        selectors[12] = IGovernor.execute.selector;
        // Timelock functions the Governor calls on the diamond (its own timelock).
        selectors[13] = ITimelockController.scheduleBatch.selector;
        selectors[14] = ITimelockController.executeBatch.selector;
        selectors[15] = ITimelockController.hashOperationBatch.selector;
        selectors[16] = ITimelockController.getMinDelay.selector;
        selectors[17] = ITimelockController.isOperationPending.selector;
        selectors[18] = ITimelockController.isOperationDone.selector;
        // Vote-token reads the Governor makes on the diamond (its own vote token).
        selectors[19] = IVotes.clock.selector;
        selectors[20] = IVotes.CLOCK_MODE.selector;
        selectors[21] = IVotes.getPastVotes.selector;
        selectors[22] = IVotes.getPastTotalSupply.selector;
    }

    /// @notice Unique storage owners, including dependencies shared across facets.
    /// @dev Initializable and the reentrancy guard use fixed non-ERC-7201 slots; see the guide.
    function storageNamespaces() public pure virtual returns (string[] memory ids) {
        ids = new string[](15);
        ids[0] = "diamond.lib.storage";
        ids[1] = "diamond.lib.storage.ERC165";
        ids[2] = "lattice.storage.AccessControl";
        ids[3] = "lattice.storage.TimelockController";
        ids[4] = "lattice.storage.ERC20";
        ids[5] = "lattice.storage.ERC4626";
        ids[6] = "lattice.storage.VaultCore";
        ids[7] = "lattice.storage.Votes";
        ids[8] = "lattice.storage.Governor";
        ids[9] = "lattice.storage.GovernedVault";
        ids[10] = "lattice.storage.EmergencyStop";
        ids[11] = "lattice.storage.GovernedDiamondCut";
        ids[12] = "lattice.storage.EIP712";
        ids[13] = "lattice.storage.Nonces";
        ids[14] = "lattice.storage.VaultCoreRecovery";
    }

    /// @dev The 14 base facet cuts alone — shared with recipes that EXTEND this one under a different
    ///      initializer (they must not pay for a discarded {GovernedVaultInit} deployment). Cuts 10-12
    ///      are the anti-frozen-diamond set: {DiamondLoupeFacet} (EIP-2535 introspection),
    ///      {EmergencyStop} (guardian halt + resume surface for the governed cut), and
    ///      {GovernedDiamondCut} (the `0x1f931c1c` upgrade path, reachable here ONLY through a passed,
    ///      timelock-executed proposal — see {GovernedVaultInit}; cutting a self-call relay such as
    ///      AccessManager next to it would open a second path). {Receive} lets the timelock hold the
    ///      ETH that proposals spend. All diamond-lib facets are cut via the
    ///      ERC-8153 address helpers (diamond-lib ≥0.2.0 facets self-report their selectors) — no FFI. Every
    ///      facet comes from {_facet}, so on a chain with the Arachnid proxy vaults share one released facet set.
    function _buildBaseCuts() internal returns (FacetCut[] memory cuts) {
        return _materialize(_cutPlan(0), _recipeSeams(0));
    }

    function _cutPlan(uint256 variant) internal pure virtual returns (RecipeFacet[] memory facets) {
        require(variant == 0, "DeployGovernedVault: unknown variant");
        facets = new RecipeFacet[](14);
        facets[0] = RecipePlanLib.all("ERC165Facet");
        facets[1] = RecipePlanLib.all("AccessControl");
        facets[2] = RecipePlanLib.all("TimelockController");
        facets[3] = RecipePlanLib.except("ERC20", _erc20Exclusions());
        facets[4] = RecipePlanLib.except("ERC4626", _erc4626Exclusions());
        facets[5] = RecipePlanLib.except("VaultCore", _vaultExclusions());
        facets[6] = RecipePlanLib.except("Votes", _votesExclusions());
        facets[7] = RecipePlanLib.except("ERC20Votes", _erc20VotesExclusions());
        facets[8] = RecipePlanLib.except("Governor", _governorExclusions());
        facets[9] = RecipePlanLib.all("GovernedVault");
        facets[10] = RecipePlanLib.all("DiamondLoupeFacet");
        facets[11] = RecipePlanLib.all("EmergencyStop");
        facets[12] = RecipePlanLib.all("GovernedDiamondCut");
        facets[13] = RecipePlanLib.all("Receive");
    }

    function _recipeSeams(uint256) internal pure virtual returns (RecipeSeam[] memory seams) {
        seams = new RecipeSeam[](16);
        seams[0] = RecipePlanLib.seam3(
            "share-name",
            bytes4(keccak256("name()")),
            "ERC20",
            "Governor",
            "GovernedVault",
            "GovernedVault",
            "one shared token and governor name"
        );
        seams[1] = RecipePlanLib.seam2(
            "share-decimals",
            bytes4(keccak256("decimals()")),
            "ERC20",
            "ERC4626",
            "ERC4626",
            "share decimals include the virtual-share offset"
        );
        seams[2] = RecipePlanLib.seam3(
            "share-transfer",
            bytes4(keccak256("transfer(address,uint256)")),
            "ERC20",
            "ERC20Votes",
            "GovernedVault",
            "GovernedVault",
            "vault share movement updates vote checkpoints through the reconciler"
        );
        seams[3] = RecipePlanLib.seam3(
            "share-transfer-from",
            bytes4(keccak256("transferFrom(address,address,uint256)")),
            "ERC20",
            "ERC20Votes",
            "GovernedVault",
            "GovernedVault",
            "approved vault share movement updates vote checkpoints through the reconciler"
        );
        seams[4] = RecipePlanLib.seam2(
            "managed-assets",
            bytes4(keccak256("totalAssets()")),
            "ERC4626",
            "VaultCore",
            "VaultCore",
            "assets include strategy-managed assets"
        );
        seams[5] = RecipePlanLib.seam2(
            "deposit-limit",
            bytes4(keccak256("maxDeposit(address)")),
            "ERC4626",
            "VaultCore",
            "VaultCore",
            "deposits honor the strategy-manager swap latch"
        );
        seams[6] = RecipePlanLib.seam2(
            "mint-limit",
            bytes4(keccak256("maxMint(address)")),
            "ERC4626",
            "VaultCore",
            "VaultCore",
            "mints honor the strategy-manager swap latch"
        );
        seams[7] = RecipePlanLib.seam3(
            "share-deposit",
            bytes4(keccak256("deposit(uint256,address)")),
            "ERC4626",
            "VaultCore",
            "GovernedVault",
            "GovernedVault",
            "deposits reconcile strategy accounting and share vote checkpoints"
        );
        seams[8] = RecipePlanLib.seam3(
            "share-mint",
            bytes4(keccak256("mint(uint256,address)")),
            "ERC4626",
            "VaultCore",
            "GovernedVault",
            "GovernedVault",
            "mints reconcile strategy accounting and share vote checkpoints"
        );
        seams[9] = RecipePlanLib.seam3(
            "share-withdraw",
            bytes4(keccak256("withdraw(uint256,address,address)")),
            "ERC4626",
            "VaultCore",
            "GovernedVault",
            "GovernedVault",
            "withdrawals reconcile strategy accounting and share vote checkpoints"
        );
        seams[10] = RecipePlanLib.seam3(
            "share-redeem",
            bytes4(keccak256("redeem(uint256,address,address)")),
            "ERC4626",
            "VaultCore",
            "GovernedVault",
            "GovernedVault",
            "redemptions reconcile strategy accounting and share vote checkpoints"
        );
        seams[11] = RecipePlanLib.seam2(
            "balance-delegation",
            bytes4(keccak256("delegate(address)")),
            "Votes",
            "ERC20Votes",
            "ERC20Votes",
            "delegation uses the share holder's current balance"
        );
        seams[12] = RecipePlanLib.seam2(
            "signed-balance-delegation",
            bytes4(keccak256("delegateBySig(address,uint256,uint256,uint8,bytes32,bytes32)")),
            "Votes",
            "ERC20Votes",
            "ERC20Votes",
            "signed delegation uses the share holder's current balance"
        );
        seams[13] = RecipePlanLib.seam3(
            "governance-clock",
            bytes4(keccak256("clock()")),
            "Votes",
            "Governor",
            "GovernedVault",
            "GovernedVault",
            "vote token and governor share the timestamp clock"
        );
        seams[14] = RecipePlanLib.seam3(
            "governance-clock-mode",
            bytes4(keccak256("CLOCK_MODE()")),
            "Votes",
            "Governor",
            "GovernedVault",
            "GovernedVault",
            "vote token and governor advertise the same timestamp clock mode"
        );
        seams[15] = RecipePlanLib.seam2(
            "signed-ballot",
            bytes4(keccak256("castVoteBySig(uint256,uint8,address,bytes)")),
            "Governor",
            "GovernedVault",
            "GovernedVault",
            "ballot signatures use the governed vault's namespaced nonce"
        );
    }

    /// @notice Uses the existing factory to create and initialize the proxy in one transaction.
    /// @dev Custom cuts use no registry entries; the factory binds salt to the caller.
    function deployAtomic(GovernedVaultParams memory p, LatticeFactory factory, bytes32 salt)
        public
        returns (address vault)
    {
        (FacetCut[] memory cuts, address init, bytes memory data) = buildCuts(p);
        vault = factory.deploy(new RecipeEntry[](0), cuts, init, data, salt);
    }

    /// @notice Deploys a self-governed vault diamond (broadcasting entrypoint for `forge script ... --broadcast`).
    function run(GovernedVaultParams memory p) external returns (address vault) {
        vm.startBroadcast();
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = buildCuts(p);
        vault = _assemble(cuts, init, initCalldata);
        vm.stopBroadcast();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          SELECTOR EXCLUSION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice ERC-20 base clashes: the share `name`, the ERC4626 `decimals`, and the checkpoint-seam movers.
    function _erc20Exclusions() private pure returns (bytes4[] memory e) {
        e = new bytes4[](4);
        e[0] = bytes4(keccak256("name()"));
        e[1] = bytes4(keccak256("decimals()"));
        e[2] = bytes4(keccak256("transfer(address,uint256)"));
        e[3] = bytes4(keccak256("transferFrom(address,address,uint256)"));
    }

    /// @notice ERC-4626 clashes: strategy-aware `totalAssets`, deposit-latch-aware `maxDeposit`/`maxMint`, and the
    ///         checkpoint-seam mint/burn flows.
    function _erc4626Exclusions() private pure returns (bytes4[] memory e) {
        e = new bytes4[](7);
        e[0] = bytes4(keccak256("totalAssets()"));
        e[1] = bytes4(keccak256("deposit(uint256,address)"));
        e[2] = bytes4(keccak256("mint(uint256,address)"));
        e[3] = bytes4(keccak256("withdraw(uint256,address,address)"));
        e[4] = bytes4(keccak256("redeem(uint256,address,address)"));
        e[5] = bytes4(keccak256("maxDeposit(address)"));
        e[6] = bytes4(keccak256("maxMint(address)"));
    }

    /// @notice VaultCore clashes: the checkpoint-seam mint/burn flows win over the guarded variants.
    function _vaultExclusions() private pure returns (bytes4[] memory e) {
        e = new bytes4[](4);
        e[0] = bytes4(keccak256("deposit(uint256,address)"));
        e[1] = bytes4(keccak256("mint(uint256,address)"));
        e[2] = bytes4(keccak256("withdraw(uint256,address,address)"));
        e[3] = bytes4(keccak256("redeem(uint256,address,address)"));
    }

    /// @notice Base-{Votes} clashes: the balance-aware {ERC20Votes} delegation and the shared clock win.
    function _votesExclusions() private pure returns (bytes4[] memory e) {
        e = new bytes4[](4);
        e[0] = bytes4(keccak256("delegate(address)"));
        e[1] = bytes4(keccak256("delegateBySig(address,uint256,uint256,uint8,bytes32,bytes32)"));
        e[2] = bytes4(keccak256("clock()"));
        e[3] = bytes4(keccak256("CLOCK_MODE()"));
    }

    /// @notice ERC20Votes clashes: the checkpoint-seam movers win over the checkpoint-updating variants.
    function _erc20VotesExclusions() private pure returns (bytes4[] memory e) {
        e = new bytes4[](2);
        e[0] = bytes4(keccak256("transfer(address,uint256)"));
        e[1] = bytes4(keccak256("transferFrom(address,address,uint256)"));
    }

    /// @notice Governor clashes: the share `name`, the Votes clock, and the namespaced-nonce ballot signature.
    function _governorExclusions() private pure returns (bytes4[] memory e) {
        e = new bytes4[](4);
        e[0] = bytes4(keccak256("name()"));
        e[1] = bytes4(keccak256("clock()"));
        e[2] = bytes4(keccak256("CLOCK_MODE()"));
        e[3] = bytes4(keccak256("castVoteBySig(uint256,uint8,address,bytes)"));
    }
}

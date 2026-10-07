// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployGovernedVault} from "@lattice-script/base/defi/DeployGovernedVault.s.sol";
import {TestnetAsset} from "@lattice-script/base/defi/DeployGovernedVaultENS.s.sol";
import {GovernedVaultTestBase} from "@lattice-test/base/GovernedVaultTestBase.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {GovernedVaultParams} from "@lattice/defi/GovernedVaultInit.sol";
import {Governor} from "@lattice/governance/Governor.sol";
import {DiamondValidationLib} from "@lattice/governance/libraries/DiamondValidationLib.sol";
import {UPGRADE_EXECUTOR_ROLE} from "@lattice/governance/libraries/GovernedDiamondCutLib.sol";
import {TimelockControllerLib} from "@lattice/governance/libraries/TimelockControllerLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IFrozenSelectors} from "@lattice/interfaces/governance/IFrozenSelectors.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/governance/IGovernedDiamondCut.sol";
import {IGovernor} from "@lattice/interfaces/governance/IGovernor.sol";
import {ITimelockController} from "@lattice/interfaces/governance/ITimelockController.sol";
import {IUpgradeRegistry} from "@lattice/interfaces/governance/IUpgradeRegistry.sol";
import {IVotes} from "@lattice/interfaces/governance/IVotes.sol";
import {IEmergencyStop} from "@lattice/interfaces/security/IEmergencyStop.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";
import {InitializableLib, InvalidInitialization} from "@lattice/utils/libraries/InitializableLib.sol";
import {Vm} from "forge-std/Vm.sol";

/// @title VaultUpgradeProbeFacet
/// @notice One-selector probe added by a governance-executed cut — calling through it proves the upgrade.
contract VaultUpgradeProbeFacet {
    function vaultProbePing() external pure returns (uint256) {
        return 42;
    }
}

/// @title GovernedVaultUpgradeTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice THE anti-frozen-diamond proof for the self-governed vault: the recipe cuts {DiamondLoupeFacet}
///         (introspection), {EmergencyStop} (guardian surface) and {GovernedDiamondCut} (upgrade path), and a
///         passed + queued + timelock-executed shareholder proposal — the ONLY reachable authority, since
///         `UPGRADE_EXECUTOR_ROLE` is held by the diamond alone and self-administered — actually executes a
///         diamond cut. Before the fix the recipe shipped 10 cuts with no cut facet and no loupe: a
///         permanently frozen, un-introspectable diamond.
contract GovernedVaultUpgradeTest is GovernedVaultTestBase {
    TestnetAsset internal asset;
    address internal vault;
    Governor internal gov;

    address internal alice = address(0xA11CE);
    address internal stranger = address(0xC3);

    uint256 internal constant DEPOSIT = 1_000 ether;

    function setUp() public {
        vm.warp(1_000_000); // non-zero timestamp clock so checkpoints have room behind them
        asset = new TestnetAsset("Lattice Testnet Asset", "tLAT");
        GovernedVaultParams memory p;
        p.name = "Governed Vault Share";
        p.symbol = "gVLT";
        p.decimalsOffset = 0;
        p.minDelay = 300;
        p.votingDelay = 60;
        p.votingPeriod = 600;
        p.proposalThreshold = 0;
        p.quorumNumerator = 4;
        vault = _deployGovernedVault(address(asset), p);
        gov = Governor(vault);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Alice takes 100% of vote supply (past the 4% quorum) and checkpoints it behind the snapshot.
    function _armAlice() internal {
        asset.mint(alice, DEPOSIT);
        vm.startPrank(alice);
        asset.approve(vault, DEPOSIT);
        IERC4626(vault).deposit(DEPOSIT, alice);
        IVotes(vault).delegate(alice);
        vm.stopPrank();
        vm.warp(block.timestamp + 1);
    }

    /// @dev Full lifecycle against the vault's own governor: propose -> vote -> queue -> delay -> execute.
    function _govern(bytes memory call, string memory description) internal {
        address[] memory targets = new address[](1);
        targets[0] = vault;
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = call;
        bytes32 descriptionHash = keccak256(bytes(description));

        vm.prank(alice);
        uint256 proposalId = gov.propose(targets, values, calldatas, description);

        vm.warp(gov.proposalSnapshot(proposalId) + 1);
        vm.prank(alice);
        gov.castVote(proposalId, 1); // For

        vm.warp(gov.proposalDeadline(proposalId) + 1);
        gov.queue(targets, values, calldatas, descriptionHash);

        vm.expectRevert();
        gov.execute(targets, values, calldatas, descriptionHash);
        vm.warp(gov.proposalEta(proposalId) + 1);
        gov.execute(targets, values, calldatas, descriptionHash);
        assertEq(uint8(gov.state(proposalId)), uint8(IGovernor.ProposalState.Executed));
        vm.expectRevert();
        gov.execute(targets, values, calldatas, descriptionHash);
    }

    function _probeCuts() internal returns (FacetCut[] memory cuts) {
        VaultUpgradeProbeFacet probe = new VaultUpgradeProbeFacet();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = VaultUpgradeProbeFacet.vaultProbePing.selector;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(probe), action: FacetCutAction.Add, functionSelectors: selectors});
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INTROSPECTION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The loupe answers on the assembled vault: 14 base facets, the cut path routed, flags true.
    function test_LoupeAnswersOnVault() public view {
        assertEq(IDiamondLoupe(vault).facetAddresses().length, 14, "14 base facet cuts");
        assertTrue(IDiamondLoupe(vault).facetAddress(0x1f931c1c) != address(0), "diamondCut not routed");
        assertTrue(ERC165Facet(vault).supportsInterface(0x1f931c1c), "IDiamondCut flag missing");
        assertTrue(ERC165Facet(vault).supportsInterface(0x48e2b093), "IDiamondLoupe flag missing");
        assertTrue(
            ERC165Facet(vault).supportsInterface(type(IEmergencyStop).interfaceId),
            "IEmergencyStop flag missing (step 1b __EmergencyStop_init)"
        );
    }

    /// @notice UPGRADE_EXECUTOR_ROLE is held by the diamond ONLY — the no-external-admin invariant.
    function test_UpgradeExecutorRoleHeldByDiamondOnly() public view {
        assertTrue(IAccessControl(vault).hasRole(UPGRADE_EXECUTOR_ROLE, vault), "diamond holds the executor role");
        assertFalse(IAccessControl(vault).hasRole(UPGRADE_EXECUTOR_ROLE, address(this)), "deployer must not");
        assertFalse(IAccessControl(vault).hasRole(UPGRADE_EXECUTOR_ROLE, stranger), "stranger must not");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                          GOVERNED UPGRADE PATH
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice THE headline: a shareholder proposal executes `diamondCut` on the vault, adding a live facet.
    function test_GovernanceProposalExecutesDiamondCut() public {
        _armAlice();
        uint256 shares = IERC20(vault).balanceOf(alice);
        uint256 assets = IERC4626(vault).totalAssets();
        uint256 snapshot = block.timestamp - 1;
        uint256 votes = IVotes(vault).getPastVotes(alice, snapshot);
        assertEq(gov.token(), vault);
        assertEq(gov.timelock(), vault);
        uint256 supply = IERC20(vault).totalSupply();
        uint256 currentVotes = IVotes(vault).getVotes(alice);
        address cutFacet = IDiamondLoupe(vault).facetAddress(0x1f931c1c);
        FacetCut[] memory cuts = _probeCuts();
        _govern(
            abi.encodeCall(IGovernedDiamondCut.diamondCut, (cuts, address(0), bytes(""))),
            "upgrade: add VaultUpgradeProbeFacet"
        );

        assertEq(VaultUpgradeProbeFacet(vault).vaultProbePing(), 42, "probe facet not routed after the cut");
        assertEq(
            IDiamondLoupe(vault).facetAddress(VaultUpgradeProbeFacet.vaultProbePing.selector),
            cuts[0].facetAddress,
            "loupe routes the probe selector to the cut facet"
        );
        assertEq(IDiamondLoupe(vault).facetAddress(0x1f931c1c), cutFacet, "the cut must not move diamondCut");
        assertEq(IUpgradeRegistry(vault).cutCount(), 1, "cut recorded in the upgrade registry");
        // The timelock relays the queued call as an external self-call, so the recorded executor is the vault.
        assertEq(IUpgradeRegistry(vault).getCutRecord(1).executor, vault, "executor is the diamond (timelock)");
        assertEq(IDiamondLoupe(vault).facetAddresses().length, 15, "probe facet joined the loupe");
        assertEq(IERC20(vault).balanceOf(alice), shares);
        assertEq(IERC4626(vault).totalAssets(), assets);
        assertEq(IVotes(vault).getPastVotes(alice, snapshot), votes);
        assertEq(IERC20(vault).totalSupply(), supply, "share supply unchanged");
        assertEq(IVotes(vault).getVotes(alice), currentVotes, "current voting power unchanged");
        assertEq(IVotes(vault).delegates(alice), alice, "delegation unchanged");
    }

    /// @notice The declared composition rejects an accidental duplicated storage owner.
    function test_DuplicateNamespaceRejected() public {
        CollidingGovernedVaultRecipe recipe = new CollidingGovernedVaultRecipe();
        LatticeFactory factory = new LatticeFactory(new LatticeRegistry(address(this)), address(0), address(0));
        GovernedVaultParams memory p =
            GovernedVaultParams(address(asset), "Collision test", "TEST", 0, 300, 60, 600, 0, 4);
        string[] memory ids = recipe.storageNamespaces();
        vm.expectRevert(
            abi.encodeWithSelector(
                DiamondValidationLib.NamespaceCollision.selector,
                DiamondValidationLib.erc7201Slot(ids[0]),
                ids[0],
                ids[0]
            )
        );
        recipe.deployAtomic(p, factory, bytes32(0));
        assertEq(factory.predict(address(recipe), bytes32(0)).code.length, 0);
    }

    /// @notice In the single initialization transaction, the module initializers run in dependency order: access
    ///         control, then upgrade control, then the timelock. diamond-lib then records the cut (`DiamondCut` is
    ///         emitted after the init delegatecall returns), and the window closes last, so the vault emits nothing
    ///         after `Initialized(1)`. The Governor step emits no event; its configuration is read back afterwards.
    function test_InitializersRunInDependencyOrder() public {
        GovernedVaultParams memory p;
        p.name = "Order test";
        p.symbol = "ORD";
        p.minDelay = 300;
        p.votingDelay = 60;
        p.votingPeriod = 600;
        p.quorumNumerator = 4;
        vm.recordLogs();
        address v = _deployGovernedVault(address(asset), p);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 roleGranted = IAccessControl.RoleGranted.selector;
        uint256 cut = _firstLog(logs, v, keccak256("DiamondCut((address,uint8,bytes4[])[],address,bytes)"), 0);
        uint256 admin = _firstLog(logs, v, roleGranted, DEFAULT_ADMIN_ROLE);
        uint256 executor = _firstLog(logs, v, roleGranted, UPGRADE_EXECUTOR_ROLE);
        uint256 timelock = _firstLog(logs, v, ITimelockController.MinDelayChange.selector, 0);
        uint256 proposer = _firstLog(logs, v, roleGranted, TimelockControllerLib.PROPOSER_ROLE);
        uint256 closed = _firstLog(logs, v, keccak256("Initialized(uint64)"), 0);

        assertLt(admin, executor, "step 1 (access control) before step 1b (upgrade control)");
        assertLt(executor, timelock, "step 1b before step 3 (timelock)");
        assertLt(timelock, proposer, "timelock delay set before its proposer is granted");
        assertLt(proposer, cut, "the cut is recorded after the initializer returns");
        assertLt(cut, closed, "the window closes last");
        for (uint256 i = closed + 1; i < logs.length; ++i) {
            assertTrue(logs[i].emitter != v, "the vault emits nothing after the window closes");
        }

        assertEq(Governor(v).token(), v, "step 4: votes come from the vault's own shares");
        assertEq(Governor(v).timelock(), v, "step 4: proposals route through the vault's own timelock");
        assertEq(Governor(v).votingDelay(), 60);
        assertEq(Governor(v).votingPeriod(), 600);
        assertEq(Governor(v).quorumNumerator(), 4);
        assertEq(ITimelockController(v).getMinDelay(), 300);
    }

    /// @dev Index of the first log `emitter` produced with topic0 `sig` (and topic1 `topic1`, unless it is zero).
    function _firstLog(Vm.Log[] memory logs, address emitter, bytes32 sig, bytes32 topic1)
        internal
        pure
        returns (uint256)
    {
        for (uint256 i; i < logs.length; ++i) {
            Vm.Log memory l = logs[i];
            if (l.emitter != emitter || l.topics.length == 0 || l.topics[0] != sig) continue;
            if (topic1 != 0 && (l.topics.length < 2 || l.topics[1] != topic1)) continue;
            return i;
        }
        revert("log not found");
    }

    /// @notice The three-stage initialization window finalized and cannot be reopened.
    function test_InitializationFinalizedAndReplayRejected() public {
        bytes32 state = vm.load(vault, InitializableLib.initializableSlot());
        // InitializableLib stores (version << 1) | initializing in its pinned slot.
        assertEq(uint256(state), 2);
        vm.expectRevert(InvalidInitialization.selector);
        Lattice(payable(vault)).initialize(new FacetCut[](0), address(0), "");
    }

    /// @notice No caller outside the timelock path can cut — not even the deployer.
    function test_StrangerCannotDiamondCut() public {
        FacetCut[] memory cuts = _probeCuts();
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, UPGRADE_EXECUTOR_ROLE
            )
        );
        IGovernedDiamondCut(vault).diamondCut(cuts, address(0), "");
    }

    /// @notice Governance can freeze the load-bearing selectors (loupe + cut + emergency path) — the
    ///         recommended first proposal after deployment — and the freeze sticks.
    function test_GovernanceCanFreezeSelectors() public {
        _armAlice();
        bytes4[] memory frozen = new bytes4[](6);
        frozen[0] = IDiamondLoupe.facets.selector;
        frozen[1] = IDiamondLoupe.facetFunctionSelectors.selector;
        frozen[2] = IDiamondLoupe.facetAddresses.selector;
        frozen[3] = IDiamondLoupe.facetAddress.selector;
        frozen[4] = 0x1f931c1c; // diamondCut
        frozen[5] = 0xc83542a6; // emergencyRemoveCut
        _govern(abi.encodeCall(IFrozenSelectors.freezeSelectors, (frozen)), "freeze: loupe + cut + emergency");

        for (uint256 i; i < frozen.length; ++i) {
            assertTrue(IFrozenSelectors(vault).isSelectorFrozen(frozen[i]), "selector not frozen");
        }
    }
}

/// @notice Exercises the production deployment path with an invalid declared composition.
contract CollidingGovernedVaultRecipe is DeployGovernedVault {
    function storageNamespaces() public pure override returns (string[] memory ids) {
        ids = super.storageNamespaces();
        ids[1] = ids[0];
    }
}

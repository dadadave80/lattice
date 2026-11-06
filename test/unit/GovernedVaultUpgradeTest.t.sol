// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Selectors} from "@diamond-test/helpers/Selectors.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployGovernedVault} from "@lattice-script/base/defi/DeployGovernedVault.s.sol";
import {TestnetAsset} from "@lattice-script/base/defi/DeployGovernedVaultENS.s.sol";
import {GovernedVaultTestBase} from "@lattice-test/base/GovernedVaultTestBase.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {AccessControlInit} from "@lattice/access/AccessControlInit.sol";
import {DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {GovernedVaultParams} from "@lattice/defi/GovernedVaultInit.sol";
import {Governor} from "@lattice/governance/Governor.sol";
import {DiamondValidationLib} from "@lattice/governance/libraries/DiamondValidationLib.sol";
import {UPGRADE_EXECUTOR_ROLE} from "@lattice/governance/libraries/GovernedDiamondCutLib.sol";
import {TimelockControllerLib} from "@lattice/governance/libraries/TimelockControllerLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IEmergencyCut} from "@lattice/interfaces/governance/IEmergencyCut.sol";
import {IFrozenSelectors} from "@lattice/interfaces/governance/IFrozenSelectors.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/governance/IGovernedDiamondCut.sol";
import {IGovernor} from "@lattice/interfaces/governance/IGovernor.sol";
import {ITimelockController} from "@lattice/interfaces/governance/ITimelockController.sol";
import {IUpgradeRegistry} from "@lattice/interfaces/governance/IUpgradeRegistry.sol";
import {IVotes} from "@lattice/interfaces/governance/IVotes.sol";
import {IEmergencyStop} from "@lattice/interfaces/security/IEmergencyStop.sol";
import {IRateLimiter} from "@lattice/interfaces/security/IRateLimiter.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";
import {RateLimiter} from "@lattice/security/RateLimiter.sol";
import {RateLimiterInit} from "@lattice/security/RateLimiterInit.sol";
import {RATE_LIMITER_STORAGE_SLOT} from "@lattice/security/libraries/RateLimiterLib.sol";
import {ReinitMultiInit} from "@lattice/utils/ReinitMultiInit.sol";
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
    bytes32 internal constant RATE_KEY = keccak256("governed-upgrade-example");
    bytes32 internal constant INIT_SLOT = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffbf601132;

    struct QueuedProposal {
        address[] targets;
        uint256[] values;
        bytes[] calldatas;
        bytes32 descriptionHash;
        uint256 id;
    }

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

    function _queueProposal(bytes memory call, string memory description) internal returns (QueuedProposal memory p) {
        p.targets = new address[](1);
        p.targets[0] = vault;
        p.values = new uint256[](1);
        p.calldatas = new bytes[](1);
        p.calldatas[0] = call;
        p.descriptionHash = keccak256(bytes(description));

        vm.prank(alice);
        p.id = gov.propose(p.targets, p.values, p.calldatas, description);

        vm.warp(gov.proposalSnapshot(p.id) + 1);
        vm.prank(alice);
        gov.castVote(p.id, 1); // For

        vm.warp(gov.proposalDeadline(p.id) + 1);
        gov.queue(p.targets, p.values, p.calldatas, p.descriptionHash);
    }

    /// @dev Full lifecycle against the vault's own governor: propose -> vote -> queue -> delay -> execute.
    function _govern(bytes memory call, string memory description) internal {
        QueuedProposal memory p = _queueProposal(call, description);

        vm.expectRevert();
        gov.execute(p.targets, p.values, p.calldatas, p.descriptionHash);
        vm.warp(gov.proposalEta(p.id) + 1);
        gov.execute(p.targets, p.values, p.calldatas, p.descriptionHash);
        assertEq(uint8(gov.state(p.id)), uint8(IGovernor.ProposalState.Executed));
        vm.expectRevert();
        gov.execute(p.targets, p.values, p.calldatas, p.descriptionHash);
    }

    function _governRejected(bytes memory call, string memory description, bytes memory reason) internal {
        QueuedProposal memory p = _queueProposal(call, description);
        vm.warp(gov.proposalEta(p.id) + 1);
        vm.expectRevert(reason);
        gov.execute(p.targets, p.values, p.calldatas, p.descriptionHash);
        assertEq(uint8(gov.state(p.id)), uint8(IGovernor.ProposalState.Queued), "failed execution stays queued");
        bytes32 operation =
            ITimelockController(vault).hashOperationBatch(p.targets, p.values, p.calldatas, bytes32(0), bytes32(p.id));
        assertTrue(ITimelockController(vault).isOperationReady(operation), "timelock execution rolled back");
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

    function _rateLimiterCut(address limiter) internal view returns (FacetCut[] memory cuts) {
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut(limiter, FacetCutAction.Add, Selectors.decode(RateLimiter(limiter).exportSelectors()));
    }

    function _rateLimiterBatch(uint64 version, address limiter, address moduleInit, bool fail)
        internal
        returns (bytes memory)
    {
        address[] memory inits = new address[](fail ? 3 : 2);
        bytes[] memory data = new bytes[](inits.length);
        inits[0] = moduleInit;
        data[0] = abi.encodeCall(RateLimiterInit.init, (vault));
        inits[1] = limiter;
        data[1] = abi.encodeCall(IRateLimiter.configure, (RATE_KEY, 100, 1));
        if (fail) {
            inits[2] = address(new AccessControlInit());
            data[2] = abi.encodeCall(AccessControlInit.init, (stranger));
        }
        return abi.encodeCall(ReinitMultiInit.reinitMulti, (version, inits, data));
    }

    function _assertReinitVersion(uint64 expected) internal view {
        assertEq(InitializableLib.initializableSlot(), INIT_SLOT, "stable tooling slot");
        assertEq(uint256(vm.load(vault, INIT_SLOT)), uint256(expected) << 1, "version and closed window");
    }

    function _vaultStateHash() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                IERC20(vault).totalSupply(),
                IERC20(vault).balanceOf(alice),
                IERC20(vault).allowance(alice, stranger),
                IERC4626(vault).totalAssets(),
                IVotes(vault).getVotes(alice),
                IVotes(vault).delegates(alice),
                gov.token(),
                gov.timelock()
            )
        );
    }

    /// @notice A real proposal adds a module, opens version2, then configures its new persistent state.
    function test_GovernanceProposalAddsAndInitializesModuleAtVersion2() public {
        _armAlice();
        vm.prank(alice);
        IERC20(vault).approve(stranger, 123);
        bytes32 previous = _vaultStateHash();
        RateLimiter limiter = new RateLimiter();
        RateLimiterInit moduleInit = new RateLimiterInit();
        ReinitMultiInit batch = new ReinitMultiInit();
        _assertReinitVersion(1);

        _govern(
            abi.encodeCall(
                IGovernedDiamondCut.diamondCut,
                (
                    _rateLimiterCut(address(limiter)),
                    address(batch),
                    _rateLimiterBatch(2, address(limiter), address(moduleInit), false)
                )
            ),
            "upgrade: add and initialize RateLimiter"
        );

        _assertReinitVersion(2);
        assertEq(IDiamondLoupe(vault).facetAddress(IRateLimiter.configure.selector), address(limiter));
        assertEq(
            abi.encode(IDiamondLoupe(vault).facetFunctionSelectors(address(limiter))),
            abi.encode(Selectors.decode(limiter.exportSelectors()))
        );
        assertTrue(ERC165Facet(vault).supportsInterface(type(IRateLimiter).interfaceId));
        (uint256 capacity, uint256 refillRate) = IRateLimiter(vault).getConfig(RATE_KEY);
        assertEq(capacity, 100);
        assertEq(refillRate, 1);
        assertEq(IRateLimiter(vault).getAvailable(RATE_KEY), 100);
        assertEq(IDiamondLoupe(vault).facetAddress(ReinitMultiInit.reinitMulti.selector), address(0));
        assertEq(IUpgradeRegistry(vault).cutCount(), 1);
        assertEq(IUpgradeRegistry(vault).getCutRecord(1).executor, vault);
        assertTrue(IAccessControl(vault).hasRole(DEFAULT_ADMIN_ROLE, vault));
        assertFalse(IAccessControl(vault).hasRole(DEFAULT_ADMIN_ROLE, alice));
        assertEq(_vaultStateHash(), previous, "original vault state preserved");
    }

    /// @notice Distinct passed proposals reach the reinitializer guard, not the Governor proposal-replay guard.
    function test_GovernedReinitRejectsSameAndLowerVersions() public {
        _armAlice();
        RateLimiter limiter = new RateLimiter();
        RateLimiterInit moduleInit = new RateLimiterInit();
        ReinitMultiInit batch = new ReinitMultiInit();
        _govern(
            abi.encodeCall(
                IGovernedDiamondCut.diamondCut,
                (
                    _rateLimiterCut(address(limiter)),
                    address(batch),
                    _rateLimiterBatch(2, address(limiter), address(moduleInit), false)
                )
            ),
            "upgrade: version2"
        );
        for (uint64 version = 2; version > 0; --version) {
            _governRejected(
                abi.encodeCall(
                    IGovernedDiamondCut.diamondCut,
                    (
                        new FacetCut[](0),
                        address(batch),
                        _rateLimiterBatch(version, address(limiter), address(moduleInit), false)
                    )
                ),
                version == 2 ? "upgrade: same version rejected" : "upgrade: lower version rejected",
                abi.encodeWithSelector(InvalidInitialization.selector)
            );
        }
        _assertReinitVersion(2);
        assertEq(IUpgradeRegistry(vault).cutCount(), 1, "rejected cuts are not recorded");
        (uint256 capacity, uint256 refillRate) = IRateLimiter(vault).getConfig(RATE_KEY);
        assertEq(capacity, 100);
        assertEq(refillRate, 1);
    }

    /// @notice A later failed init rolls back the earlier config, cut, version and governance execution writes.
    function test_GovernedReinitLateFailureRollsBackAndVersionCanBeRetried() public {
        _armAlice();
        bytes32 previous = _vaultStateHash();
        RateLimiter limiter = new RateLimiter();
        RateLimiterInit moduleInit = new RateLimiterInit();
        ReinitMultiInit batch = new ReinitMultiInit();
        FacetCut[] memory cuts = _rateLimiterCut(address(limiter));
        bytes32 bucket = keccak256(abi.encode(RATE_KEY, RATE_LIMITER_STORAGE_SLOT));
        _governRejected(
            abi.encodeCall(
                IGovernedDiamondCut.diamondCut,
                (cuts, address(batch), _rateLimiterBatch(2, address(limiter), address(moduleInit), true))
            ),
            "upgrade: conflicting final bootstrap rejected",
            abi.encodeWithSelector(IAccessControl.AccessControlConflictingInitialization.selector, vault, stranger)
        );
        _assertReinitVersion(1);
        assertEq(vm.load(vault, bucket), bytes32(0), "earlier capacity write rolled back");
        assertEq(IDiamondLoupe(vault).facetAddress(IRateLimiter.configure.selector), address(0));
        assertFalse(ERC165Facet(vault).supportsInterface(type(IRateLimiter).interfaceId));
        assertEq(IUpgradeRegistry(vault).cutCount(), 0);
        assertEq(_vaultStateHash(), previous, "old vault state preserved after failure");

        _govern(
            abi.encodeCall(
                IGovernedDiamondCut.diamondCut,
                (cuts, address(batch), _rateLimiterBatch(2, address(limiter), address(moduleInit), false))
            ),
            "upgrade: retry version2 with valid final step"
        );
        _assertReinitVersion(2);
        assertEq(uint256(vm.load(vault, bucket)), 100, "successful retry persists capacity");
        assertEq(IUpgradeRegistry(vault).cutCount(), 1);
        assertEq(_vaultStateHash(), previous, "old vault state preserved after retry");
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

    //*//////////////////////////////////////////////////////////////////////////
    //                         EMERGENCY GUARDIAN BOUNDS
    //////////////////////////////////////////////////////////////////////////*//

    address internal guardian = address(0x6044D1A11);

    /// @dev Appoints `guardian` the way governance would: the vault holds DEFAULT_ADMIN_ROLE.
    function _appointGuardian() internal {
        vm.prank(vault);
        IEmergencyStop(vault).addGuardian(guardian);
    }

    function _removeCut(bytes4 sel) internal pure returns (FacetCut[] memory cuts) {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = sel;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(0), action: FacetCutAction.Remove, functionSelectors: sels});
    }

    /// @notice #218 regression: with nothing frozen, a guardian still cannot remove `diamondCut`.
    function test_GuardianCannotRemoveDiamondCut() public {
        _appointGuardian();
        assertEq(IFrozenSelectors(vault).frozenSelectors().length, 0, "nothing frozen at init");
        vm.prank(guardian);
        vm.expectRevert(
            abi.encodeWithSelector(IEmergencyCut.EmergencyCutEntrypointProtected.selector, bytes4(0x1f931c1c))
        );
        IEmergencyCut(vault).emergencyRemoveCut(_removeCut(0x1f931c1c));
        assertTrue(IDiamondLoupe(vault).facetAddress(0x1f931c1c) != address(0), "diamondCut must stay bound");
    }

    /// @notice Documents the liveness trust: before the recommended freeze, a guardian CAN remove an
    ///         unfrozen Governor execution selector (the NatSpec on {GovernedDiamondCutLib} and
    ///         {DeployGovernedVault.recommendedFreezeSelectors} states this).
    function test_GuardianTrustedForLivenessUntilFrozen() public {
        _appointGuardian();
        vm.prank(guardian);
        IEmergencyCut(vault).emergencyRemoveCut(_removeCut(IGovernor.execute.selector));
        assertEq(IDiamondLoupe(vault).facetAddress(IGovernor.execute.selector), address(0), "unfrozen: removable");
    }

    /// @notice #218 regression: after governance freezes the recommended list, a guardian cannot remove
    ///         any Governor or Timelock execution selector, and governance can still upgrade.
    function test_RecommendedFreezeBoundsGuardian() public {
        _armAlice();
        bytes4[] memory frozen = deployer.recommendedFreezeSelectors();
        _govern(abi.encodeCall(IFrozenSelectors.freezeSelectors, (frozen)), "freeze: recommended list");
        _appointGuardian();

        for (uint256 i; i < frozen.length; ++i) {
            assertTrue(IDiamondLoupe(vault).facetAddress(frozen[i]) != address(0), "recommended selector unbound");
            bytes memory reason = frozen[i] == bytes4(0x1f931c1c)
                ? abi.encodeWithSelector(IEmergencyCut.EmergencyCutEntrypointProtected.selector, frozen[i])
                : abi.encodeWithSelector(IFrozenSelectors.FrozenSelectorProtected.selector, frozen[i]);
            vm.prank(guardian);
            vm.expectRevert(reason);
            IEmergencyCut(vault).emergencyRemoveCut(_removeCut(frozen[i]));
        }

        FacetCut[] memory cuts = _probeCuts();
        _govern(abi.encodeCall(IGovernedDiamondCut.diamondCut, (cuts, address(0), "")), "upgrade after freeze");
        assertEq(VaultUpgradeProbeFacet(vault).vaultProbePing(), 42, "governance must still upgrade");
    }

    /// @notice #218 regression (recipe-built vault): after the recommended freeze, a guardian that trips
    ///         the stop cannot then remove `emergencyResume` (or the guardian-revocation selectors), so a
    ///         governance proposal resumes the vault and the next one upgrades it.
    function test_GuardianStopCannotStrandUpgradePath() public {
        _armAlice();
        _govern(
            abi.encodeCall(IFrozenSelectors.freezeSelectors, (deployer.recommendedFreezeSelectors())),
            "freeze: recommended list"
        );
        _appointGuardian();
        vm.prank(guardian);
        IEmergencyStop(vault).emergencyStop("incident");

        bytes4[3] memory recovery = [
            IEmergencyStop.emergencyResume.selector,
            IEmergencyStop.removeGuardian.selector,
            IAccessControl.revokeRole.selector
        ];
        for (uint256 i; i < recovery.length; ++i) {
            vm.prank(guardian);
            vm.expectRevert(abi.encodeWithSelector(IEmergencyCut.EmergencyCutEntrypointProtected.selector, recovery[i]));
            IEmergencyCut(vault).emergencyRemoveCut(_removeCut(recovery[i]));
            assertTrue(IDiamondLoupe(vault).facetAddress(recovery[i]) != address(0), "recovery selector unbound");
        }

        _govern(abi.encodeCall(IEmergencyStop.emergencyResume, ()), "resume");
        assertFalse(IEmergencyStop(vault).isStopped(), "governance must resume");
        FacetCut[] memory cuts = _probeCuts();
        _govern(abi.encodeCall(IGovernedDiamondCut.diamondCut, (cuts, address(0), "")), "upgrade after resume");
        assertEq(VaultUpgradeProbeFacet(vault).vaultProbePing(), 42, "governance must still upgrade");
    }
}

/// @notice Exercises the production deployment path with an invalid declared composition.
contract CollidingGovernedVaultRecipe is DeployGovernedVault {
    function storageNamespaces() public pure override returns (string[] memory ids) {
        ids = super.storageNamespaces();
        ids[1] = ids[0];
    }
}

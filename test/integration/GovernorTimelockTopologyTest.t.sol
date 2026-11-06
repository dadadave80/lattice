// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondCutFacet} from "@diamond/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {MultiInit} from "@diamond/initializers/MultiInit.sol";
import {DiamondLib, FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {DeployGovernedDiamondCut} from "@lattice-script/base/governance/DeployGovernedDiamondCut.s.sol";
import {GovToken} from "@lattice-test/integration/GovernedUpgradeTest.t.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {LatticeRegistry} from "@lattice/LatticeRegistry.sol";
import {GovernedDiamondCut} from "@lattice/governance/GovernedDiamondCut.sol";
import {GovernedDiamondCutInit} from "@lattice/governance/GovernedDiamondCutInit.sol";
import {Governor} from "@lattice/governance/Governor.sol";
import {GovernorInit} from "@lattice/governance/GovernorInit.sol";
import {TimelockController} from "@lattice/governance/TimelockController.sol";
import {TimelockControllerInit} from "@lattice/governance/TimelockControllerInit.sol";
import {UPGRADE_EXECUTOR_ROLE} from "@lattice/governance/libraries/GovernedDiamondCutLib.sol";
import {GOVERNOR_STORAGE_SLOT} from "@lattice/governance/libraries/GovernorLib.sol";
import {RecipeEntry} from "@lattice/interfaces/ILatticeFactory.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/governance/IGovernedDiamondCut.sol";
import {IGovernor} from "@lattice/interfaces/governance/IGovernor.sol";
import {Initializable} from "@lattice/utils/Initializable.sol";
import {NotInitializing} from "@lattice/utils/libraries/InitializableLib.sol";
import {Test} from "forge-std/Test.sol";

interface IAcknowledgedGovernorInit {
    function registerGovernedCutTopology() external;
    function initWithExternalTimelockOptOut(
        string memory name_,
        address token_,
        address timelock_,
        uint48 votingDelay_,
        uint32 votingPeriod_,
        uint256 proposalThreshold_,
        uint256 quorumNumerator_,
        bool acknowledgeIncompatibleCutExecutor_
    ) external;
}

/// @notice Test equivalent of the separately released #207 batch's native guard/delegatecall boundary.
contract GovernorTopologyReinitializer is Initializable {
    function run(uint64 version, address target, bytes calldata data) external reinitializer(version) {
        DiamondLib.initializeDiamondCut(target, data);
    }
}

contract GovernorTopologyProbe {
    function topologyProbe() external pure returns (uint256) {
        return 208;
    }
}

/// @notice Real recipe facets and guarded initialization, deployed atomically by LatticeFactory.
contract GovernorTimelockTopologyTest is Test, BaseDeploy {
    bytes4 constant INCOMPATIBLE = bytes4(keccak256("GovernorIncompatibleTimelock(address,address)"));
    bytes4 constant NO_CUT_ROUTE = bytes4(keccak256("GovernorMissingGovernedCutRoute()"));
    bytes4 constant UNACKNOWLEDGED = bytes4(keccak256("GovernorTimelockOptOutNotAcknowledged()"));
    address constant ALICE = address(0xA11CE);
    address constant EXTERNAL = address(0xE208);
    GovToken token;
    LatticeFactory factory;
    uint256 nonce;

    struct Setup {
        address predicted;
        address timelock;
        bool governorFirst;
        bool optOut;
        bool acknowledge;
    }

    function setUp() public {
        vm.warp(1_000_000);
        token = new GovToken();
        token.initialize("Vote", "VOTE", address(this));
        token.mint(ALICE, 100e18);
        vm.prank(ALICE);
        token.delegate(ALICE);
        vm.warp(block.timestamp + 1);
        factory = new LatticeFactory(new LatticeRegistry(address(this)), address(0), address(0));
    }

    function deployTopology(uint8 topology, bool governorFirst, bool optOut, bool acknowledge)
        external
        returns (address diamond)
    {
        bytes32 salt = bytes32(++nonce);
        address predicted = factory.predict(address(this), salt);
        address timelock = topology == 1 ? predicted : topology == 2 ? EXTERNAL : address(0);
        (FacetCut[] memory cuts, address[] memory inits, bytes[] memory data) =
            _buildTopology(Setup(predicted, timelock, governorFirst, optOut, acknowledge));
        diamond = factory.deploy(
            new RecipeEntry[](0),
            cuts,
            address(new MultiInit()),
            abi.encodeCall(MultiInit.multiInit, (inits, data)),
            salt
        );
        assertEq(diamond, predicted);
    }

    function _buildTopology(Setup memory config)
        private
        returns (FacetCut[] memory cuts, address[] memory inits, bytes[] memory data)
    {
        (FacetCut[] memory base, address cutInit, bytes memory cutData) =
            new DeployGovernedDiamondCut().buildCuts(address(this));
        cuts = new FacetCut[](base.length + 2);
        for (uint256 i; i < base.length; ++i) {
            cuts[i] = base[i];
        }
        cuts[base.length] = _cut(address(new Governor()));
        cuts[base.length + 1] = _cut(address(new TimelockController()));
        inits = new address[](3);
        data = new bytes[](3);
        uint256 governorIndex = config.governorFirst ? 0 : 1;
        uint256 cutIndex = config.governorFirst ? 1 : 0;
        inits[cutIndex] = cutInit;
        data[cutIndex] = cutData;
        inits[governorIndex] = address(new GovernorInit());
        data[governorIndex] = _governorData(config.timelock, config.optOut, config.acknowledge);
        inits[2] = address(new TimelockControllerInit());
        address[] memory proposers = new address[](1);
        proposers[0] = config.predicted;
        address[] memory executors = new address[](1);
        data[2] = abi.encodeCall(TimelockControllerInit.init, (60, proposers, executors, address(this)));
    }

    function _governorData(address timelock, bool optOut, bool acknowledge) private view returns (bytes memory) {
        return optOut
            ? abi.encodeCall(
                IAcknowledgedGovernorInit.initWithExternalTimelockOptOut,
                ("Governed", address(token), timelock, 1, 10, 0, 4, acknowledge)
            )
            : abi.encodeCall(GovernorInit.init, ("Governed", address(token), timelock, 1, 10, 0, 4));
    }

    function test_ExternalTimelockRejectedWhenGovernorInitializesAfterGovernedCut() public {
        vm.expectPartialRevert(INCOMPATIBLE);
        this.deployTopology(2, false, false, false);
    }

    function test_ExternalTimelockRejectedWhenGovernorInitializesBeforeGovernedCut() public {
        vm.expectPartialRevert(INCOMPATIBLE);
        this.deployTopology(2, true, false, false);
    }

    function test_SelfTimelockExecutesPassedCut() public {
        _executeCut(1, false);
    }

    function test_DirectGovernorExecutesPassedCut() public {
        _executeCut(0, false);
    }

    function test_SupportedTopologiesAlsoExecuteCutsWhenGovernorInitializesFirst() public {
        _executeCut(0, true);
        _executeCut(1, true);
    }

    function _executeCut(uint8 topology, bool governorFirst) private {
        address diamond = this.deployTopology(topology, governorFirst, false, false);
        GovernorTopologyProbe probe = new GovernorTopologyProbe();
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = GovernorTopologyProbe.topologyProbe.selector;
        FacetCut[] memory cut = new FacetCut[](1);
        cut[0] = FacetCut(address(probe), FacetCutAction.Add, selectors);
        _passAndExecute(diamond, abi.encodeCall(IGovernedDiamondCut.diamondCut, (cut, address(0), hex"")));
        assertEq(DiamondLoupeFacet(diamond).facetAddress(selectors[0]), address(probe));
        assertEq(GovernorTopologyProbe(diamond).topologyProbe(), 208);
    }

    function test_UpdateTimelockRejectsExternalExecutorThroughPassedProposal() public {
        address diamond = this.deployTopology(0, false, false, false);
        (address[] memory targets, uint256[] memory values, bytes[] memory calls, bytes32 hash) =
            _pass(diamond, abi.encodeCall(IGovernor.updateTimelock, (EXTERNAL)));
        vm.expectPartialRevert(INCOMPATIBLE);
        Governor(payable(diamond)).execute(targets, values, calls, hash);
        assertEq(Governor(payable(diamond)).timelock(), address(0));
    }

    function test_ExplicitOptOutDoesNotGrantExternalExecutorAuthority() public {
        address diamond = this.deployTopology(2, false, true, true);
        assertEq(Governor(payable(diamond)).timelock(), EXTERNAL);
        assertTrue(IAccessControl(diamond).hasRole(UPGRADE_EXECUTOR_ROLE, diamond));
        assertFalse(IAccessControl(diamond).hasRole(UPGRADE_EXECUTOR_ROLE, EXTERNAL));
    }

    function test_OptOutRequiresAcknowledgement() public {
        vm.expectRevert(UNACKNOWLEDGED);
        this.deployTopology(2, false, true, false);
    }

    function test_TopologyConfigurationRequiresAnInitializationWindow() public {
        IAcknowledgedGovernorInit init = IAcknowledgedGovernorInit(address(new GovernorInit()));
        vm.expectRevert(NotInitializing.selector);
        init.registerGovernedCutTopology();
        vm.expectRevert(NotInitializing.selector);
        init.initWithExternalTimelockOptOut("Gov", address(token), EXTERNAL, 1, 10, 0, 4, false);
    }

    function test_GovernedCutInitializerRejectsMissingCutRoute() public {
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = _cut(address(new DiamondLoupeFacet()));
        address init = address(new GovernedDiamondCutInit());
        vm.expectRevert(NO_CUT_ROUTE);
        factory.deploy(
            new RecipeEntry[](0),
            cuts,
            init,
            abi.encodeCall(GovernedDiamondCutInit.init, (address(this))),
            bytes32(uint256(100))
        );
    }

    function test_ExplicitOptOutWorksWhenGovernorInitializesFirst() public {
        address diamond = this.deployTopology(2, true, true, true);
        assertEq(Governor(payable(diamond)).timelock(), EXTERNAL);
        assertFalse(IAccessControl(diamond).hasRole(UPGRADE_EXECUTOR_ROLE, EXTERNAL));
    }

    function test_AcknowledgedOptOutAppliesToLaterGovernanceSetterWithoutGrantingRoles() public {
        address diamond = this.deployTopology(0, false, true, true);
        _passAndExecute(diamond, abi.encodeCall(IGovernor.updateTimelock, (EXTERNAL)));
        assertEq(Governor(payable(diamond)).timelock(), EXTERNAL);
        assertFalse(IAccessControl(diamond).hasRole(UPGRADE_EXECUTOR_ROLE, EXTERNAL));
    }

    function test_StalePolicyDoesNotClassifyReplacementCutFlavor() public {
        address diamond = this.deployTopology(0, false, false, false);
        _replaceCut(diamond, address(new DiamondCutFacet()), false);
        _passAndExecute(diamond, abi.encodeCall(IGovernor.updateTimelock, (EXTERNAL)));
        assertEq(Governor(payable(diamond)).timelock(), EXTERNAL);
    }

    function test_UpgradedGovernedCutPolicyIsRegisteredForItsNewAddress() public {
        address diamond = this.deployTopology(0, false, false, false);
        address next = address(new GovernedDiamondCut());
        _replaceCut(diamond, next, true);
        (address[] memory targets, uint256[] memory values, bytes[] memory calls, bytes32 hash) =
            _pass(diamond, abi.encodeCall(IGovernor.updateTimelock, (EXTERNAL)));
        vm.expectRevert(abi.encodeWithSelector(INCOMPATIBLE, EXTERNAL, next));
        Governor(payable(diamond)).execute(targets, values, calls, hash);
    }

    function test_LegacyPolicyBackfillPreservesRolesAndGovernorState() public {
        address diamond = this.deployTopology(0, false, false, false);
        // Legacy Governor's existing prefix ends at slot 9; its appended policy word is absent/zero.
        vm.store(diamond, bytes32(uint256(GOVERNOR_STORAGE_SLOT) + 10), bytes32(0));
        bytes32 admin = IAccessControl(diamond).getRoleAdmin(UPGRADE_EXECUTOR_ROLE);
        _passAndExecute(diamond, _backfillCall());
        assertEq(Governor(payable(diamond)).name(), "Governed");
        assertEq(Governor(payable(diamond)).token(), address(token));
        assertEq(Governor(payable(diamond)).votingPeriod(), 10);
        assertEq(IAccessControl(diamond).getRoleAdmin(UPGRADE_EXECUTOR_ROLE), admin);
        assertTrue(IAccessControl(diamond).hasRole(UPGRADE_EXECUTOR_ROLE, diamond));
        assertFalse(IAccessControl(diamond).hasRole(UPGRADE_EXECUTOR_ROLE, EXTERNAL));
        (address[] memory targets, uint256[] memory values, bytes[] memory calls, bytes32 hash) =
            _pass(diamond, abi.encodeCall(IGovernor.updateTimelock, (EXTERNAL)));
        vm.expectPartialRevert(INCOMPATIBLE);
        Governor(payable(diamond)).execute(targets, values, calls, hash);
    }

    function test_IncompatibleLegacyBackfillRevertsAtomically() public {
        address diamond = this.deployTopology(0, false, false, false);
        vm.store(diamond, bytes32(uint256(GOVERNOR_STORAGE_SLOT) + 10), bytes32(0));
        // Control: merely upgrading Governor cannot identify an old unmarked governed-cut deployment.
        _passAndExecute(diamond, abi.encodeCall(IGovernor.updateTimelock, (EXTERNAL)));
        assertEq(Governor(payable(diamond)).timelock(), EXTERNAL);
        bytes memory backfill = _backfillCall();
        vm.prank(diamond); // Model an explicitly authorized recovery cut, not the incompatible executor.
        (bool ok, bytes memory reason) = diamond.call(backfill);
        assertFalse(ok);
        assertEq(bytes4(reason), INCOMPATIBLE);
        assertEq(vm.load(diamond, bytes32(uint256(GOVERNOR_STORAGE_SLOT) + 10)), bytes32(0));
    }

    function _replaceCut(address diamond, address next, bool registerPolicy) private {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = IGovernedDiamondCut.diamondCut.selector;
        FacetCut[] memory cuts = new FacetCut[](1);
        cuts[0] = FacetCut(next, FacetCutAction.Replace, selectors);
        address init;
        bytes memory data;
        if (registerPolicy) {
            init = address(new GovernorTopologyReinitializer());
            data = abi.encodeCall(
                GovernorTopologyReinitializer.run,
                (
                    2,
                    address(new GovernorInit()),
                    abi.encodeCall(IAcknowledgedGovernorInit.registerGovernedCutTopology, ())
                )
            );
        }
        _passAndExecute(diamond, abi.encodeCall(IGovernedDiamondCut.diamondCut, (cuts, init, data)));
        assertEq(DiamondLoupeFacet(diamond).facetAddress(selectors[0]), next);
    }

    function _backfillCall() private returns (bytes memory) {
        return abi.encodeCall(
            IGovernedDiamondCut.diamondCut,
            (
                new FacetCut[](0),
                address(new GovernorTopologyReinitializer()),
                abi.encodeCall(
                    GovernorTopologyReinitializer.run,
                    (
                        2,
                        address(new GovernorInit()),
                        abi.encodeCall(IAcknowledgedGovernorInit.registerGovernedCutTopology, ())
                    )
                )
            )
        );
    }

    function _passAndExecute(address diamond, bytes memory callData) private {
        (address[] memory targets, uint256[] memory values, bytes[] memory calls, bytes32 hash) =
            _pass(diamond, callData);
        Governor(payable(diamond)).execute(targets, values, calls, hash);
    }

    function _pass(address diamond, bytes memory callData)
        private
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calls, bytes32 hash)
    {
        Governor governor = Governor(payable(diamond));
        targets = new address[](1);
        targets[0] = diamond;
        values = new uint256[](1);
        calls = new bytes[](1);
        calls[0] = callData;
        string memory description = string.concat("Governed topology regression ", vm.toString(++nonce));
        hash = keccak256(bytes(description));
        vm.prank(ALICE);
        uint256 id = governor.propose(targets, values, calls, description);
        vm.warp(governor.proposalSnapshot(id) + 1);
        vm.prank(ALICE);
        governor.castVote(id, uint8(IGovernor.VoteType.For));
        vm.warp(governor.proposalDeadline(id) + 1);
        if (governor.timelock() != address(0)) {
            governor.queue(targets, values, calls, hash);
            vm.warp(governor.proposalEta(id));
        }
    }
}

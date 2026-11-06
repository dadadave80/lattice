// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {MultiInit, MultiInit__StepFailed} from "@diamond/initializers/MultiInit.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlInit} from "@lattice/access/AccessControlInit.sol";
import {Governor} from "@lattice/governance/Governor.sol";
import {GovernorInit} from "@lattice/governance/GovernorInit.sol";
import {TimelockController} from "@lattice/governance/TimelockController.sol";
import {TimelockControllerInit} from "@lattice/governance/TimelockControllerInit.sol";
import {Votes} from "@lattice/governance/Votes.sol";
import {VotesInit} from "@lattice/governance/VotesInit.sol";
import {TimelockControllerLib} from "@lattice/governance/libraries/TimelockControllerLib.sol";
import {IGovernor} from "@lattice/interfaces/governance/IGovernor.sol";
import {IVotes} from "@lattice/interfaces/governance/IVotes.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Init} from "@lattice/tokens/ERC20/ERC20Init.sol";
import {ERC20VotesLib} from "@lattice/tokens/ERC20/libraries/ERC20VotesLib.sol";
import {EIP712} from "@lattice/utils/EIP712.sol";
import {Nonces} from "@lattice/utils/Nonces.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NotInitializing} from "@lattice/utils/libraries/InitializableLib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Test-only signing-domain init and checkpoint-aware minting; only mint is cut onto the token.
contract GovernanceInitTokenFixture {
    function initDomain() external {
        EIP712Lib.__EIP712_init("Vote", "1");
        NoncesLib.__Nonces_init();
    }

    function mint(address to, uint256 amount) external {
        ERC20VotesLib._mint(to, amount);
    }
}

contract GovernanceInitTarget {
    uint256 public value;

    function setValue(uint256 value_) external {
        value = value_;
    }
}

contract GovernanceInitTest is Test, BaseDeploy {
    Governor internal governor;
    TimelockController internal timelock;
    Votes internal votes;
    address internal alice;

    function setUp() public {
        vm.warp(1_000_000);
        alice = vm.addr(0xA11CE);
        Lattice tokenDiamond = new Lattice();
        Lattice timelockDiamond = new Lattice();
        Lattice governorDiamond = new Lattice();
        votes = Votes(address(tokenDiamond));
        timelock = TimelockController(payable(address(timelockDiamond)));
        governor = Governor(payable(address(governorDiamond)));
        _initializeToken(tokenDiamond);
        _initializeTimelock(timelockDiamond, address(governorDiamond));
        _initializeGovernor(governorDiamond, 10, 4);
        GovernanceInitTokenFixture(address(tokenDiamond)).mint(alice, 100e18);
        vm.prank(alice);
        votes.delegate(alice);
        vm.warp(vm.getBlockTimestamp() + 1);
    }

    function test_StandaloneStepsConfigureRealDiamondsAndRoles() public view {
        assertEq(governor.name(), "Vote governance");
        assertEq(governor.token(), address(votes));
        assertEq(governor.timelock(), address(timelock));
        assertEq(governor.votingPeriod(), 10);
        assertEq(governor.votingDelay(), 1);
        assertEq(governor.quorumNumerator(), 4);
        assertEq(timelock.getMinDelay(), 60);
        assertTrue(AccessControl(address(timelock)).hasRole(bytes32(0), address(this)));
        assertTrue(AccessControl(address(timelock)).hasRole(bytes32(0), address(timelock)));
        assertTrue(AccessControl(address(timelock)).hasRole(TimelockControllerLib.PROPOSER_ROLE, address(governor)));
        assertTrue(AccessControl(address(timelock)).hasRole(TimelockControllerLib.CANCELLER_ROLE, address(governor)));
        assertTrue(AccessControl(address(timelock)).hasRole(TimelockControllerLib.EXECUTOR_ROLE, address(0)));
        assertFalse(AccessControl(address(timelock)).hasRole(bytes32(0), alice));
        assertEq(votes.getVotes(alice), 100e18);
        assertTrue(ERC165Facet(address(votes)).supportsInterface(type(IVotes).interfaceId));
        (, string memory name, string memory version,, address verifyingContract,,) =
            EIP712(address(votes)).eip712Domain();
        assertEq(name, "Vote");
        assertEq(version, "1");
        assertEq(verifyingContract, address(votes));
        assertEq(Nonces(address(votes)).nonces(alice), 0);
    }

    function test_StandaloneInitCompositionExecutesProposalThroughTimelock() public {
        GovernanceInitTarget target = new GovernanceInitTarget();
        address[] memory targets = new address[](1);
        targets[0] = address(target);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeCall(GovernanceInitTarget.setValue, (42));
        string memory description = "Standalone init proposal";
        vm.prank(alice);
        uint256 id = governor.propose(targets, values, calls, description);
        vm.warp(governor.proposalSnapshot(id) + 1);
        vm.prank(alice);
        governor.castVote(id, uint8(IGovernor.VoteType.For));
        vm.warp(governor.proposalDeadline(id) + 1);
        bytes32 descriptionHash = keccak256(bytes(description));
        governor.queue(targets, values, calls, descriptionHash);
        vm.warp(governor.proposalEta(id));
        governor.execute(targets, values, calls, descriptionHash);
        assertEq(target.value(), 42);
        assertEq(uint256(governor.state(id)), uint256(IGovernor.ProposalState.Executed));
    }

    function test_GovernanceStepsRejectCallsOutsideInitializationWindow() public {
        VotesInit votesInit = new VotesInit();
        GovernorInit governorInit = new GovernorInit();
        TimelockControllerInit timelockInit = new TimelockControllerInit();
        address[] memory empty = new address[](0);
        vm.expectRevert(NotInitializing.selector);
        votesInit.init();
        vm.expectRevert(NotInitializing.selector);
        governorInit.init("Gov", address(votes), address(timelock), 1, 10, 0, 4);
        vm.expectRevert(NotInitializing.selector);
        timelockInit.init(60, empty, empty, address(this));
    }

    function test_GovernorStepPreservesInvalidParameterGuards() public {
        Lattice diamond = new Lattice();
        address governorInit = _init("GovernorInit");
        vm.expectRevert(
            abi.encodeWithSelector(
                MultiInit__StepFailed.selector,
                1,
                governorInit,
                abi.encodeWithSelector(IGovernor.GovernorInvalidVotingPeriod.selector, 0)
            )
        );
        this.initializeGovernor(diamond, 0, 4);
        vm.expectRevert(
            abi.encodeWithSelector(
                MultiInit__StepFailed.selector,
                1,
                governorInit,
                abi.encodeWithSelector(IGovernor.GovernorInvalidQuorumFraction.selector, 101, 100)
            )
        );
        this.initializeGovernor(diamond, 10, 101);
        _initializeGovernor(diamond, 10, 4);
        assertEq(Governor(payable(address(diamond))).votingPeriod(), 10, "failed init could not be retried");
    }

    function initializeGovernor(Lattice diamond, uint32 period, uint256 quorum) external {
        _initializeGovernor(diamond, period, quorum);
    }

    function _initializeToken(Lattice diamond) private {
        GovernanceInitTokenFixture fixture = new GovernanceInitTokenFixture();
        FacetCut[] memory cuts = new FacetCut[](6);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new ERC20()));
        cuts[2] = _cut(address(new Votes()));
        cuts[3] = _cut(address(new EIP712()));
        cuts[4] = _cut(address(new Nonces()));
        bytes4[] memory mint = new bytes4[](1);
        mint[0] = GovernanceInitTokenFixture.mint.selector;
        cuts[5] = FacetCut(address(fixture), FacetCutAction.Add, mint);
        address[] memory inits = new address[](3);
        bytes[] memory data = new bytes[](3);
        inits[0] = _init("ERC20Init");
        data[0] = abi.encodeCall(ERC20Init.init, ("Vote", "VOTE"));
        inits[1] = address(fixture);
        data[1] = abi.encodeCall(GovernanceInitTokenFixture.initDomain, ());
        inits[2] = _init("VotesInit");
        data[2] = abi.encodeCall(VotesInit.init, ());
        diamond.initialize(cuts, _init("MultiInit"), abi.encodeCall(MultiInit.multiInit, (inits, data)));
    }

    function _initializeTimelock(Lattice diamond, address proposer) private {
        FacetCut[] memory cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new TimelockController()));
        address[] memory proposers = new address[](1);
        proposers[0] = proposer;
        address[] memory executors = new address[](1);
        address[] memory inits = new address[](2);
        bytes[] memory data = new bytes[](2);
        inits[0] = _init("AccessControlInit");
        data[0] = abi.encodeCall(AccessControlInit.init, (address(this)));
        inits[1] = _init("TimelockControllerInit");
        data[1] = abi.encodeCall(TimelockControllerInit.init, (60, proposers, executors, address(this)));
        diamond.initialize(cuts, _init("MultiInit"), abi.encodeCall(MultiInit.multiInit, (inits, data)));
    }

    function _initializeGovernor(Lattice diamond, uint32 period, uint256 quorum) private {
        FacetCut[] memory cuts = new FacetCut[](3);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new Governor()));
        address[] memory inits = new address[](2);
        bytes[] memory data = new bytes[](2);
        inits[0] = _init("AccessControlInit");
        data[0] = abi.encodeCall(AccessControlInit.init, (address(this)));
        inits[1] = _init("GovernorInit");
        data[1] = abi.encodeCall(
            GovernorInit.init,
            ("Vote governance", address(votes), address(timelock), uint48(1), period, uint256(0), quorum)
        );
        diamond.initialize(cuts, _init("MultiInit"), abi.encodeCall(MultiInit.multiInit, (inits, data)));
    }
}

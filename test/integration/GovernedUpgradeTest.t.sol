// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title GovernedUpgradeTest
/// @notice End-to-end: a self-governing Diamond (Governor + Timelock + GovernedDiamondCut +
///         AccessControl + EmergencyStop in one contract) upgrades ITSELF via governance.
///
/// Flows tested:
///  1. propose(diamondCut calldata, target=self) -> vote -> queue -> timelock delay -> execute
///     -> the DummyFacet.ping selector is added to the diamond.
///  2. Guardian cancels a queued malicious cut during the delay window (CANCELLER_ROLE).
///  3. Emergency stop blocks an otherwise-valid governed cut.
///  4. An unauthorized direct caller cannot diamondCut.

import {DiamondLib, FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {ERC165Lib} from "@diamond/libraries/ERC165Lib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";

import {AccessControl} from "@lattice/access/AccessControl.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {DEFAULT_ADMIN_ROLE} from "@lattice/access/libraries/AccessControlLib.sol";
import {GovernedDiamondCut} from "@lattice/governance/GovernedDiamondCut.sol";
import {Governor} from "@lattice/governance/Governor.sol";
import {TimelockController} from "@lattice/governance/TimelockController.sol";
import {Votes} from "@lattice/governance/Votes.sol";
import {GovernedDiamondCutLib, UPGRADE_EXECUTOR_ROLE} from "@lattice/governance/libraries/GovernedDiamondCutLib.sol";
import {GovernorLib} from "@lattice/governance/libraries/GovernorLib.sol";
import {TimelockControllerLib} from "@lattice/governance/libraries/TimelockControllerLib.sol";
import {VotesLib} from "@lattice/governance/libraries/VotesLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/governance/IGovernedDiamondCut.sol";
import {IGovernor} from "@lattice/interfaces/governance/IGovernor.sol";
import {ITimelockController} from "@lattice/interfaces/governance/ITimelockController.sol";
import {EmergencyStop} from "@lattice/security/EmergencyStop.sol";
import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Votes} from "@lattice/tokens/ERC20/ERC20Votes.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {ERC20VotesLib} from "@lattice/tokens/ERC20/libraries/ERC20VotesLib.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";
import {Test} from "forge-std/Test.sol";

//*//////////////////////////////////////////////////////////////////////////
//                             MOCKS
//////////////////////////////////////////////////////////////////////////*//

/// @notice ERC20Votes governance token (copied from GovernanceStackTest). Flattens the composable {ERC20},
///         {Votes}, and {ERC20Votes} facets into one mock; the checkpoint/balance-aware overrides win the clashes.
contract GovToken is ERC20, Votes, ERC20Votes {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors() external pure virtual override(ERC20, Votes, ERC20Votes) returns (bytes memory) {}

    function transfer(address to, uint256 value) public override(ERC20, ERC20Votes) returns (bool) {
        return ERC20Votes.transfer(to, value);
    }

    function transferFrom(address from, address to, uint256 value) public override(ERC20, ERC20Votes) returns (bool) {
        return ERC20Votes.transferFrom(from, to, value);
    }

    function delegate(address delegatee) public override(Votes, ERC20Votes) {
        ERC20Votes.delegate(delegatee);
    }

    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        public
        override(Votes, ERC20Votes)
    {
        ERC20Votes.delegateBySig(delegatee, nonce, expiry, v, r, s);
    }

    function initialize(string memory name_, string memory symbol_, address admin_) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);
        ERC20Lib.__ERC20_init(name_, symbol_);
        EIP712Lib.__EIP712_init(name_, "1");
        NoncesLib.__Nonces_init();
        VotesLib.__Votes_init();
        ERC20VotesLib.__ERC20Votes_init();
        AccessControlLib.__AccessControl_init(admin_);
        InitializableLib.postInitializer(s);
    }

    function mint(address to, uint256 amount) external {
        ERC20VotesLib._mint(to, amount);
    }
}

/// @notice A trivial facet added via a governed cut to prove the cut applied.
contract DummyFacet {
    function ping() external pure returns (uint256) {
        return 7;
    }
}

/// @notice The self-governing Diamond: Governor + Timelock + GovernedDiamondCut + AccessControl +
///         EmergencyStop in one contract. Its OWN governance authorizes cuts to itself.
/// @dev Multi-inheritance mirrors MockAccessSuiteDiamond. The timelock's executor identity and the
///      cut target are the same address (this contract), so UPGRADE_EXECUTOR_ROLE -> address(this).
contract SelfGovDiamond is Governor, TimelockController, GovernedDiamondCut, AccessControl, EmergencyStop {
    /// @dev ERC-8153 clash resolver: this composite inherits multiple facets that each declare
    ///      `exportSelectors()`. It is never cut as a diamond facet, so it exports nothing.
    function exportSelectors()
        external
        pure
        virtual
        override(Governor, TimelockController, GovernedDiamondCut, AccessControl, EmergencyStop)
        returns (bytes memory)
    {}

    struct Cfg {
        string name;
        address token;
        uint48 votingDelay;
        uint32 votingPeriod;
        uint256 proposalThreshold;
        uint256 quorumNumerator;
        uint256 timelockMinDelay;
    }

    function initialize(Cfg memory cfg, address admin) external {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.preInitializer(s);

        // AccessControl first (roles live here).
        AccessControlLib.__AccessControl_init(admin);
        EIP712Lib.__EIP712_init(cfg.name, "1");
        NoncesLib.__Nonces_init();

        // Governor with timelock == self (this diamond is its own timelock).
        GovernorLib.__Governor_init(
            cfg.name,
            cfg.token,
            address(this), // timelock is self
            cfg.votingDelay,
            cfg.votingPeriod,
            cfg.proposalThreshold,
            cfg.quorumNumerator
        );

        // Timelock: governor (self) is proposer + canceller; open execution.
        address[] memory proposers = new address[](1);
        proposers[0] = address(this);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // open execution
        TimelockControllerLib.__TimelockController_init(cfg.timelockMinDelay, proposers, executors, admin);

        EmergencyStopLib.__EmergencyStop_init();
        DiamondLib.registerInterface();
        GovernedDiamondCutLib.__GovernedDiamondCut_init(); // grants UPGRADE_EXECUTOR_ROLE to address(this)

        InitializableLib.postInitializer(s);
    }

    // NOTE: In this repo the role functions (hasRole/getRoleAdmin/grant/revoke/renounceRole) are
    // declared ONLY by AccessControl — the Lattice TimelockController facet is decoupled from
    // AccessControl and exposes none of them. There is therefore no inheritance clash to resolve
    // (unlike the OZ topology the plan assumed), so they are inherited cleanly from AccessControl
    // with no override shim required.

    function supportsInterface(bytes4 id) external view returns (bool) {
        return ERC165Lib.supportsInterface(id);
    }

    function facetOf(bytes4 selector) external view returns (address) {
        return DiamondLib.diamondStorage().selectorToFacetAndPosition[selector].facetAddress;
    }

    /// @dev EIP-2535 proxy fallback (mirrors diamond-lib's `Diamond.fallback`): routes a selector
    ///      that is not statically inherited to its cut-in facet via the diamond selector table. This
    ///      is what makes a governed-cut-added selector (e.g. DummyFacet.ping) live-callable through
    ///      the proxy, proving the cut took effect end-to-end and not merely in the selector table.
    fallback() external payable virtual {
        address implementation = DiamondLib.selectorToFacet(msg.sig);
        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    receive() external payable {}
}

//*//////////////////////////////////////////////////////////////////////////
//                              TEST SUITE
//////////////////////////////////////////////////////////////////////////*//

contract GovernedUpgradeTest is Test {
    GovToken token;
    SelfGovDiamond diamond;
    DummyFacet dummy;

    address admin = address(0xAD);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address guardian = address(0x6A);
    address stranger = address(0xBEEF);

    uint256 constant INITIAL_SUPPLY = 1_000_000e18;
    uint48 constant VOTING_DELAY = 1 days;
    uint32 constant VOTING_PERIOD = 7 days;
    uint256 constant PROPOSAL_THRESHOLD = 1_000e18;
    uint256 constant QUORUM_NUMERATOR = 4;
    uint256 constant TIMELOCK_DELAY = 2 days;

    function setUp() public {
        vm.warp(1_000_000);

        token = new GovToken();
        token.initialize("Gov", "GOV", admin);
        token.mint(alice, INITIAL_SUPPLY);
        token.mint(bob, INITIAL_SUPPLY);
        vm.prank(alice);
        token.delegate(alice);
        vm.prank(bob);
        token.delegate(bob);
        vm.warp(block.timestamp + 1);

        SelfGovDiamond.Cfg memory cfg = SelfGovDiamond.Cfg({
            name: "Self Gov Diamond",
            token: address(token),
            votingDelay: VOTING_DELAY,
            votingPeriod: VOTING_PERIOD,
            proposalThreshold: PROPOSAL_THRESHOLD,
            quorumNumerator: QUORUM_NUMERATOR,
            timelockMinDelay: TIMELOCK_DELAY
        });
        diamond = new SelfGovDiamond();
        diamond.initialize(cfg, admin);

        // Admin makes a guardian for the emergency-stop tests.
        vm.prank(admin);
        diamond.addGuardian(guardian);

        dummy = new DummyFacet();
    }

    // ---- helpers ----

    function _addPingCut() internal view returns (FacetCut[] memory cuts) {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = DummyFacet.ping.selector;
        cuts = new FacetCut[](1);
        cuts[0] = FacetCut({facetAddress: address(dummy), action: FacetCutAction.Add, functionSelectors: sels});
    }

    /// @dev Builds the proposal: a single call to the diamond's own diamondCut adding ping.
    function _cutProposal()
        internal
        view
        returns (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory desc)
    {
        FacetCut[] memory cuts = _addPingCut();
        targets = new address[](1);
        targets[0] = address(diamond);
        values = new uint256[](1);
        calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(IGovernedDiamondCut.diamondCut.selector, cuts, address(0), bytes(""));
        desc = "Add DummyFacet.ping via governed cut";
    }

    // ---- 1) full governed-cut lifecycle ----

    function test_GovernedCut_FullLifecycle() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory desc) =
            _cutProposal();
        bytes32 descHash = keccak256(bytes(desc));

        // propose
        vm.prank(alice);
        uint256 pid = diamond.propose(targets, values, calldatas, desc);
        assertEq(uint8(diamond.state(pid)), uint8(IGovernor.ProposalState.Pending));

        // vote
        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.prank(alice);
        diamond.castVote(pid, uint8(IGovernor.VoteType.For));
        vm.prank(bob);
        diamond.castVote(pid, uint8(IGovernor.VoteType.For));
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        assertEq(uint8(diamond.state(pid)), uint8(IGovernor.ProposalState.Succeeded));

        // queue
        diamond.queue(targets, values, calldatas, descHash);
        assertEq(uint8(diamond.state(pid)), uint8(IGovernor.ProposalState.Queued));

        // timelock delay, then execute
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        diamond.execute(targets, values, calldatas, descHash);

        // the cut applied: ping selector now bound to the dummy facet and callable.
        assertEq(diamond.facetOf(DummyFacet.ping.selector), address(dummy));
        (bool ok, bytes memory ret) = address(diamond).call(abi.encodeWithSelector(DummyFacet.ping.selector));
        assertTrue(ok);
        assertEq(abi.decode(ret, (uint256)), 7);
        assertEq(uint8(diamond.state(pid)), uint8(IGovernor.ProposalState.Executed));
    }

    // ---- 2) guardian cancels a queued cut during the delay ----

    function test_GovernedCut_GuardianCancelDuringDelay() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory desc) =
            _cutProposal();
        bytes32 descHash = keccak256(bytes(desc));

        vm.prank(alice);
        diamond.propose(targets, values, calldatas, desc);
        vm.warp(block.timestamp + VOTING_DELAY + 1);
        vm.prank(alice);
        uint256 pid = diamond.hashProposal(targets, values, calldatas, descHash);
        diamond.castVote(pid, uint8(IGovernor.VoteType.For));
        vm.prank(bob);
        diamond.castVote(pid, uint8(IGovernor.VoteType.For));
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        diamond.queue(targets, values, calldatas, descHash);

        // The queued timelock op exists.
        bytes32 salt = bytes32(pid);
        bytes32 opId = diamond.hashOperationBatch(targets, values, calldatas, bytes32(0), salt);
        assertTrue(diamond.isOperationPending(opId));

        // Grant the guardian CANCELLER_ROLE (admin can, holding DEFAULT_ADMIN_ROLE).
        vm.prank(admin);
        diamond.grantRole(TimelockControllerLib.CANCELLER_ROLE, guardian);

        // Guardian cancels the queued cut during the delay window.
        vm.prank(guardian);
        diamond.cancel(opId);
        assertFalse(diamond.isOperationPending(opId));

        // Executing afterwards reverts (op no longer ready).
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);
        vm.expectRevert();
        diamond.execute(targets, values, calldatas, descHash);

        // ping was never added.
        assertEq(diamond.facetOf(DummyFacet.ping.selector), address(0));
    }

    // ---- 3) emergency stop blocks the governed cut at execution ----

    function test_GovernedCut_EmergencyStopBlocksExecution() public {
        (address[] memory targets, uint256[] memory values, bytes[] memory calldatas, string memory desc) =
            _cutProposal();
        bytes32 descHash = keccak256(bytes(desc));

        vm.prank(alice);
        diamond.propose(targets, values, calldatas, desc);
        vm.warp(block.timestamp + VOTING_DELAY + 1);
        uint256 pid = diamond.hashProposal(targets, values, calldatas, descHash);
        vm.prank(alice);
        diamond.castVote(pid, uint8(IGovernor.VoteType.For));
        vm.prank(bob);
        diamond.castVote(pid, uint8(IGovernor.VoteType.For));
        vm.warp(block.timestamp + VOTING_PERIOD + 1);
        diamond.queue(targets, values, calldatas, descHash);
        vm.warp(block.timestamp + TIMELOCK_DELAY + 1);

        // Guardian trips the emergency stop before execution.
        vm.prank(guardian);
        diamond.emergencyStop("freeze upgrades");

        // Execution bubbles up EmergencyStopActive from inside the cut (timelock relays the revert).
        vm.expectRevert();
        diamond.execute(targets, values, calldatas, descHash);

        assertEq(diamond.facetOf(DummyFacet.ping.selector), address(0));
    }

    // ---- 4) direct unauthorized cut reverts ----

    function test_GovernedCut_DirectCallByStrangerReverts() public {
        FacetCut[] memory cuts = _addPingCut();
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, UPGRADE_EXECUTOR_ROLE
            )
        );
        diamond.diamondCut(cuts, address(0), "");
    }

    /// @notice The role lives only on the diamond/timelock identity, never on the admin or proposer.
    function test_GovernedCut_RoleOnlyOnDiamond() public view {
        assertTrue(diamond.hasRole(UPGRADE_EXECUTOR_ROLE, address(diamond)));
        assertFalse(diamond.hasRole(UPGRADE_EXECUTOR_ROLE, admin));
        assertFalse(diamond.hasRole(UPGRADE_EXECUTOR_ROLE, alice));
    }
}

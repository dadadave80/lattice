// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployGovernedVaultENS, TestnetAsset} from "@lattice-script/base/defi/DeployGovernedVaultENS.s.sol";
import {LatticeDiamond} from "@lattice/LatticeDiamond.sol";
import {GovernedVault} from "@lattice/defi/GovernedVault.sol";
import {GovernedVaultENSParams} from "@lattice/defi/GovernedVaultENSInit.sol";
import {ENSReverseClaimer} from "@lattice/ens/ENSReverseClaimer.sol";
import {ENS_MANAGER_ROLE} from "@lattice/ens/libraries/ENSReverseClaimerLib.sol";
import {Governor} from "@lattice/governance/Governor.sol";
import {TimelockController} from "@lattice/governance/TimelockController.sol";
import {UPGRADE_EXECUTOR_ROLE} from "@lattice/governance/libraries/GovernedDiamondCutLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IENSReverseClaimer} from "@lattice/interfaces/ens/IENSReverseClaimer.sol";
import {IReverseRegistrar} from "@lattice/interfaces/external/ens/IReverseRegistrar.sol";
import {IVotes} from "@lattice/interfaces/governance/IVotes.sol";
import {IEmergencyStop} from "@lattice/interfaces/security/IEmergencyStop.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";
import {Test} from "forge-std/Test.sol";

/// @title MockReverseRegistrar
/// @notice Minimal ENS reverse registrar recording the name each caller sets for itself plus a call counter.
///         A test fixture (the external contract the init/facet forwards to — NOT the code under test).
contract MockReverseRegistrar is IReverseRegistrar {
    mapping(address caller => string name) public nameOf;
    uint256 public setNameCalls;

    function setName(string memory name) external {
        nameOf[msg.sender] = name;
        ++setNameCalls;
    }
}

/// @title GovernedVaultENSInitTest
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Non-fork proof of {GovernedVaultENSInit} wiring on a REAL {Diamond} assembled by the
///         {DeployGovernedVaultENS} recipe (14 cuts): the base {GovernedVaultInit} sequence is unchanged
///         (self-governed wiring, share metadata, timestamp clock), the ENS module is initialized with the
///         supplied reverse registrar, `ENS_MANAGER_ROLE` is held by the diamond ONLY (renames pass through
///         governance), and the reverse name is claimed inline at init time AS the diamond (the mock registrar
///         records `msg.sender == diamond`). An empty `ensName` skips the claim.
contract GovernedVaultENSInitTest is Test {
    DeployGovernedVaultENS internal deployer;
    MockReverseRegistrar internal registrar;
    TestnetAsset internal asset;

    address internal diamond;
    GovernedVault internal vault;
    Governor internal gov;
    ENSReverseClaimer internal claimer;

    address internal alice = address(0xA11CE);
    address internal stranger = address(0xC3);

    string internal constant ENS_NAME = "governed-vault.lattice.eth";
    uint256 internal constant DEPOSIT = 1_000 ether;

    function _params(address asset_, string memory ensName_) internal view returns (GovernedVaultENSParams memory p) {
        p.vault.asset = asset_;
        p.vault.name = "Governed Vault Share";
        p.vault.symbol = "gVLT";
        p.vault.decimalsOffset = 0;
        p.vault.minDelay = 300;
        p.vault.votingDelay = 60;
        p.vault.votingPeriod = 600;
        p.vault.proposalThreshold = 0;
        p.vault.quorumNumerator = 4;
        p.reverseRegistrar = address(registrar);
        p.ensName = ensName_;
    }

    function _deploy(GovernedVaultENSParams memory p) internal returns (address diamond_) {
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCutsWithENS(p);
        LatticeDiamond d = new LatticeDiamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }

    function setUp() public {
        vm.warp(1_000_000); // non-zero timestamp clock so checkpoints have room behind them
        registrar = new MockReverseRegistrar();
        asset = new TestnetAsset("Lattice Testnet Asset", "tLAT");
        deployer = new DeployGovernedVaultENS();
        diamond = _deploy(_params(address(asset), ENS_NAME));
        vault = GovernedVault(diamond);
        gov = Governor(diamond);
        claimer = ENSReverseClaimer(diamond);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ENS MODULE WIRING
    //////////////////////////////////////////////////////////////////////////*//

    function test_InitStoresReverseRegistrar() public view {
        assertEq(claimer.reverseRegistrar(), address(registrar), "registrar wired at init");
    }

    function test_InitClaimsReverseNameAsDiamond() public view {
        // The init delegatecall runs inside the diamond, so the registrar saw the DIAMOND as msg.sender —
        // exactly what makes the diamond's `addr.reverse` record resolve to the chosen name.
        assertEq(registrar.nameOf(diamond), ENS_NAME, "registrar recorded the claim under the diamond");
        assertEq(registrar.setNameCalls(), 1, "exactly one init-time claim");
        assertEq(claimer.ensName(), ENS_NAME, "facet cache matches the claim");
    }

    function test_InitGrantsEnsManagerRoleToDiamondOnly() public view {
        assertTrue(IAccessControl(diamond).hasRole(ENS_MANAGER_ROLE, diamond), "diamond holds ENS_MANAGER_ROLE");
        assertFalse(IAccessControl(diamond).hasRole(ENS_MANAGER_ROLE, address(this)), "deployer holds no ENS role");
        assertFalse(IAccessControl(diamond).hasRole(ENS_MANAGER_ROLE, stranger), "stranger holds no ENS role");
    }

    function test_EmptyEnsNameSkipsInitClaim() public {
        MockReverseRegistrar reg2 = new MockReverseRegistrar();
        GovernedVaultENSParams memory p = _params(address(asset), "");
        p.reverseRegistrar = address(reg2);
        address d2 = _deploy(p);

        assertEq(reg2.setNameCalls(), 0, "no claim for an empty name");
        assertEq(ENSReverseClaimer(d2).ensName(), "", "cache stays empty");
        assertEq(ENSReverseClaimer(d2).reverseRegistrar(), address(reg2), "registrar still wired");
    }

    function test_SetEnsNameStaysRoleGated() public {
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, ENS_MANAGER_ROLE)
        );
        claimer.setEnsName("hijack.eth");
    }

    /// @notice THE headline claim, demonstrated end-to-end: a rename passes exclusively through a passed,
    ///         timelock-executed governance proposal — propose → vote → queue → (delay) → execute — and the
    ///         registrar records the new name set BY the diamond.
    function test_GovernanceProposalRenamesEns() public {
        // Alice takes 100% of the vote supply (well past the 4% quorum) and checkpoints it.
        asset.mint(alice, DEPOSIT);
        vm.startPrank(alice);
        asset.approve(diamond, DEPOSIT);
        vault.deposit(DEPOSIT, alice);
        IVotes(diamond).delegate(alice);
        vm.stopPrank();
        vm.warp(block.timestamp + 1); // checkpoint strictly behind the proposal snapshot

        address[] memory targets = new address[](1);
        targets[0] = diamond;
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(IENSReverseClaimer.setEnsName, ("vault-v2.lattice.eth"));
        string memory description = "rename: vault-v2.lattice.eth";
        bytes32 descriptionHash = keccak256(bytes(description));

        vm.prank(alice);
        uint256 proposalId = gov.propose(targets, values, calldatas, description);

        vm.warp(block.timestamp + 61); // past votingDelay (60s) — voting opens
        vm.prank(alice);
        gov.castVote(proposalId, 1); // For

        vm.warp(block.timestamp + 601); // past votingPeriod (600s) — vote succeeds
        gov.queue(targets, values, calldatas, descriptionHash); // open execution: anyone may queue

        vm.warp(block.timestamp + 301); // past the timelock minDelay (300s)
        gov.execute(targets, values, calldatas, descriptionHash); // open execution: anyone may execute

        assertEq(registrar.nameOf(diamond), "vault-v2.lattice.eth", "registrar recorded the governed rename");
        assertEq(claimer.ensName(), "vault-v2.lattice.eth", "facet cache updated by the proposal");
        assertEq(registrar.setNameCalls(), 2, "exactly the init claim + the governed rename");
    }

    function test_SupportsIENSReverseClaimerInterface() public view {
        assertTrue(
            ERC165Facet(diamond).supportsInterface(type(IENSReverseClaimer).interfaceId),
            "IENSReverseClaimer registered"
        );
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                      BASE VAULT INIT UNCHANGED
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The governed-upgradeability replay (step 1b) is wired on the ENS variant too: the diamond —
    ///         and only the diamond — holds the self-administered UPGRADE_EXECUTOR_ROLE, and the cut, loupe,
    ///         and emergency-stop ERC-165 flags are all advertised. Deleting any of the three step-1b init
    ///         calls from {GovernedVaultENSInit} makes this fail.
    function test_GovernedUpgradeabilityReplayedInEnsInit() public view {
        assertTrue(IAccessControl(diamond).hasRole(UPGRADE_EXECUTOR_ROLE, diamond), "diamond holds executor role");
        assertFalse(IAccessControl(diamond).hasRole(UPGRADE_EXECUTOR_ROLE, address(this)), "deployer must not");
        assertTrue(ERC165Facet(diamond).supportsInterface(0x1f931c1c), "IDiamondCut flag missing");
        assertTrue(ERC165Facet(diamond).supportsInterface(0x48e2b093), "IDiamondLoupe flag missing");
        assertTrue(
            ERC165Facet(diamond).supportsInterface(type(IEmergencyStop).interfaceId), "IEmergencyStop flag missing"
        );
    }

    function test_SelfGovernedWiringUnchanged() public view {
        assertEq(gov.token(), diamond, "governor votes come from the diamond's own shares");
        assertEq(gov.timelock(), diamond, "governor queues through the diamond's own timelock");
        assertTrue(IAccessControl(diamond).hasRole(0x00, diamond), "diamond holds its own DEFAULT_ADMIN_ROLE");
    }

    /// @notice Every governance parameter lands on ITS OWN getter — a fresh diamond with all-distinct values
    ///         (61/601/7/5/301) makes ANY pairwise swap in the hand-copied init sequence fail loudly.
    function test_GovernanceParamsWiredExactly() public {
        GovernedVaultENSParams memory p = _params(address(asset), ENS_NAME);
        p.reverseRegistrar = address(new MockReverseRegistrar());
        p.vault.minDelay = 301;
        p.vault.votingDelay = 61;
        p.vault.votingPeriod = 601;
        p.vault.proposalThreshold = 7;
        p.vault.quorumNumerator = 5;
        address d2 = _deploy(p);

        assertEq(Governor(d2).votingDelay(), 61, "votingDelay");
        assertEq(Governor(d2).votingPeriod(), 601, "votingPeriod");
        assertEq(Governor(d2).proposalThreshold(), 7, "proposalThreshold");
        assertEq(Governor(d2).quorumNumerator(), 5, "quorumNumerator");
        assertEq(TimelockController(d2).getMinDelay(), 301, "timelock minDelay");
    }

    function test_VaultMetadataUnchanged() public view {
        assertEq(vault.name(), "Governed Vault Share", "share name");
        assertEq(IERC20(diamond).symbol(), "gVLT", "share symbol");
        assertEq(IERC4626(diamond).asset(), address(asset), "underlying asset");
        assertEq(IERC20(diamond).decimals(), 18, "asset decimals + zero offset");
        assertEq(vault.CLOCK_MODE(), "mode=timestamp", "timestamp clock (governor params are in seconds)");
    }

    function test_DepositGrantsVotingPower() public {
        asset.mint(alice, DEPOSIT);
        vm.startPrank(alice);
        asset.approve(diamond, DEPOSIT);
        uint256 shares = vault.deposit(DEPOSIT, alice);
        IVotes(diamond).delegate(alice);
        vm.stopPrank();
        vm.warp(block.timestamp + 1);

        assertEq(shares, DEPOSIT, "1:1 shares on an empty vault");
        assertEq(IERC20(diamond).balanceOf(alice), DEPOSIT, "shares minted");
        assertEq(IVotes(diamond).getVotes(alice), DEPOSIT, "delegated deposit = voting power");
    }

    function test_WithdrawReturnsAssetsAndReducesVotes() public {
        asset.mint(alice, DEPOSIT);
        vm.startPrank(alice);
        asset.approve(diamond, DEPOSIT);
        vault.deposit(DEPOSIT, alice);
        IVotes(diamond).delegate(alice);

        // The other half of the dogfooding loop: withdrawing burns shares, returns the underlying, and the
        // checkpoint seam reduces voting power in the same move.
        uint256 shares = vault.withdraw(DEPOSIT / 2, alice, alice);
        vm.stopPrank();
        vm.warp(block.timestamp + 1);

        assertEq(shares, DEPOSIT / 2, "1:1 share burn on withdraw");
        assertEq(asset.balanceOf(alice), DEPOSIT / 2, "underlying returned to alice");
        assertEq(IERC20(diamond).balanceOf(alice), DEPOSIT / 2, "half the shares burned");
        assertEq(IVotes(diamond).getVotes(alice), DEPOSIT / 2, "voting power reduced with the burn");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              COMPOSABILITY
    //////////////////////////////////////////////////////////////////////////*//

    function test_FourteenCutsAssembleWithoutSelectorClash() public {
        // A second full assembly re-runs all 14 Add cuts; any duplicate selector across the base recipe and
        // the appended ENSReverseClaimer facet would revert CannotAddFunctionToDiamondThatAlreadyExists.
        address d2 = _deploy(_params(address(asset), ENS_NAME));
        assertTrue(d2 != address(0), "second assembly succeeds");
    }

    function test_BuildCutsWithENSReturnsFourteenCuts() public {
        (FacetCut[] memory cuts,,) = deployer.buildCutsWithENS(_params(address(asset), ENS_NAME));
        assertEq(cuts.length, 14, "13 base cuts + ENSReverseClaimer");
    }
}

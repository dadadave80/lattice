// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Diamond} from "@diamond/Diamond.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {DeployGovernedVaultENS, TestnetAsset} from "@lattice-script/base/defi/DeployGovernedVaultENS.s.sol";
import {RegisterEnsName} from "@lattice-script/config/RegisterEnsName.s.sol";
import {GovernedVault} from "@lattice/defi/GovernedVault.sol";
import {GovernedVaultENSParams} from "@lattice/defi/GovernedVaultENSInit.sol";
import {ENSReverseClaimer} from "@lattice/ens/ENSReverseClaimer.sol";
import {ENS_MANAGER_ROLE} from "@lattice/ens/libraries/ENSReverseClaimerLib.sol";
import {Governor} from "@lattice/governance/Governor.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IENS} from "@lattice/interfaces/external/IENS.sol";
import {IETHRegistrarController} from "@lattice/interfaces/external/IETHRegistrarController.sol";
import {IGovernor} from "@lattice/interfaces/governance/IGovernor.sol";
import {IVotes} from "@lattice/interfaces/governance/IVotes.sol";
import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Reverse-node reads on the REAL Sepolia ReverseRegistrar (`node(addr)` is pure upstream).
interface IReverseRegistrarNode {
    function node(address addr) external pure returns (bytes32);
}

/// @notice ENS name-resolver read used to resolve the claimed reverse record on the fork.
interface INameResolver {
    function name(bytes32 node) external view returns (string memory);
}

/// @notice ENS addr-resolver surface used to wire + check the forward record in the post-registration flow.
interface IAddrResolver {
    function addr(bytes32 node) external view returns (address);
    function setAddr(bytes32 node, address a) external;
}

/// @notice ENS registry write surface for the owner's post-registration resolver wiring.
interface IENSSetResolver {
    function setResolver(bytes32 node, address resolver) external;
}

/// @notice Exposes {RegisterEnsName}'s internal Registration builder so the fork test drives the LIVE
///         controller with the SCRIPT'S OWN struct — pinning the vendored ABI byte-match end-to-end.
contract RegisterEnsNameProbe is RegisterEnsName {
    function registration(string calldata label, address owner)
        external
        pure
        returns (IETHRegistrarController.Registration memory)
    {
        return _registration(label, owner);
    }
}

/// @title GovernedVaultENSFork
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Sepolia fork proof of the {DeployGovernedVaultENS} recipe against the REAL ENS deployment: the
///         14-facet self-governed vault diamond assembles, the vault flows work (metadata, deposit, delegation
///         checkpoint on the timestamp clock, threshold-0 propose), and the init-time reverse claim lands in the
///         live ENS registry — the diamond's `addr.reverse` node resolves to the chosen name through the real
///         {ReverseRegistrar} default resolver.
///
/// Enabling this test:
///   export SEPOLIA_RPC_URL=<your-sepolia-rpc-url>
///   forge test --match-path "test/fork/GovernedVaultENSFork.t.sol"
///
/// The test is skipped cleanly when SEPOLIA_RPC_URL is unset.
contract GovernedVaultENSFork is Test {
    //*//////////////////////////////////////////////////////////////////////////
    //             VERIFIED SEPOLIA ADDRESSES (ensdomains/ens-contracts)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice ENS registry (deployments/sepolia/ENSRegistry.json).
    address internal constant SEPOLIA_ENS_REGISTRY = 0x00000000000C2E074eC69A0dFb2997BA6C7d2e1e;

    /// @notice ENS reverse registrar (deployments/sepolia/ReverseRegistrar.json).
    address internal constant SEPOLIA_REVERSE_REGISTRAR = 0xA0a1AbcDAe1a2a4A2EF8e9113Ff0e02DD81DC0C6;

    /// @notice ENS .eth registrar controller — the LIVE controller authorized on the Sepolia BaseRegistrar
    ///         (see the provenance note in {RegisterEnsName}; the ens-contracts deployment artifact address
    ///         is deployed but NOT authorized, and registering through it reverts).
    address internal constant SEPOLIA_ETH_REGISTRAR_CONTROLLER = 0xdf60C561Ca35AD3C89D24BbA854654b1c3477078;

    /// @notice ENS public resolver (deployments/sepolia/PublicResolver.json).
    address internal constant SEPOLIA_PUBLIC_RESOLVER = 0xE99638b40E4Fff0129D56f03b55b6bbC4BBE49b5;

    /// @notice A recent Sepolia block; overridable via SEPOLIA_FORK_BLOCK for a fresher value. Pinned so runs
    ///         are reproducible and forge's RPC cache actually hits (matches the other fork suites).
    uint256 internal constant DEFAULT_FORK_BLOCK = 11_239_288;

    string internal constant ENS_NAME = "governed-vault.lattice.eth";

    uint48 internal constant VOTING_DELAY = 60; // seconds (timestamp clock)
    uint32 internal constant VOTING_PERIOD = 600; // seconds (timestamp clock)
    uint256 internal constant MIN_DELAY = 300; // seconds
    uint256 internal constant DEPOSIT = 1_000 ether;

    DeployGovernedVaultENS internal deployer;
    TestnetAsset internal asset;
    address internal diamond;
    GovernedVault internal vault;
    Governor internal gov;
    ENSReverseClaimer internal claimer;

    address internal alice = address(0xA11CE);

    function _params() internal view returns (GovernedVaultENSParams memory p) {
        p.vault.asset = address(asset);
        p.vault.name = "Governed Vault Share";
        p.vault.symbol = "gVLT";
        p.vault.decimalsOffset = 0;
        p.vault.minDelay = MIN_DELAY;
        p.vault.votingDelay = VOTING_DELAY;
        p.vault.votingPeriod = VOTING_PERIOD;
        p.vault.proposalThreshold = 0;
        p.vault.quorumNumerator = 4;
        p.reverseRegistrar = SEPOLIA_REVERSE_REGISTRAR;
        p.ensName = ENS_NAME;
    }

    function _deploy() internal returns (address diamond_) {
        (FacetCut[] memory cuts, address init, bytes memory initCalldata) = deployer.buildCutsWithENS(_params());
        Diamond d = new Diamond();
        d.initialize(cuts, init, initCalldata);
        diamond_ = address(d);
    }

    function setUp() public {
        string memory rpc = vm.envOr("SEPOLIA_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork("sepolia", vm.envOr("SEPOLIA_FORK_BLOCK", DEFAULT_FORK_BLOCK));

        asset = new TestnetAsset("Lattice Testnet Asset", "tLAT");
        deployer = new DeployGovernedVaultENS();
        diamond = _deploy();
        vault = GovernedVault(diamond);
        gov = Governor(diamond);
        claimer = ENSReverseClaimer(diamond);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                VAULT FLOWS
    //////////////////////////////////////////////////////////////////////////*//

    function test_Fork_VaultMetadata() public view {
        assertEq(vault.name(), "Governed Vault Share", "share name");
        assertEq(IERC20(diamond).symbol(), "gVLT", "share symbol");
        assertEq(IERC4626(diamond).asset(), address(asset), "underlying testnet asset");
        assertEq(IERC20(diamond).decimals(), 18, "asset decimals + zero offset");
        assertEq(vault.CLOCK_MODE(), "mode=timestamp", "timestamp clock");
    }

    function test_Fork_DepositMintsShares() public {
        _depositAndDelegate(alice, DEPOSIT);
        assertEq(IERC20(diamond).balanceOf(alice), DEPOSIT, "1:1 shares minted on an empty vault");
    }

    function test_Fork_WithdrawReturnsUnderlying() public {
        _depositAndDelegate(alice, DEPOSIT);

        vm.prank(alice);
        vault.withdraw(DEPOSIT / 2, alice, alice);

        assertEq(asset.balanceOf(alice), DEPOSIT / 2, "underlying returned to alice");
        assertEq(IERC20(diamond).balanceOf(alice), DEPOSIT / 2, "half the shares burned");
    }

    function test_Fork_DelegationCheckpointsVotes() public {
        _depositAndDelegate(alice, DEPOSIT);
        uint256 snapshot = block.timestamp;
        vm.warp(block.timestamp + 1); // advance the TIMESTAMP clock past the checkpoint
        assertGt(IVotes(diamond).getVotes(alice), 0, "delegated deposit = live voting power");
        assertEq(IVotes(diamond).getPastVotes(alice, snapshot), DEPOSIT, "checkpoint visible in the past");
    }

    function test_Fork_ProposeWithZeroThresholdSucceeds() public {
        _depositAndDelegate(alice, DEPOSIT);
        vm.warp(block.timestamp + 1);

        address[] memory targets = new address[](1);
        targets[0] = diamond;
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeCall(ENSReverseClaimer.setEnsName, ("renamed-vault.lattice.eth"));

        vm.prank(alice);
        uint256 proposalId = gov.propose(targets, values, calldatas, "Rename the vault through governance");
        assertTrue(proposalId != 0, "proposal created");
        assertEq(uint8(gov.state(proposalId)), uint8(IGovernor.ProposalState.Pending), "pending until votingDelay");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             ENS REVERSE CLAIM
    //////////////////////////////////////////////////////////////////////////*//

    function test_Fork_InitClaimResolvesThroughRealENS() public view {
        // Resolve the diamond's reverse record through the REAL registry: addr.reverse node -> resolver ->
        // name(node). The init-time claim ran AS the diamond, so the live record must match.
        bytes32 node = IReverseRegistrarNode(SEPOLIA_REVERSE_REGISTRAR).node(diamond);
        address resolver = IENS(SEPOLIA_ENS_REGISTRY).resolver(node);
        assertTrue(resolver != address(0), "reverse node claimed with the registrar's default resolver");
        assertEq(INameResolver(resolver).name(node), ENS_NAME, "live reverse record matches the init claim");
        assertEq(claimer.ensName(), ENS_NAME, "facet cache matches");
        assertEq(claimer.reverseRegistrar(), SEPOLIA_REVERSE_REGISTRAR, "real registrar wired");
    }

    function test_Fork_EnsManagerRoleHeldByDiamondOnly() public view {
        assertTrue(IAccessControl(diamond).hasRole(ENS_MANAGER_ROLE, diamond), "diamond holds ENS_MANAGER_ROLE");
        assertFalse(IAccessControl(diamond).hasRole(ENS_MANAGER_ROLE, address(this)), "no external ENS manager");
        assertFalse(IAccessControl(diamond).hasRole(ENS_MANAGER_ROLE, alice), "no external ENS manager (alice)");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    .ETH REGISTRATION (LIVE CONTROLLER)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The COMPLETE documented naming flow against the LIVE Sepolia ENS deployment: register the
    ///         bare name through {RegisterEnsName}'s exact Registration struct (this controller generation
    ///         has no commit/reveal and refuses in-registration record writes — rent priced internally,
    ///         excess refunded), then, as the owner, wire the forward record to the DIAMOND (the runbook's
    ///         two post-deploy calls) and resolve it back through the real registry.
    function test_Fork_RegisterEnsNameFlowAgainstLiveController() public {
        RegisterEnsNameProbe probe = new RegisterEnsNameProbe();
        IETHRegistrarController controller = IETHRegistrarController(SEPOLIA_ETH_REGISTRAR_CONTROLLER);

        // A label long/random enough to be unregistered at the pinned block.
        string memory label = "lattice-governed-vault-fork-probe";
        address owner = alice;

        // Step 1 — register bare (the script's exact struct). The controller prices internally and refunds
        // the excess (at the pinned block Sepolia rent prices to ZERO, so the full send comes back — the
        // refund path is exercised either way; never assert a live price, only that we cannot overpay).
        uint256 value = 0.01 ether; // the script's fixed send
        vm.deal(address(this), value);
        uint256 balanceBefore = address(this).balance;
        controller.register{value: value}(probe.registration(label, owner));
        assertLe(balanceBefore - address(this).balance, value, "never spends more than the send");

        // The registry hands the fresh node to the owner, with no resolver yet (bare registration).
        bytes32 ethNode = 0x93cdeb708b7545dc668eb9280176169d1c33cfd8ed6f04690a0bcc88a93fc4ae;
        bytes32 node = keccak256(abi.encodePacked(ethNode, keccak256(bytes(label))));
        assertEq(IENS(SEPOLIA_ENS_REGISTRY).owner(node), owner, "registry node owned by the registrant");

        // Step 2 — the owner wires the forward record to the DIAMOND (the runbook's two calls).
        vm.startPrank(owner);
        IENSSetResolver(SEPOLIA_ENS_REGISTRY).setResolver(node, SEPOLIA_PUBLIC_RESOLVER);
        IAddrResolver(SEPOLIA_PUBLIC_RESOLVER).setAddr(node, diamond);
        vm.stopPrank();

        // The name now forward-resolves to the vault diamond through the real registry + PublicResolver.
        address resolver = IENS(SEPOLIA_ENS_REGISTRY).resolver(node);
        assertEq(resolver, SEPOLIA_PUBLIC_RESOLVER, "resolver wired by the owner");
        assertEq(IAddrResolver(resolver).addr(node), diamond, "forward addr record points at the diamond");
    }

    /// @dev Accepts the controller's excess-rent refund during {test_Fork_RegisterEnsNameFlowAgainstLiveController}.
    receive() external payable {}

    //*//////////////////////////////////////////////////////////////////////////
    //                              COMPOSABILITY
    //////////////////////////////////////////////////////////////////////////*//

    function test_Fork_FourteenFacetCutsAssembleWithoutSelectorClash() public {
        // Re-assembling the full 14-cut recipe re-adds every selector; any overlap between the base recipe and
        // the appended ENSReverseClaimer facet would revert CannotAddFunctionToDiamondThatAlreadyExists.
        address d2 = _deploy();
        assertTrue(d2 != address(0), "second 14-facet assembly succeeds");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    function _depositAndDelegate(address who, uint256 amount) internal {
        asset.mint(who, amount);
        vm.startPrank(who);
        asset.approve(diamond, amount);
        vault.deposit(amount, who);
        IVotes(diamond).delegate(who);
        vm.stopPrank();
    }
}

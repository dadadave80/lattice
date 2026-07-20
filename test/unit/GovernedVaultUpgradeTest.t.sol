// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {IDiamondLoupe} from "@diamond/interfaces/IDiamondLoupe.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {TestnetAsset} from "@lattice-script/base/defi/DeployGovernedVaultENS.s.sol";
import {GovernedVaultTestBase} from "@lattice-test/base/GovernedVaultTestBase.sol";
import {GovernedVaultParams} from "@lattice/defi/GovernedVaultInit.sol";
import {Governor} from "@lattice/governance/Governor.sol";
import {UPGRADE_EXECUTOR_ROLE} from "@lattice/governance/libraries/GovernedDiamondCutLib.sol";
import {IAccessControl} from "@lattice/interfaces/access/IAccessControl.sol";
import {IFrozenSelectors} from "@lattice/interfaces/governance/IFrozenSelectors.sol";
import {IGovernedDiamondCut} from "@lattice/interfaces/governance/IGovernedDiamondCut.sol";
import {IUpgradeRegistry} from "@lattice/interfaces/governance/IUpgradeRegistry.sol";
import {IVotes} from "@lattice/interfaces/governance/IVotes.sol";
import {IEmergencyStop} from "@lattice/interfaces/security/IEmergencyStop.sol";
import {IERC4626} from "@lattice/interfaces/tokens/IERC4626.sol";

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

        vm.warp(block.timestamp + 61); // past votingDelay (60s)
        vm.prank(alice);
        gov.castVote(proposalId, 1); // For

        vm.warp(block.timestamp + 601); // past votingPeriod (600s)
        gov.queue(targets, values, calldatas, descriptionHash);

        vm.warp(block.timestamp + 301); // past the timelock minDelay (300s)
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
        FacetCut[] memory cuts = _probeCuts();
        _govern(
            abi.encodeCall(IGovernedDiamondCut.diamondCut, (cuts, address(0), bytes(""))),
            "upgrade: add VaultUpgradeProbeFacet"
        );

        assertEq(VaultUpgradeProbeFacet(vault).vaultProbePing(), 42, "probe facet not routed after the cut");
        assertEq(IUpgradeRegistry(vault).cutCount(), 1, "cut recorded in the upgrade registry");
        // The timelock relays the queued call as an external self-call, so the recorded executor is the vault.
        assertEq(IUpgradeRegistry(vault).getCutRecord(1).executor, vault, "executor is the diamond (timelock)");
        assertEq(IDiamondLoupe(vault).facetAddresses().length, 15, "probe facet joined the loupe");
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

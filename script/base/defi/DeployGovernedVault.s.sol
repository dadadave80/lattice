// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLoupeFacet} from "@diamond/facets/DiamondLoupeFacet.sol";
import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {LatticeFactory} from "@lattice/LatticeFactory.sol";
import {Receive} from "@lattice/Receive.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {GovernedVault} from "@lattice/defi/GovernedVault.sol";
import {GovernedVaultInit, GovernedVaultParams} from "@lattice/defi/GovernedVaultInit.sol";
import {VaultCore} from "@lattice/defi/VaultCore.sol";
import {GovernedDiamondCut} from "@lattice/governance/GovernedDiamondCut.sol";
import {Governor} from "@lattice/governance/Governor.sol";
import {TimelockController} from "@lattice/governance/TimelockController.sol";
import {Votes} from "@lattice/governance/Votes.sol";
import {DiamondValidationLib} from "@lattice/governance/libraries/DiamondValidationLib.sol";
import {RecipeEntry} from "@lattice/interfaces/ILatticeFactory.sol";
import {EmergencyStop} from "@lattice/security/EmergencyStop.sol";
import {ERC20} from "@lattice/tokens/ERC20/ERC20.sol";
import {ERC20Votes} from "@lattice/tokens/ERC20/ERC20Votes.sol";
import {ERC4626} from "@lattice/tokens/ERC4626/ERC4626.sol";

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
        init = address(new GovernedVaultInit());
        initCalldata = abi.encodeCall(GovernedVaultInit.init, (p));
    }

    /// @notice Unique storage owners, including dependencies shared across facets.
    /// @dev Initializable and the reentrancy guard use fixed non-ERC-7201 slots; see the guide.
    function storageNamespaces() public pure returns (string[] memory ids) {
        ids = new string[](14);
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
    }

    /// @dev The 14 base facet cuts alone — shared with recipes that EXTEND this one under a different
    ///      initializer (they must not pay for a discarded {GovernedVaultInit} deployment). The last three
    ///      are the anti-frozen-diamond set: {DiamondLoupeFacet} (EIP-2535 introspection),
    ///      {EmergencyStop} (guardian halt + resume surface for the governed cut), and
    ///      {GovernedDiamondCut} (the `0x1f931c1c` upgrade path, reachable ONLY through a passed,
    ///      timelock-executed proposal — see {GovernedVaultInit}). All diamond-lib facets are cut via the
    ///      ERC-8153 address helpers (diamond-lib ≥0.2.0 facets self-report their selectors) — no FFI.
    function _buildBaseCuts() internal returns (FacetCut[] memory cuts) {
        cuts = new FacetCut[](14);
        cuts[0] = _cut(address(new ERC165Facet()));
        cuts[1] = _cut(address(new AccessControl()));
        cuts[2] = _cut(address(new TimelockController()));
        cuts[3] = _cutExcept(address(new ERC20()), _erc20Exclusions());
        cuts[4] = _cutExcept(address(new ERC4626()), _erc4626Exclusions());
        cuts[5] = _cutExcept(address(new VaultCore()), _vaultExclusions());
        cuts[6] = _cutExcept(address(new Votes()), _votesExclusions());
        cuts[7] = _cutExcept(address(new ERC20Votes()), _erc20VotesExclusions());
        cuts[8] = _cutExcept(address(new Governor()), _governorExclusions());
        cuts[9] = _cut(address(new GovernedVault()));
        cuts[10] = _cut(address(new DiamondLoupeFacet()));
        cuts[11] = _cut(address(new EmergencyStop()));
        cuts[12] = _cut(address(new GovernedDiamondCut()));
        cuts[13] = _cut(address(new Receive()));
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

    /// @notice ERC-4626 clashes: strategy-aware `totalAssets` and the checkpoint-seam mint/burn flows.
    function _erc4626Exclusions() private pure returns (bytes4[] memory e) {
        e = new bytes4[](5);
        e[0] = bytes4(keccak256("totalAssets()"));
        e[1] = bytes4(keccak256("deposit(uint256,address)"));
        e[2] = bytes4(keccak256("mint(uint256,address)"));
        e[3] = bytes4(keccak256("withdraw(uint256,address,address)"));
        e[4] = bytes4(keccak256("redeem(uint256,address,address)"));
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

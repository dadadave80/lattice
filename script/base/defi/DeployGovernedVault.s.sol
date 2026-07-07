// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC165Facet} from "@diamond/facets/ERC165Facet.sol";
import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {AccessControl} from "@lattice/access/AccessControl.sol";
import {GovernedVault} from "@lattice/defi/GovernedVault.sol";
import {GovernedVaultInit, GovernedVaultParams} from "@lattice/defi/GovernedVaultInit.sol";
import {VaultCore} from "@lattice/defi/VaultCore.sol";
import {Governor} from "@lattice/governance/Governor.sol";
import {TimelockController} from "@lattice/governance/TimelockController.sol";
import {Votes} from "@lattice/governance/Votes.sol";
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
///         {TimelockController} — plus a thin {GovernedVault} reconciliation facet. {GovernedVaultInit} wires the
///         Governor's `token`/`timelock` and the vault's admin to the diamond, so share-holders propose → vote →
///         queue → (delay) → execute.
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
        cuts = new FacetCut[](10);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()), "AccessControl");
        cuts[2] = _cut(address(new TimelockController()), "TimelockController");
        cuts[3] = _cutExcept(address(new ERC20()), "ERC20", _erc20Exclusions());
        cuts[4] = _cutExcept(address(new ERC4626()), "ERC4626", _erc4626Exclusions());
        cuts[5] = _cutExcept(address(new VaultCore()), "VaultCore", _vaultExclusions());
        cuts[6] = _cutExcept(address(new Votes()), "Votes", _votesExclusions());
        cuts[7] = _cutExcept(address(new ERC20Votes()), "ERC20Votes", _erc20VotesExclusions());
        cuts[8] = _cutExcept(address(new Governor()), "Governor", _governorExclusions());
        cuts[9] = _cut(address(new GovernedVault()), "GovernedVault");

        init = address(new GovernedVaultInit());
        initCalldata = abi.encodeCall(GovernedVaultInit.init, (p));
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

    /// @notice An `Add` cut of `facet`'s selectors MINUS `excluded` — for facets whose reconciled selectors are
    ///         owned by {GovernedVault} (or by a sibling facet) instead.
    function _cutExcept(address facet, string memory name, bytes4[] memory excluded)
        internal
        returns (FacetCut memory)
    {
        bytes4[] memory all = _getSelectors(name);
        bytes4[] memory kept = new bytes4[](all.length);
        uint256 n;
        for (uint256 i; i < all.length; ++i) {
            if (!_contains(excluded, all[i])) kept[n++] = all[i];
        }
        assembly ("memory-safe") {
            mstore(kept, n)
        }
        return FacetCut({facetAddress: facet, action: FacetCutAction.Add, functionSelectors: kept});
    }

    function _contains(bytes4[] memory set, bytes4 sel) private pure returns (bool) {
        for (uint256 i; i < set.length; ++i) {
            if (set[i] == sel) return true;
        }
        return false;
    }

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

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
import {ERC20Votes} from "@lattice/tokens/ERC20/ERC20Votes.sol";

/// @title DeployGovernedVault
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Ready-to-deploy recipe for a SELF-GOVERNED ERC-4626 vault: ONE diamond whose vote-weighted shares
///         elect an on-chain Governor + Timelock that governs the vault itself, with no external admin. The
///         diamond hosts the NATURAL facets — {VaultCore} (strategy-aware ERC-4626 over ERC-20 shares),
///         {ERC20Votes} (checkpointed vote weight), {Governor}, {TimelockController} — plus a thin
///         {GovernedVault} reconciliation facet. {GovernedVaultInit} wires the Governor's `token`/`timelock`
///         and the vault's admin to the diamond, so share-holders propose → vote → queue → (delay) → execute.
/// @dev A single mega-facet inheriting all four would be ~45 kB (EIP-170 is 24,576 B), so each facet is cut for
///      its OWN selectors and {GovernedVault} owns the handful that either CLASH across facets or are MODIFIED
///      for the single-diamond topology. Those selectors are EXCLUDED from the base facets' cuts (via
///      {_cutExcept}) and provided once by {GovernedVault}:
///      - `name` — excluded from VaultCore (its ERC-20) and Governor.
///      - `clock`/`CLOCK_MODE` — excluded from ERC20Votes (its Votes) and Governor.
///      - `transfer`/`transferFrom` — excluded from VaultCore (base ERC-20) and ERC20Votes.
///      - `deposit`/`mint`/`withdraw`/`redeem` — excluded from VaultCore (the checkpoint-seam versions win).
///      - `castVoteBySig` — excluded from Governor (the namespaced-nonce version wins).
contract DeployGovernedVault is BaseDeploy {
    /// @notice Builds the self-governed vault diamond cuts + initializer (no broadcast, no proxy deploy).
    function buildCuts(GovernedVaultParams memory p)
        public
        returns (FacetCut[] memory cuts, address init, bytes memory initCalldata)
    {
        cuts = new FacetCut[](7);
        cuts[0] = _cut(address(new ERC165Facet()), "ERC165Facet");
        cuts[1] = _cut(address(new AccessControl()), "AccessControl");
        cuts[2] = _cut(address(new TimelockController()), "TimelockController");
        cuts[3] = _cutExcept(address(new VaultCore()), "VaultCore", _vaultExclusions());
        cuts[4] = _cutExcept(address(new ERC20Votes()), "ERC20Votes", _votesExclusions());
        cuts[5] = _cutExcept(address(new Governor()), "Governor", _governorExclusions());
        cuts[6] = _cut(address(new GovernedVault()), "GovernedVault");

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
    ///         owned by {GovernedVault} instead.
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

    function _vaultExclusions() private pure returns (bytes4[] memory e) {
        e = new bytes4[](7);
        e[0] = bytes4(keccak256("name()"));
        e[1] = bytes4(keccak256("transfer(address,uint256)"));
        e[2] = bytes4(keccak256("transferFrom(address,address,uint256)"));
        e[3] = bytes4(keccak256("deposit(uint256,address)"));
        e[4] = bytes4(keccak256("mint(uint256,address)"));
        e[5] = bytes4(keccak256("withdraw(uint256,address,address)"));
        e[6] = bytes4(keccak256("redeem(uint256,address,address)"));
    }

    function _votesExclusions() private pure returns (bytes4[] memory e) {
        e = new bytes4[](4);
        e[0] = bytes4(keccak256("transfer(address,uint256)"));
        e[1] = bytes4(keccak256("transferFrom(address,address,uint256)"));
        e[2] = bytes4(keccak256("clock()"));
        e[3] = bytes4(keccak256("CLOCK_MODE()"));
    }

    function _governorExclusions() private pure returns (bytes4[] memory e) {
        e = new bytes4[](4);
        e[0] = bytes4(keccak256("name()"));
        e[1] = bytes4(keccak256("clock()"));
        e[2] = bytes4(keccak256("CLOCK_MODE()"));
        e[3] = bytes4(keccak256("castVoteBySig(uint256,uint8,address,bytes)"));
    }
}

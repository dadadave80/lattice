// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib} from "@diamond/libraries/DiamondLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {GovernedVaultParams} from "@lattice/defi/GovernedVaultInit.sol";
import {GovernedVaultLib} from "@lattice/defi/libraries/GovernedVaultLib.sol";
import {VaultCoreLib} from "@lattice/defi/libraries/VaultCoreLib.sol";
import {ENSReverseClaimerLib, ENS_MANAGER_ROLE} from "@lattice/ens/libraries/ENSReverseClaimerLib.sol";
import {GovernedDiamondCutLib} from "@lattice/governance/libraries/GovernedDiamondCutLib.sol";
import {GovernorLib} from "@lattice/governance/libraries/GovernorLib.sol";
import {TimelockControllerLib} from "@lattice/governance/libraries/TimelockControllerLib.sol";
import {VotesLib} from "@lattice/governance/libraries/VotesLib.sol";
import {IENSReverseClaimer} from "@lattice/interfaces/ens/IENSReverseClaimer.sol";
import {IReverseRegistrar} from "@lattice/interfaces/external/ens/IReverseRegistrar.sol";
import {EmergencyStopLib} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {ERC20VotesLib} from "@lattice/tokens/ERC20/libraries/ERC20VotesLib.sol";
import {ERC4626Lib} from "@lattice/tokens/ERC4626/libraries/ERC4626Lib.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";

/// @notice Parameters for the ENS-named self-governed vault (grouped to avoid stack-too-deep).
struct GovernedVaultENSParams {
    GovernedVaultParams vault; // the base self-governed vault parameters
    address reverseRegistrar; // the chain's ENS reverse registrar (Sepolia: the ENS ReverseRegistrar)
    string ensName; // primary ENS name claimed at init (empty string skips the inline claim)
}

/// @title GovernedVaultENSInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for the ENS-named self-governed ERC-4626 vault diamond: runs
///         {GovernedVaultInit}'s EXACT module sequence (AccessControl seeded ONCE with the diamond itself,
///         share token, EIP-712 domain, vote checkpoints, timelock, governor), then wires the ENS module —
///         the reverse registrar is stored, `ENS_MANAGER_ROLE` is granted to the DIAMOND ONLY (so renames pass
///         exclusively through a passed, timelock-executed governance proposal), and, when `ensName` is
///         non-empty, the reverse name is claimed inline. The claim works because this contract is
///         delegatecalled by {Diamond.initialize}: `address(this)` IS the diamond, so the registrar sees the
///         DIAMOND as `msg.sender` — exactly the self-claim that makes the diamond's `addr.reverse` record
///         resolve to `ensName`.
/// @dev Delegatecalled inside the diamond's initializing window — each `__*_init` guard passes because the
///      window is already open; it must NOT open its own pre/postInitializer. The inline claim mirrors
///      {ENSReverseClaimerLib.setEnsName} minus its `ENS_MANAGER_ROLE` gate (which checks `msg.sender` — the
///      deployer during init, deliberately NOT a role holder): cache the name (CEI), forward `setName` to the
///      registrar, emit {IENSReverseClaimer.EnsNameSet}. It must NOT call {ENSReverseClaimerInit}, which would
///      re-run `__AccessControl_init` and clobber the self-admin wiring.
contract GovernedVaultENSInit {
    function init(GovernedVaultENSParams calldata p) external {
        address self = address(this); // the diamond (delegatecall context)

        // 1. Access control — the diamond (as its own timelock) holds DEFAULT_ADMIN_ROLE; no external admin.
        AccessControlLib.__AccessControl_init(self);

        // 1b. Governed upgradeability — replayed EXACTLY from {GovernedVaultInit}: guardian surface armed
        //     (nobody appointed), cut + loupe ERC-165 flags registered, and UPGRADE_EXECUTOR_ROLE granted to
        //     the diamond ONLY + self-administered, so a passed, timelock-executed proposal is the ONLY
        //     upgrade path. No selectors are frozen at init.
        EmergencyStopLib.__EmergencyStop_init();
        DiamondLib.registerInterface();
        GovernedDiamondCutLib.__GovernedDiamondCut_init();

        // 2. Share token: ERC-20 metadata, ERC-4626 vault params, EIP-712 domain + nonces + vote checkpoints.
        ERC20Lib.__ERC20_init(p.vault.name, p.vault.symbol);
        ERC4626Lib.__ERC4626_init(p.vault.asset, p.vault.decimalsOffset);
        EIP712Lib.__EIP712_init(p.vault.name, "1");
        NoncesLib.__Nonces_init();
        VotesLib.__Votes_init();
        ERC20VotesLib.__ERC20Votes_init();
        VaultCoreLib.__VaultCore_init();

        // 3. Timelock: the diamond is the sole PROPOSER (so the Governor can queue) and its own admin; execution
        //    is open (address(0)).
        address[] memory proposers = new address[](1);
        proposers[0] = self;
        address[] memory executors = new address[](1);
        executors[0] = address(0);
        TimelockControllerLib.__TimelockController_init(p.vault.minDelay, proposers, executors, self);

        // 4. Governor: votes come from THIS diamond's shares; queued proposals route through THIS diamond's
        //    timelock.
        GovernorLib.__Governor_init(
            p.vault.name,
            self,
            self,
            p.vault.votingDelay,
            p.vault.votingPeriod,
            p.vault.proposalThreshold,
            p.vault.quorumNumerator
        );

        // 5. Register the vault's own (ballot-nonce) ERC-165 id.
        GovernedVaultLib.registerInterface();

        // 6. ENS identity: wire the reverse registrar and gate all future renames behind governance — the
        //    diamond is the ONLY ENS_MANAGER_ROLE holder, so `setEnsName` is reachable exclusively through a
        //    passed, timelock-executed proposal.
        ENSReverseClaimerLib.__ENSReverseClaimer_init(p.reverseRegistrar);
        AccessControlLib._grantRole(ENS_MANAGER_ROLE, self);

        // 7. Inline reverse claim (skipped for an empty name): `address(this)` is the diamond, so the registrar
        //    records the claim under the diamond's own `addr.reverse` node.
        if (bytes(p.ensName).length != 0) {
            ENSReverseClaimerLib.ensReverseClaimerStorage()._ensName = p.ensName;
            IReverseRegistrar(p.reverseRegistrar).setName(p.ensName);
            emit IENSReverseClaimer.EnsNameSet(p.ensName);
        }
    }
}

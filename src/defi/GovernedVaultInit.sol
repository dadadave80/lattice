// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {GovernedVaultLib} from "@lattice/defi/libraries/GovernedVaultLib.sol";
import {VaultCoreLib} from "@lattice/defi/libraries/VaultCoreLib.sol";
import {GovernorLib} from "@lattice/governance/libraries/GovernorLib.sol";
import {TimelockControllerLib} from "@lattice/governance/libraries/TimelockControllerLib.sol";
import {VotesLib} from "@lattice/governance/libraries/VotesLib.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {ERC20VotesLib} from "@lattice/tokens/ERC20/libraries/ERC20VotesLib.sol";
import {ERC4626Lib} from "@lattice/tokens/ERC4626/libraries/ERC4626Lib.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";

/// @notice Governance parameters for the self-governed vault (grouped to avoid stack-too-deep).
struct GovernedVaultParams {
    address asset; // underlying ERC-20 the vault holds
    string name; // share-token name (also the EIP-712 domain name + governor name)
    string symbol; // share-token symbol
    uint8 decimalsOffset; // ERC-4626 virtual-share offset (usually 0)
    uint256 minDelay; // timelock delay (seconds) between queue and execute
    uint48 votingDelay; // clock units between proposal creation and voting start
    uint32 votingPeriod; // clock units the vote stays open (must be > 0)
    uint256 proposalThreshold; // min votes to create a proposal
    uint256 quorumNumerator; // quorum as numerator over QUORUM_DENOMINATOR
}

/// @title GovernedVaultInit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice One-shot initializer for the self-governed ERC-4626 vault diamond. Runs every module initializer in
///         dependency order inside a single initializing window. The SELF-REFERENTIAL wiring is the crux: this
///         contract is delegatecalled by {Diamond.initialize}, so `address(this)` IS the diamond — the
///         {Governor}'s vote `token` and `timelock` are both set to it, the timelock's sole proposer is it (so
///         the Governor can queue), and its `DEFAULT_ADMIN_ROLE` (the vault's strategy-admin gate) is held by it
///         (i.e. only reachable through a passed, timelock-executed proposal). Execution is left OPEN
///         (`executor = address(0)`), so anyone may execute a proposal once its delay elapses.
/// @dev Delegatecalled inside the diamond's initializing window — each `__*_init` guard passes because the
///      window is already open; it must NOT open its own pre/postInitializer.
contract GovernedVaultInit {
    function init(GovernedVaultParams calldata p) external {
        address self = address(this); // the diamond (delegatecall context)

        // 1. Access control — the diamond (as its own timelock) holds DEFAULT_ADMIN_ROLE; no external admin.
        AccessControlLib.__AccessControl_init(self);

        // 2. Share token: ERC-20 metadata, ERC-4626 vault params, EIP-712 domain + nonces + vote checkpoints.
        ERC20Lib.__ERC20_init(p.name, p.symbol);
        ERC4626Lib.__ERC4626_init(p.asset, p.decimalsOffset);
        EIP712Lib.__EIP712_init(p.name, "1");
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
        TimelockControllerLib.__TimelockController_init(p.minDelay, proposers, executors, self);

        // 4. Governor: votes come from THIS diamond's shares; queued proposals route through THIS diamond's
        //    timelock.
        GovernorLib.__Governor_init(
            p.name, self, self, p.votingDelay, p.votingPeriod, p.proposalThreshold, p.quorumNumerator
        );

        // 5. Register the vault's own (ballot-nonce) ERC-165 id.
        GovernedVaultLib.registerInterface();
    }
}

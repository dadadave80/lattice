// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Governor} from "@lattice/governance/Governor.sol";
import {GovernorLib} from "@lattice/governance/libraries/GovernorLib.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";

/// @title GovernorStandalone
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/Governor.sol)
/// @notice Non-Diamond deployable Governor. Runs the full initialization dance in
///         the constructor and accepts ETH for value-bearing proposal execution.
/// @dev Initializes EIP-712 (for castVoteBySig), Nonces (for signature replay-protection),
///      and Governor in a single pre/post initializer block.
///      The token_ address must implement {IVotes} (e.g. an ERC20Votes token).
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source OpenZeppelin v5.1.0
contract GovernorStandalone is Governor {
    /// @param name_ Human-readable name of the governor and EIP-712 signing domain.
    /// @param token_ IVotes-compatible voting token.
    /// @param timelock_ Optional TimelockController (address(0) for direct execution).
    /// @param votingDelay_ Delay before voting starts (in seconds for timestamp mode).
    /// @param votingPeriod_ Duration of the voting window (must be > 0).
    /// @param proposalThreshold_ Minimum voting power to submit a proposal.
    /// @param quorumNumerator_ Quorum as a percentage of total supply (0–100).
    /// @notice Governance configuration struct to avoid stack-too-deep.
    struct Config {
        string name;
        address token;
        address timelock;
        uint48 votingDelay;
        uint32 votingPeriod;
        uint256 proposalThreshold;
        uint256 quorumNumerator;
    }

    constructor(Config memory cfg) {
        bytes32 s = InitializableLib.initializableSlot();
        s = InitializableLib.preInitializer(s);
        EIP712Lib.__EIP712_init(cfg.name, "1");
        NoncesLib.__Nonces_init();
        GovernorLib.__Governor_init(
            cfg.name,
            cfg.token,
            cfg.timelock,
            cfg.votingDelay,
            cfg.votingPeriod,
            cfg.proposalThreshold,
            cfg.quorumNumerator
        );
        InitializableLib.postInitializer(s);
    }

    /// @notice Accept ETH so the governor can hold and forward value during proposal execution.
    receive() external payable {}
}

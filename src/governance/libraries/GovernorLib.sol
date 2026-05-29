// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ContextLib} from "@diamond/libraries/ContextLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";
import {SignatureChecker} from "@lattice/utils/libraries/SignatureChecker.sol";
import {IGovernor} from "@lattice/interfaces/IGovernor.sol";
import {IVotes} from "@lattice/interfaces/IVotes.sol";
import {ITimelockController} from "@lattice/interfaces/ITimelockController.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.Governor")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant GOVERNOR_STORAGE_SLOT = 0x20a7901cc1c78eb01d63d9c1875355513c3dabc82d8607ad0f82e1312f750c00;

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant GOVERNOR_ERC165_STORAGE_LOCATION = 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x7d3554af is `type(IGovernor).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x7d3554af), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IGOVERNOR_SLOT = 0x1721450696844f78c528c7efd225c94c965fc94f208ba0b176ffddc2587dcbe1;

/// @dev EIP-712 typehash for the Ballot struct.
bytes32 constant BALLOT_TYPEHASH = keccak256("Ballot(uint256 proposalId,uint8 support,address voter,uint256 nonce)");

/// @notice Core proposal data stored for each proposal.
/// @dev Packed tightly: proposer (20 bytes) + voteStart (6 bytes) + voteDuration (4 bytes)
///      + executed (1 byte) + canceled (1 byte) + etaSeconds (6 bytes) = 38 bytes (fits in 2 slots).
struct ProposalCore {
    /// @dev The address that submitted the proposal.
    address proposer;
    /// @dev The clock value at which voting begins (voteStart = creation clock + votingDelay).
    uint48 voteStart;
    /// @dev Duration of the voting period (in clock units).
    uint32 voteDuration;
    /// @dev Whether the proposal has been executed.
    bool executed;
    /// @dev Whether the proposal has been canceled.
    bool canceled;
    /// @dev Timelock ETA in seconds (0 if not queued).
    uint48 etaSeconds;
}

/// @notice Per-proposal vote tallies and per-voter tracking.
struct ProposalVote {
    /// @dev Cumulative Against votes.
    uint256 againstVotes;
    /// @dev Cumulative For votes.
    uint256 forVotes;
    /// @dev Cumulative Abstain votes.
    uint256 abstainVotes;
    /// @dev Tracks whether each voter has already cast a vote.
    mapping(address voter => bool) hasVoted;
}

/// @notice ERC-7201 namespaced storage for the Governor module.
/// @custom:storage-location erc7201:lattice.storage.Governor
struct GovernorStorage {
    /// @dev Human-readable name of the governor.
    string _name;
    /// @dev IVotes token used to read voting power.
    address _token;
    /// @dev Optional TimelockController. address(0) means direct execution.
    address _timelock;
    /// @dev Delay (in clock units) before voting starts after proposal creation.
    uint48 _votingDelay;
    /// @dev Duration (in clock units) of the voting window.
    uint32 _votingPeriod;
    /// @dev Minimum voting power required to create a proposal.
    uint256 _proposalThreshold;
    /// @dev Quorum numerator (percentage points, denominator = 100).
    uint256 _quorumNumerator;
    /// @dev Proposals indexed by proposal ID.
    mapping(uint256 proposalId => ProposalCore) _proposals;
    /// @dev Vote tallies indexed by proposal ID.
    mapping(uint256 proposalId => ProposalVote) _proposalVotes;
    /// @dev Maps timelock operation ID → proposal ID for cancel tracking.
    mapping(bytes32 timelockId => uint256 proposalId) _timelockIds;
    /// @dev Maps proposal ID → timelock operation ID (reverse of _timelockIds).
    mapping(uint256 proposalId => bytes32 timelockId) _proposalTimelockIds;
}

/// @title GovernorLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Library implementing the full on-chain governance lifecycle: proposal creation,
///         voting (For/Against/Abstain with quorum), optional timelock queuing, execution,
///         and cancellation. Includes EIP-712 `castVoteBySig` support.
/// @dev Three-layer pattern: this library holds all logic and state. The stateless
///      {Governor} facet delegates every external call here.
library GovernorLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                               CONSTANTS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Quorum denominator: quorum = (totalSupply * quorumNumerator) / QUORUM_DENOMINATOR.
    uint256 internal constant QUORUM_DENOMINATOR = 100;

    //*//////////////////////////////////////////////////////////////////////////
    //                           STORAGE ACCESSOR
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns a storage reference to the GovernorStorage struct.
    function governorStorage() internal pure returns (GovernorStorage storage $) {
        assembly {
            $.slot := GOVERNOR_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            INTERFACE REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IGovernor interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IGOVERNOR_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the Governor module.
    /// @param name_ The human-readable name of the governor.
    /// @param token_ The IVotes-compatible token used for voting power.
    /// @param timelock_ Optional TimelockController address (address(0) for direct execution).
    /// @param votingDelay_ Delay in clock units before voting starts (can be 0).
    /// @param votingPeriod_ Duration in clock units of the voting window (must be > 0).
    /// @param proposalThreshold_ Minimum voting power required to create a proposal.
    /// @param quorumNumerator_ Quorum as a percentage of total supply (0–100).
    /// @dev Must be called between preInitializer and postInitializer.
    function __Governor_init(
        string memory name_,
        address token_,
        address timelock_,
        uint48 votingDelay_,
        uint32 votingPeriod_,
        uint256 proposalThreshold_,
        uint256 quorumNumerator_
    ) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        if (votingPeriod_ == 0) revert IGovernor.GovernorInvalidVotingPeriod(0);
        if (quorumNumerator_ > QUORUM_DENOMINATOR) {
            revert IGovernor.GovernorInvalidQuorumFraction(quorumNumerator_, QUORUM_DENOMINATOR);
        }
        GovernorStorage storage $ = governorStorage();
        $._name = name_;
        $._token = token_;
        $._timelock = timelock_;
        $._votingDelay = votingDelay_;
        $._votingPeriod = votingPeriod_;
        $._proposalThreshold = proposalThreshold_;
        $._quorumNumerator = quorumNumerator_;
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the human-readable name of this governor.
    function name() internal view returns (string memory) {
        return governorStorage()._name;
    }

    /// @notice Returns the version string ("1").
    function version() internal pure returns (string memory) {
        return "1";
    }

    /// @notice Returns the IVotes token address.
    function token() internal view returns (address) {
        return governorStorage()._token;
    }

    /// @notice Returns the configured TimelockController address (address(0) if none).
    function timelock() internal view returns (address) {
        return governorStorage()._timelock;
    }

    /// @notice Returns the current clock value as uint48 (block.timestamp).
    function clock() internal view returns (uint48) {
        return uint48(block.timestamp);
    }

    /// @notice Returns the machine-readable clock mode string.
    function CLOCK_MODE() internal pure returns (string memory) {
        return "mode=timestamp";
    }

    /// @notice Returns the counting mode string (Bravo: For/Against/Abstain).
    function COUNTING_MODE() internal pure returns (string memory) {
        return "support=bravo&quorum=for,abstain";
    }

    /// @notice Returns the voting delay in clock units.
    function votingDelay() internal view returns (uint256) {
        return governorStorage()._votingDelay;
    }

    /// @notice Returns the voting period duration in clock units.
    function votingPeriod() internal view returns (uint256) {
        return governorStorage()._votingPeriod;
    }

    /// @notice Returns the proposal threshold (minimum voting power to propose).
    function proposalThreshold() internal view returns (uint256) {
        return governorStorage()._proposalThreshold;
    }

    /// @notice Returns the current quorum numerator.
    function quorumNumerator() internal view returns (uint256) {
        return governorStorage()._quorumNumerator;
    }

    /// @notice Returns the quorum numerator at a given timepoint.
    /// @dev Simplified: returns the current numerator (no historical tracking).
    function quorumNumeratorAt(uint256 /* timepoint */ ) internal view returns (uint256) {
        return governorStorage()._quorumNumerator;
    }

    /// @notice Returns the quorum denominator (100).
    function quorumDenominator() internal pure returns (uint256) {
        return QUORUM_DENOMINATOR;
    }

    /// @notice Returns the quorum (in token units) required at a given past timepoint.
    /// @param timepoint The past clock value to query.
    function quorum(uint256 timepoint) internal view returns (uint256) {
        GovernorStorage storage $ = governorStorage();
        uint256 totalSupply = IVotes($._token).getPastTotalSupply(timepoint);
        return (totalSupply * $._quorumNumerator) / QUORUM_DENOMINATOR;
    }

    /// @notice Returns the voting power of an account at a past timepoint.
    function getVotes(address account, uint256 timepoint) internal view returns (uint256) {
        return IVotes(governorStorage()._token).getPastVotes(account, timepoint);
    }

    /// @notice Computes the proposal ID from targets, values, calldatas, and description hash.
    function hashProposal(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(targets, values, calldatas, descriptionHash)));
    }

    /// @notice Returns the clock value at which voting starts for a proposal.
    function proposalSnapshot(uint256 proposalId) internal view returns (uint256) {
        return governorStorage()._proposals[proposalId].voteStart;
    }

    /// @notice Returns the clock value at which voting ends for a proposal.
    function proposalDeadline(uint256 proposalId) internal view returns (uint256) {
        ProposalCore storage p = governorStorage()._proposals[proposalId];
        return p.voteStart + p.voteDuration;
    }

    /// @notice Returns the address that created a proposal.
    function proposalProposer(uint256 proposalId) internal view returns (address) {
        return governorStorage()._proposals[proposalId].proposer;
    }

    /// @notice Returns the timelock ETA for a proposal (0 if not queued).
    function proposalEta(uint256 proposalId) internal view returns (uint256) {
        return governorStorage()._proposals[proposalId].etaSeconds;
    }

    /// @notice Returns the vote totals for a proposal.
    function proposalVotes(uint256 proposalId)
        internal
        view
        returns (uint256 againstVotes, uint256 forVotes, uint256 abstainVotes)
    {
        ProposalVote storage pv = governorStorage()._proposalVotes[proposalId];
        return (pv.againstVotes, pv.forVotes, pv.abstainVotes);
    }

    /// @notice Returns whether an account has voted on a proposal.
    function hasVoted(uint256 proposalId, address account) internal view returns (bool) {
        return governorStorage()._proposalVotes[proposalId].hasVoted[account];
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              STATE LOGIC
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the current state of a proposal.
    /// @dev State transitions (ordered by finality):
    ///      Executed → Canceled → Pending → Active → Defeated → Succeeded → Queued → Expired
    function state(uint256 proposalId) internal view returns (IGovernor.ProposalState) {
        ProposalCore storage p = governorStorage()._proposals[proposalId];
        if (p.executed) return IGovernor.ProposalState.Executed;
        if (p.canceled) return IGovernor.ProposalState.Canceled;
        uint256 snapshot = p.voteStart;
        if (snapshot == 0) revert IGovernor.GovernorNonexistentProposal(proposalId);
        if (snapshot >= block.timestamp) return IGovernor.ProposalState.Pending;
        uint256 deadline = snapshot + p.voteDuration;
        if (deadline >= block.timestamp) return IGovernor.ProposalState.Active;
        if (!_voteSucceeded(proposalId) || !_quorumReached(proposalId)) {
            return IGovernor.ProposalState.Defeated;
        }
        if (p.etaSeconds == 0) return IGovernor.ProposalState.Succeeded;
        // Proposal has been queued — consult the live timelock operation state.
        address timelockAddr = governorStorage()._timelock;
        if (timelockAddr != address(0)) {
            bytes32 timelockId = governorStorage()._proposalTimelockIds[proposalId];
            if (ITimelockController(timelockAddr).isOperationDone(timelockId)) {
                // Timelock already executed the operation (defensive; execute() sets executed=true).
                return IGovernor.ProposalState.Executed;
            }
            if (ITimelockController(timelockAddr).isOperationPending(timelockId)) {
                // Still pending in timelock: check expiry grace period.
                if (block.timestamp > uint256(p.etaSeconds) + 14 days) return IGovernor.ProposalState.Expired;
                return IGovernor.ProposalState.Queued;
            }
            // Operation is no longer pending (was externally canceled in the timelock).
            return IGovernor.ProposalState.Canceled;
        }
        // No timelock configured but etaSeconds is set — fallback grace period check.
        if (block.timestamp > uint256(p.etaSeconds) + 14 days) return IGovernor.ProposalState.Expired;
        return IGovernor.ProposalState.Queued;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            MUTATING FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Creates a new proposal.
    /// @param targets Contract addresses to call.
    /// @param values ETH values for each call.
    /// @param calldatas Encoded calldata for each call.
    /// @param description Human-readable description of the proposal.
    /// @return proposalId The unique ID of the new proposal.
    function propose(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) internal returns (uint256) {
        address proposer = ContextLib.msgSender();
        if (targets.length == 0) {
            revert IGovernor.GovernorInvalidProposalLength(0, 0, 0);
        }
        if (targets.length != values.length || targets.length != calldatas.length) {
            revert IGovernor.GovernorInvalidProposalLength(targets.length, calldatas.length, values.length);
        }

        uint256 proposerVotes = getVotes(proposer, clock() - 1);
        uint256 threshold = governorStorage()._proposalThreshold;
        if (proposerVotes < threshold) {
            revert IGovernor.GovernorInsufficientProposerVotes(proposer, proposerVotes, threshold);
        }

        uint256 proposalId = hashProposal(targets, values, calldatas, keccak256(bytes(description)));
        ProposalCore storage p = governorStorage()._proposals[proposalId];
        // Revert if proposal already exists (voteStart would be non-zero)
        if (p.voteStart != 0) {
            revert IGovernor.GovernorUnexpectedProposalState(
                proposalId, state(proposalId), _encodeStateBitmap(IGovernor.ProposalState.Pending)
            );
        }

        _storeAndEmitProposal(proposalId, proposer, targets, values, calldatas, description);

        return proposalId;
    }

    /// @dev Stores proposal core data and emits ProposalCreated. Extracted to avoid stack-too-deep.
    function _storeAndEmitProposal(
        uint256 proposalId,
        address proposer,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description
    ) private {
        uint48 voteStart = uint48(clock() + governorStorage()._votingDelay);
        uint32 voteDur = governorStorage()._votingPeriod;

        ProposalCore storage p = governorStorage()._proposals[proposalId];
        p.proposer = proposer;
        p.voteStart = voteStart;
        p.voteDuration = voteDur;

        // Build empty signatures array (OZ compatibility)
        string[] memory signatures = new string[](targets.length);

        emit IGovernor.ProposalCreated(
            proposalId,
            proposer,
            targets,
            values,
            signatures,
            calldatas,
            voteStart,
            voteStart + voteDur,
            description
        );
    }

    /// @notice Queue a succeeded proposal in the TimelockController.
    /// @param targets Contract addresses to call.
    /// @param values ETH values for each call.
    /// @param calldatas Encoded calldata for each call.
    /// @param descriptionHash keccak256 hash of the description string.
    /// @return proposalId The proposal ID.
    function queue(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);

        IGovernor.ProposalState currentState = state(proposalId);
        if (currentState != IGovernor.ProposalState.Succeeded) {
            revert IGovernor.GovernorUnexpectedProposalState(
                proposalId, currentState, _encodeStateBitmap(IGovernor.ProposalState.Succeeded)
            );
        }

        address timelockAddr = governorStorage()._timelock;
        if (timelockAddr == address(0)) revert IGovernor.GovernorQueueNotImplemented();

        // Use proposalId as the salt for the timelock operation
        bytes32 salt = bytes32(proposalId);
        bytes32 timelockId =
            ITimelockController(timelockAddr).hashOperationBatch(targets, values, calldatas, bytes32(0), salt);

        uint256 minDelay = ITimelockController(timelockAddr).getMinDelay();
        ITimelockController(timelockAddr).scheduleBatch(targets, values, calldatas, bytes32(0), salt, minDelay);

        uint48 eta = uint48(block.timestamp + minDelay);
        governorStorage()._proposals[proposalId].etaSeconds = eta;
        governorStorage()._timelockIds[timelockId] = proposalId;
        governorStorage()._proposalTimelockIds[proposalId] = timelockId;

        emit IGovernor.ProposalQueued(proposalId, eta);

        return proposalId;
    }

    /// @notice Execute a proposal (succeeded with no timelock, or queued+ready with timelock).
    /// @param targets Contract addresses to call.
    /// @param values ETH values for each call.
    /// @param calldatas Encoded calldata for each call.
    /// @param descriptionHash keccak256 hash of the description string.
    /// @return proposalId The proposal ID.
    function execute(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);

        IGovernor.ProposalState currentState = state(proposalId);
        address timelockAddr = governorStorage()._timelock;

        if (timelockAddr != address(0)) {
            // With timelock: must be Queued
            if (currentState != IGovernor.ProposalState.Queued) {
                revert IGovernor.GovernorUnexpectedProposalState(
                    proposalId, currentState, _encodeStateBitmap(IGovernor.ProposalState.Queued)
                );
            }
        } else {
            // Without timelock: must be Succeeded
            if (currentState != IGovernor.ProposalState.Succeeded) {
                revert IGovernor.GovernorUnexpectedProposalState(
                    proposalId, currentState, _encodeStateBitmap(IGovernor.ProposalState.Succeeded)
                );
            }
        }

        // CEI: mark executed before any external calls
        governorStorage()._proposals[proposalId].executed = true;

        emit IGovernor.ProposalExecuted(proposalId);

        if (timelockAddr != address(0)) {
            bytes32 salt = bytes32(proposalId);
            ITimelockController(timelockAddr).executeBatch(targets, values, calldatas, bytes32(0), salt);
        } else {
            for (uint256 i = 0; i < targets.length; ++i) {
                // solhint-disable-next-line avoid-low-level-calls
                (bool success,) = targets[i].call{value: values[i]}(calldatas[i]);
                if (!success) {
                    assembly ("memory-safe") {
                        let returnDataSize := returndatasize()
                        if returnDataSize {
                            let ptr := mload(0x40)
                            returndatacopy(ptr, 0, returnDataSize)
                            revert(ptr, returnDataSize)
                        }
                        revert(0, 0)
                    }
                }
            }
        }

        return proposalId;
    }

    /// @notice Cancel a proposal. Proposer can cancel in any non-terminal state
    ///         (Pending, Active, Succeeded, or Queued). If the proposal is Queued, also
    ///         cancels the corresponding timelock operation.
    /// @param targets Contract addresses for the proposal.
    /// @param values ETH values for the proposal.
    /// @param calldatas Calldata for the proposal.
    /// @param descriptionHash keccak256 hash of the description string.
    /// @return proposalId The proposal ID.
    function cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);

        IGovernor.ProposalState currentState = state(proposalId);
        // Allow cancel in any non-terminal state: Pending, Active, Succeeded, Queued.
        bytes32 allowedStates = _encodeStateBitmap(IGovernor.ProposalState.Pending)
            | _encodeStateBitmap(IGovernor.ProposalState.Active)
            | _encodeStateBitmap(IGovernor.ProposalState.Succeeded)
            | _encodeStateBitmap(IGovernor.ProposalState.Queued);
        if (
            currentState != IGovernor.ProposalState.Pending && currentState != IGovernor.ProposalState.Active
                && currentState != IGovernor.ProposalState.Succeeded && currentState != IGovernor.ProposalState.Queued
        ) {
            revert IGovernor.GovernorUnexpectedProposalState(proposalId, currentState, allowedStates);
        }

        address caller = ContextLib.msgSender();
        if (caller != governorStorage()._proposals[proposalId].proposer) {
            revert IGovernor.GovernorOnlyExecutor(caller);
        }

        // If the proposal is queued, cancel the corresponding timelock operation.
        GovernorStorage storage $ = governorStorage();
        ProposalCore storage p = $._proposals[proposalId];
        if (p.etaSeconds != 0) {
            address timelockAddr = $._timelock;
            if (timelockAddr != address(0)) {
                bytes32 timelockId = $._proposalTimelockIds[proposalId];
                ITimelockController(timelockAddr).cancel(timelockId);
            }
        }

        p.canceled = true;

        emit IGovernor.ProposalCanceled(proposalId);

        return proposalId;
    }

    /// @notice Cast a vote on an active proposal.
    /// @param proposalId The proposal to vote on.
    /// @param support Vote type: 0=Against, 1=For, 2=Abstain.
    /// @return weight The voter's voting power at the proposal snapshot.
    function castVote(uint256 proposalId, uint8 support) internal returns (uint256) {
        address voter = ContextLib.msgSender();
        return _castVote(proposalId, voter, support, "", "");
    }

    /// @notice Cast a vote with a reason string.
    /// @param proposalId The proposal to vote on.
    /// @param support Vote type: 0=Against, 1=For, 2=Abstain.
    /// @param reason Human-readable reason for the vote.
    /// @return weight The voter's voting power at the proposal snapshot.
    function castVoteWithReason(uint256 proposalId, uint8 support, string calldata reason)
        internal
        returns (uint256)
    {
        address voter = ContextLib.msgSender();
        return _castVote(proposalId, voter, support, reason, "");
    }

    /// @notice Cast a vote via an EIP-712 signature.
    /// @param proposalId The proposal to vote on.
    /// @param support Vote type: 0=Against, 1=For, 2=Abstain.
    /// @param voter The address that signed the vote.
    /// @param signature EIP-712 signature over the Ballot struct.
    /// @return weight The voter's voting power at the proposal snapshot.
    function castVoteBySig(uint256 proposalId, uint8 support, address voter, bytes memory signature)
        internal
        returns (uint256)
    {
        uint256 nonce = NoncesLib.useNonce(voter);
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support, voter, nonce));
        bytes32 hash = EIP712Lib.hashTypedDataV4(structHash);

        if (!SignatureChecker.isValidSignatureNow(voter, hash, signature)) {
            revert IGovernor.GovernorInvalidSignature(voter);
        }

        return _castVote(proposalId, voter, support, "", "");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ADMIN SETTERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Update the voting delay. Callable only via a passed governance proposal.
    /// @param newVotingDelay The new voting delay in clock units.
    function setVotingDelay(uint48 newVotingDelay) internal {
        _onlyGovernance();
        GovernorStorage storage $ = governorStorage();
        emit IGovernor.VotingDelaySet($._votingDelay, newVotingDelay);
        $._votingDelay = newVotingDelay;
    }

    /// @notice Update the voting period. Callable only via a passed governance proposal.
    /// @param newVotingPeriod The new voting period in clock units (must be > 0).
    function setVotingPeriod(uint32 newVotingPeriod) internal {
        _onlyGovernance();
        if (newVotingPeriod == 0) revert IGovernor.GovernorInvalidVotingPeriod(0);
        GovernorStorage storage $ = governorStorage();
        emit IGovernor.VotingPeriodSet($._votingPeriod, newVotingPeriod);
        $._votingPeriod = newVotingPeriod;
    }

    /// @notice Update the proposal threshold. Callable only via a passed governance proposal.
    /// @param newProposalThreshold The new minimum voting power to propose.
    function setProposalThreshold(uint256 newProposalThreshold) internal {
        _onlyGovernance();
        GovernorStorage storage $ = governorStorage();
        emit IGovernor.ProposalThresholdSet($._proposalThreshold, newProposalThreshold);
        $._proposalThreshold = newProposalThreshold;
    }

    /// @notice Update the quorum numerator. Callable only via a passed governance proposal.
    /// @param newQuorumNumerator New quorum percentage (0–100).
    function updateQuorumNumerator(uint256 newQuorumNumerator) internal {
        _onlyGovernance();
        if (newQuorumNumerator > QUORUM_DENOMINATOR) {
            revert IGovernor.GovernorInvalidQuorumFraction(newQuorumNumerator, QUORUM_DENOMINATOR);
        }
        GovernorStorage storage $ = governorStorage();
        emit IGovernor.QuorumNumeratorUpdated($._quorumNumerator, newQuorumNumerator);
        $._quorumNumerator = newQuorumNumerator;
    }

    /// @notice Update the timelock address. Callable only via a passed governance proposal.
    /// @param newTimelock The new TimelockController address (or address(0) to disable).
    function updateTimelock(address newTimelock) internal {
        _onlyGovernance();
        address old = governorStorage()._timelock;
        governorStorage()._timelock = newTimelock;
        emit IGovernor.TimelockChange(old, newTimelock);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INTERNAL HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Internal implementation for all vote casting paths.
    function _castVote(
        uint256 proposalId,
        address voter,
        uint8 support,
        string memory reason,
        bytes memory params
    ) internal returns (uint256 weight) {
        IGovernor.ProposalState currentState = state(proposalId);
        if (currentState != IGovernor.ProposalState.Active) {
            revert IGovernor.GovernorUnexpectedProposalState(
                proposalId, currentState, _encodeStateBitmap(IGovernor.ProposalState.Active)
            );
        }

        ProposalVote storage pv = governorStorage()._proposalVotes[proposalId];
        if (pv.hasVoted[voter]) revert IGovernor.GovernorAlreadyCastVote(voter);

        uint256 snapshot = governorStorage()._proposals[proposalId].voteStart;
        weight = IVotes(governorStorage()._token).getPastVotes(voter, snapshot);

        pv.hasVoted[voter] = true;

        if (support == uint8(IGovernor.VoteType.Against)) {
            pv.againstVotes += weight;
        } else if (support == uint8(IGovernor.VoteType.For)) {
            pv.forVotes += weight;
        } else if (support == uint8(IGovernor.VoteType.Abstain)) {
            pv.abstainVotes += weight;
        }

        if (params.length == 0) {
            emit IGovernor.VoteCast(voter, proposalId, support, weight, reason);
        } else {
            emit IGovernor.VoteCastWithParams(voter, proposalId, support, weight, reason, params);
        }
    }

    /// @dev Returns true if forVotes > againstVotes.
    function _voteSucceeded(uint256 proposalId) internal view returns (bool) {
        ProposalVote storage pv = governorStorage()._proposalVotes[proposalId];
        return pv.forVotes > pv.againstVotes;
    }

    /// @dev Returns true if forVotes + abstainVotes >= quorum(snapshot).
    function _quorumReached(uint256 proposalId) internal view returns (bool) {
        ProposalVote storage pv = governorStorage()._proposalVotes[proposalId];
        uint256 snapshot = governorStorage()._proposals[proposalId].voteStart;
        return pv.forVotes + pv.abstainVotes >= quorum(snapshot);
    }

    /// @dev Reverts unless the caller is address(this) (i.e., the governor contract executing a proposal).
    function _onlyGovernance() internal view {
        address caller = ContextLib.msgSender();
        if (caller != address(this)) revert IGovernor.GovernorOnlyExecutor(caller);
    }

    /// @dev Encodes a single ProposalState as a 1-bit bitmask for error reporting.
    function _encodeStateBitmap(IGovernor.ProposalState proposalState) internal pure returns (bytes32) {
        // forge-lint: disable-next-line(incorrect-shift)
        return bytes32(1 << uint8(proposalState));
    }
}

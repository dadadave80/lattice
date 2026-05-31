// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ContextLib} from "@diamond/libraries/ContextLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IVotes} from "@lattice/interfaces/IVotes.sol";
import {Checkpoints} from "@lattice/utils/libraries/Checkpoints.sol";
import {ECDSA} from "@lattice/utils/libraries/ECDSA.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.Votes")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant VOTES_STORAGE_SLOT = 0x51efe794a829d7992f137137b94eec0d37b1c5be45aa8cf9431c145ea39c0600;

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant VOTES_ERC165_STORAGE_LOCATION = 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x3327c9eb is `type(IVotes).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x3327c9eb), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IVOTES_SLOT = 0x61ade9dd9a8b94d6fecab99fabf41cc4bf0b14d40172852668cf26dba0f52f49;

/// @dev EIP-712 typehash for delegation-by-signature.
bytes32 constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

/// @notice Storage struct for Votes module.
/// @custom:storage-location erc7201:lattice.storage.Votes
struct VotesStorage {
    mapping(address account => address) _delegatee;
    mapping(address delegatee => Checkpoints.Trace208) _delegateCheckpoints;
    Checkpoints.Trace208 _totalCheckpoints;
}

/// @title VotesLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/governance/utils/Votes.sol)
/// @notice Library implementing delegation + checkpoint tracking for ERC-5805 / ERC-6372 voting.
/// @dev Abstract building block: `_getVotingUnits` must be overridden by submodules (e.g. ERC20VotesLib).
library VotesLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function votesStorage() internal pure returns (VotesStorage storage $) {
        assembly {
            $.slot := VOTES_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the Votes module and registers the IVotes interface.
    /// @dev Must be called inside a pre/postInitializer block.
    function __Votes_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IVotes interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IVOTES_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               CLOCK (ERC-6372)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the current timepoint (block.timestamp cast to uint48).
    function clock() internal view returns (uint48) {
        return uint48(block.timestamp);
    }

    /// @notice Returns the ERC-6372 clock mode string.
    /// @dev Declared as view (not pure) to allow future overrides to add a consistency
    ///      check (e.g., assert clock() == expected_mode) without mutability narrowing.
    ///      Timestamp mode is an intentional deviation from OZ's default block-number mode.
    function CLOCK_MODE() internal view returns (string memory) {
        return "mode=timestamp";
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           VOTING POWER VIEWS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the current voting power of `account`.
    function getVotes(address account) internal view returns (uint256) {
        return Checkpoints.latest(votesStorage()._delegateCheckpoints[account]);
    }

    /// @notice Returns the voting power of `account` at a past `timepoint`.
    /// @dev Reverts with ERC5805FutureLookup if `timepoint >= clock()`.
    function getPastVotes(address account, uint256 timepoint) internal view returns (uint256) {
        uint48 currentClock = clock();
        if (timepoint >= currentClock) {
            revert IVotes.ERC5805FutureLookup(timepoint, currentClock);
        }
        return Checkpoints.upperLookupRecent(votesStorage()._delegateCheckpoints[account], uint48(timepoint));
    }

    /// @notice Returns the total token supply checkpointed at a past `timepoint`.
    /// @dev Reverts with ERC5805FutureLookup if `timepoint >= clock()`.
    function getPastTotalSupply(uint256 timepoint) internal view returns (uint256) {
        uint48 currentClock = clock();
        if (timepoint >= currentClock) {
            revert IVotes.ERC5805FutureLookup(timepoint, currentClock);
        }
        return Checkpoints.upperLookupRecent(votesStorage()._totalCheckpoints, uint48(timepoint));
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           DELEGATION VIEWS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the current delegate of `account`.
    function delegates(address account) internal view returns (address) {
        return votesStorage()._delegatee[account];
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         DELEGATION MUTATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Delegates votes from the caller to `delegatee`, using the provided voting units.
    /// @dev Submodules pass their token balance as `votingUnits`.
    function delegate(address delegatee, uint256 votingUnits) internal {
        _delegate(ContextLib.msgSender(), delegatee, votingUnits);
    }

    /// @notice Delegates votes via an EIP-712 signature.
    /// @param votingUnits The current voting weight of the signer (e.g. token balance).
    ///                    Callers that know the signer's units (e.g. ERC20VotesLib) must pass
    ///                    the correct balance; the base Votes facet passes 0.
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s,
        uint256 votingUnits
    ) internal {
        // Re-use the shared _recoverDelegationSigner to avoid logic duplication.
        address signer = _recoverDelegationSigner(delegatee, nonce, expiry, v, r, s);
        NoncesLib.useCheckedNonce(signer, nonce);
        _delegate(signer, delegatee, votingUnits);
    }

    /// @notice Recovers the signer of a delegation EIP-712 signature and validates expiry.
    ///         Does NOT consume the nonce or delegate. Useful for callers needing the
    ///         signer address before deciding on voting units (e.g. ERC20VotesLib).
    function _recoverDelegationSigner(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s)
        internal
        view
        returns (address signer)
    {
        if (block.timestamp > expiry) {
            revert IVotes.VotesExpiredSignature(expiry);
        }
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        bytes32 digest = EIP712Lib.hashTypedDataV4(structHash);
        signer = ECDSA.recover(digest, v, r, s);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            INTERNAL HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Changes the delegate of `account` to `delegatee` and moves `votingUnits` accordingly.
    function _delegate(address account, address delegatee, uint256 votingUnits) internal {
        VotesStorage storage $ = votesStorage();
        address oldDelegate = $._delegatee[account];
        $._delegatee[account] = delegatee;

        emit IVotes.DelegateChanged(account, oldDelegate, delegatee);
        _moveDelegateVotes(oldDelegate, delegatee, votingUnits);
    }

    /// @notice Moves `amount` voting units from delegate `from` to delegate `to`.
    /// @dev Pushes new checkpoints and emits DelegateVotesChanged for any non-zero, non-self moves.
    function _moveDelegateVotes(address from, address to, uint256 amount) internal {
        VotesStorage storage $ = votesStorage();
        if (from != to && amount > 0) {
            if (from != address(0)) {
                uint208 prev = Checkpoints.latest($._delegateCheckpoints[from]);
                uint208 newWeight = _subtract(prev, uint208(amount));
                Checkpoints.push($._delegateCheckpoints[from], clock(), newWeight);
                emit IVotes.DelegateVotesChanged(from, prev, newWeight);
            }
            if (to != address(0)) {
                uint208 prev = Checkpoints.latest($._delegateCheckpoints[to]);
                uint208 newWeight = _add(prev, uint208(amount));
                Checkpoints.push($._delegateCheckpoints[to], clock(), newWeight);
                emit IVotes.DelegateVotesChanged(to, prev, newWeight);
            }
        }
    }

    /// @notice Called by submodules on token transfers to update total supply and delegated vote checkpoints.
    /// @dev If `from == address(0)`, increases total supply checkpoint.
    ///      If `to == address(0)`, decreases total supply checkpoint.
    ///      Always moves delegated votes between the delegates of from and to.
    function _transferVotingUnits(address from, address to, uint256 amount) internal {
        VotesStorage storage $ = votesStorage();
        if (from == address(0)) {
            // Mint: increase total supply checkpoint
            uint208 prev = Checkpoints.latest($._totalCheckpoints);
            Checkpoints.push($._totalCheckpoints, clock(), _add(prev, uint208(amount)));
        }
        if (to == address(0)) {
            // Burn: decrease total supply checkpoint
            uint208 prev = Checkpoints.latest($._totalCheckpoints);
            Checkpoints.push($._totalCheckpoints, clock(), _subtract(prev, uint208(amount)));
        }
        _moveDelegateVotes(delegates(from), delegates(to), amount);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              SAFE MATH HELPERS
    //////////////////////////////////////////////////////////////////////////*//

    function _add(uint208 a, uint208 b) private pure returns (uint208) {
        return a + b;
    }

    function _subtract(uint208 a, uint208 b) private pure returns (uint208) {
        return a - b;
    }
}

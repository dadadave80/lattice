// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ICommitReveal} from "@lattice/interfaces/privacy/ICommitReveal.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.CommitReveal")) - 1)) & ~bytes32(uint256(0xff))`.
///      Verify with: `cast index-erc7201 "lattice.storage.CommitReveal"`.
bytes32 constant COMMIT_REVEAL_STORAGE_SLOT = 0xd3109411a8705fe8e8868eda2607aae4e6b37bb0d383a8a9e1c55c78e6853e00;

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant COMMIT_REVEAL_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0xe371e8b7 is `type(ICommitReveal).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xe371e8b7), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ICOMMITREVEAL_SLOT = 0xdc9ba0d500a620df2dabeedf359873cda3ecd1229c8cb91b5b30ae80ec382462;

/// @notice ERC-7201 namespaced storage for the CommitReveal module.
/// @dev APPEND-ONLY: new fields may only be added at the end to preserve the upgrade-safe layout.
/// @custom:storage-location erc7201:lattice.storage.CommitReveal
struct CommitRevealStorage {
    /// @dev commitment hash => its record.
    mapping(bytes32 commitment => ICommitReveal.Commitment record) _commitments;
}

/// @title CommitRevealLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Library implementing a generic commit–reveal primitive (sealed bids / auctions / MEV
///         mitigation). The commitment binds the committer's address, so only the bound committer can
///         reveal it — front-running the commit transaction cannot hijack the reveal.
/// @dev Three-layer pattern: this library holds the logic + namespaced storage; the stateless
///      {CommitReveal} facet forwards to it. Permissionless — anyone may commit and reveal their own.
library CommitRevealLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function commitRevealStorage() internal pure returns (CommitRevealStorage storage $) {
        assembly {
            $.slot := COMMIT_REVEAL_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the CommitReveal module.
    /// @dev Must be called inside a pre/postInitializer block. Registers ICommitReveal for ERC-165.
    function __CommitReveal_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the ICommitReveal interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ICOMMITREVEAL_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             COMMIT / REVEAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Records a commitment hash (`computeCommitment(msg.sender, data, salt)`).
    /// @param commitment The commitment hash to record.
    function commit(bytes32 commitment) internal {
        if (commitment == bytes32(0)) revert ICommitReveal.CommitRevealZeroCommitment();
        CommitRevealStorage storage $ = commitRevealStorage();
        if ($._commitments[commitment].committedAt != 0) {
            revert ICommitReveal.CommitRevealAlreadyCommitted(commitment);
        }
        uint64 ts = uint64(block.timestamp);
        $._commitments[commitment] = ICommitReveal.Commitment({committer: msg.sender, committedAt: ts, revealed: false});
        emit ICommitReveal.Committed(commitment, msg.sender, ts);
    }

    /// @notice Reveals `data` + `salt` for a commitment previously made by `msg.sender`.
    /// @dev Only the address bound into the commitment can produce a matching hash, so reveal is
    ///      front-run-proof regardless of who submitted the {commit} transaction.
    /// @param data The committed data.
    /// @param salt The blinding salt.
    function reveal(bytes calldata data, bytes32 salt) internal {
        bytes32 commitment = keccak256(abi.encode(msg.sender, data, salt));
        ICommitReveal.Commitment storage c = commitRevealStorage()._commitments[commitment];
        if (c.committedAt == 0) revert ICommitReveal.CommitRevealNotCommitted(commitment);
        if (c.revealed) revert ICommitReveal.CommitRevealAlreadyRevealed(commitment);
        c.revealed = true;
        emit ICommitReveal.Revealed(commitment, msg.sender, data, salt);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the record for `commitment`.
    function commitmentInfo(bytes32 commitment) internal view returns (ICommitReveal.Commitment memory) {
        return commitRevealStorage()._commitments[commitment];
    }

    /// @notice Returns whether `commitment` has been revealed.
    function isRevealed(bytes32 commitment) internal view returns (bool) {
        return commitRevealStorage()._commitments[commitment].revealed;
    }

    /// @notice Computes `keccak256(abi.encode(committer, data, salt))`.
    function computeCommitment(address committer, bytes calldata data, bytes32 salt) internal pure returns (bytes32) {
        return keccak256(abi.encode(committer, data, salt));
    }
}

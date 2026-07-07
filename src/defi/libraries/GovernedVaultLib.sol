// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IGovernedVault} from "@lattice/interfaces/defi/IGovernedVault.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.GovernedVault")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant GOVERNED_VAULT_STORAGE_SLOT = 0xce91473269200f209353d1f9f84b7900d57f30b14d017212fb8c61b25320cc00;

/// @dev 0xd5cae628 is `type(IGovernedVault).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xd5cae628), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IGOVERNEDVAULT_SLOT = 0xce6fd43da1904d8f433b8bce181e4722445e0a5f694993acc9f150691da893d1;

/// @notice ERC-7201 namespaced storage unique to the self-governed vault: the governor ballot-nonce namespace,
///         kept SEPARATE from the ERC-20 delegation nonce (which lives in {NoncesLib}).
/// @custom:storage-location erc7201:lattice.storage.GovernedVault
struct GovernedVaultStorage {
    /// @notice voter => next unused governor-ballot nonce (consumed by `castVoteBySig`). APPEND-ONLY.
    mapping(address voter => uint256 nonce) _ballotNonces;
}

/// @title GovernedVaultLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice The one piece of genuinely NEW logic the self-governed ERC-4626 vault needs on top of the audited
///         modules it composes ({ERC20VotesLib}, {ERC4626Lib}/{VaultCoreLib}, {VotesLib}, {GovernorLib},
///         {TimelockControllerLib}): a DEDICATED nonce namespace for the governor's `castVoteBySig`.
/// @dev WHY THIS EXISTS: {GovernorLib.castVoteBySig} and {ERC20VotesLib}'s `delegateBySig` both draw from
///      {NoncesLib} — fine when the token and the governor are separate contracts (the canonical OZ topology),
///      but on ONE diamond they would share a single counter, so signing a delegation would consume the nonce a
///      pending vote signature depends on (and vice versa), silently invalidating it. {GovernedVault} keeps the
///      token's `delegateBySig` on {NoncesLib} and routes the governor's ballot nonce through this namespace, so
///      the two are independent — the exact isolation the two-contract deployment enjoys for free. Everything
///      else (share accounting, checkpoints, proposal lifecycle, timelock) reuses the existing libraries
///      unmodified; only the nonce source and the vault-mint→checkpoint seam (in the facet) are new.
library GovernedVaultLib {
    function governedVaultStorage() internal pure returns (GovernedVaultStorage storage $) {
        assembly {
            $.slot := GOVERNED_VAULT_STORAGE_SLOT
        }
    }

    /// @notice Registers the {IGovernedVault} ERC-165 id. Called inside the diamond initializing window.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IGOVERNEDVAULT_SLOT, true)
        }
    }

    /// @notice Returns the current governor-ballot nonce for `voter` and increments it (consume-once).
    /// @dev Mirrors {NoncesLib.useNonce}'s return-then-increment semantics, in the vault's own namespace.
    function useBallotNonce(address voter) internal returns (uint256 current) {
        GovernedVaultStorage storage $ = governedVaultStorage();
        current = $._ballotNonces[voter];
        $._ballotNonces[voter] = current + 1;
    }

    /// @notice The next unused governor-ballot nonce for `voter`.
    function ballotNonce(address voter) internal view returns (uint256) {
        return governedVaultStorage()._ballotNonces[voter];
    }
}

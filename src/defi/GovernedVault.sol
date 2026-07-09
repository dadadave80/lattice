// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GovernedVaultLib} from "@lattice/defi/libraries/GovernedVaultLib.sol";
import {VaultCoreLib} from "@lattice/defi/libraries/VaultCoreLib.sol";
import {BALLOT_TYPEHASH, GovernorLib} from "@lattice/governance/libraries/GovernorLib.sol";
import {VotesLib} from "@lattice/governance/libraries/VotesLib.sol";
import {IGovernedVault} from "@lattice/interfaces/defi/IGovernedVault.sol";
import {IGovernor} from "@lattice/interfaces/governance/IGovernor.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {ERC20VotesLib} from "@lattice/tokens/ERC20/libraries/ERC20VotesLib.sol";
import {ERC4626Lib} from "@lattice/tokens/ERC4626/libraries/ERC4626Lib.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {SignatureChecker} from "@lattice/utils/libraries/SignatureChecker.sol";

/// @title GovernedVault
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice The RECONCILIATION facet of the self-governed ERC-4626 vault. The vault is ONE diamond that composes
///         the strategy-aware vault ({VaultCore} → {ERC4626} → {ERC20}), vote-weighted shares ({ERC20Votes}),
///         an on-chain {Governor}, and a {TimelockController} — all cut as their normal facets — but a handful
///         of selectors either CLASH across those facets or must be MODIFIED for the single-diamond topology.
///         This small facet owns exactly those selectors; {DeployGovernedVault} cuts it for them and excludes
///         them from the base facets.
/// @dev Deliberately a THIN library-delegating facet (NOT inheriting the four heavy facets — that would exceed
///      EIP-170 by ~2x). It resolves:
///      - SELECTOR CLASHES: `name` (ERC-20 vs Governor → the share name), `clock`/`CLOCK_MODE` (Votes vs
///        Governor → the Votes clock), `transfer`/`transferFrom` (base ERC-20 vs the checkpoint-updating
///        {ERC20Votes} variants → the checkpoint variants).
///      - VAULT MINT/BURN → VOTE CHECKPOINT SEAM: the audited {ERC4626Lib} mutators move shares via {ERC20Lib}'s
///        plain `_update` (no checkpoint); each is wrapped here to post the matching {VotesLib} voting-unit
///        delta, so governance weight tracks deposits/withdrawals. (`transfer`/`transferFrom` already checkpoint
///        via {ERC20Votes}.)
///      - BALLOT-NONCE NAMESPACE: `castVoteBySig` draws from {GovernedVaultLib}'s dedicated nonce, leaving the
///        ERC-20 `delegateBySig` nonce on {NoncesLib} — see {GovernedVaultLib} for why a shared counter would
///        silently invalidate signatures.
contract GovernedVault is IGovernedVault {
    //*//////////////////////////////////////////////////////////////////////////
    //                            CLASH RESOLUTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @inheritdoc IGovernedVault
    function ballotNonce(address voter) external view returns (uint256) {
        return GovernedVaultLib.ballotNonce(voter);
    }

    /// @notice The single share-token name (resolves the ERC-20 vs Governor `name()` clash).
    function name() external view returns (string memory) {
        return ERC20Lib.name();
    }

    /// @notice The ERC-6372 clock (the Votes/shares clock serves both the token and the governor).
    function clock() external view returns (uint48) {
        return VotesLib.clock();
    }

    /// @notice The ERC-6372 clock mode.
    function CLOCK_MODE() external view returns (string memory) {
        return VotesLib.CLOCK_MODE();
    }

    /// @notice Checkpoint-updating share transfer (resolves the base ERC-20 vs {ERC20Votes} clash).
    function transfer(address to, uint256 value) external returns (bool) {
        return ERC20VotesLib.transfer(to, value);
    }

    /// @notice Checkpoint-updating share transferFrom.
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        return ERC20VotesLib.transferFrom(from, to, value);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                    VAULT MUTATORS — VOTE-CHECKPOINT SEAM
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Deposit assets for shares, then post the mint's voting-unit delta (strategy-rebalance guarded).
    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        VaultCoreLib.requireManagerNotRebalancing();
        shares = ERC4626Lib.deposit(assets, receiver);
        VotesLib._transferVotingUnits(address(0), receiver, shares);
    }

    /// @notice Mint exact shares for assets, then post the voting-unit delta.
    function mint(uint256 shares, address receiver) external returns (uint256 assets) {
        VaultCoreLib.requireManagerNotRebalancing();
        assets = ERC4626Lib.mint(shares, receiver);
        VotesLib._transferVotingUnits(address(0), receiver, shares);
    }

    /// @notice Withdraw exact assets by burning shares, then post the burn's voting-unit delta.
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares) {
        VaultCoreLib.requireManagerNotRebalancing();
        shares = ERC4626Lib.withdraw(assets, receiver, owner);
        VotesLib._transferVotingUnits(owner, address(0), shares);
    }

    /// @notice Redeem exact shares for assets, then post the burn's voting-unit delta.
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        VaultCoreLib.requireManagerNotRebalancing();
        assets = ERC4626Lib.redeem(shares, receiver, owner);
        VotesLib._transferVotingUnits(owner, address(0), shares);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                      GOVERNOR — NAMESPACED BALLOT NONCE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Cast a vote by EIP-712 signature, consuming the vault's DEDICATED ballot nonce (not the shared
    ///         {NoncesLib} counter the ERC-20 `delegateBySig` owns). Only the nonce source differs from
    ///         {GovernorLib.castVoteBySig}.
    function castVoteBySig(uint256 proposalId, uint8 support, address voter, bytes memory signature)
        external
        returns (uint256)
    {
        uint256 nonce = GovernedVaultLib.useBallotNonce(voter);
        bytes32 structHash = keccak256(abi.encode(BALLOT_TYPEHASH, proposalId, support, voter, nonce));
        bytes32 hash = EIP712Lib.hashTypedDataV4(structHash);
        if (!SignatureChecker.isValidSignatureNow(voter, hash, signature)) {
            revert IGovernor.GovernorInvalidSignature(voter);
        }
        return GovernorLib._castVote(proposalId, voter, support, "", "");
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect GovernedVault methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `CLOCK_MODE()` 0x4bf5d7e9
    ///      `ballotNonce(address)` 0xd5cae628
    ///      `castVoteBySig(uint256,uint8,address,bytes)` 0x8ff262e3
    ///      `clock()` 0x91ddadf4
    ///      `deposit(uint256,address)` 0x6e553f65
    ///      `mint(uint256,address)` 0x94bf804d
    ///      `name()` 0x06fdde03
    ///      `redeem(uint256,address,address)` 0xba087652
    ///      `transfer(address,uint256)` 0xa9059cbb
    ///      `transferFrom(address,address,uint256)` 0x23b872dd
    ///      `withdraw(uint256,address,address)` 0xb460af94
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"4bf5d7e9d5cae6288ff262e391ddadf46e553f6594bf804d06fdde03ba087652a9059cbb23b872ddb460af94";
    }
}

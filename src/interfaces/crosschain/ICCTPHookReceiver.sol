// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ICCTPHookReceiver
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Circle CCTP v2 (https://github.com/circlefin/evm-cctp-contracts)
/// @notice The typed callback a Lattice CCTP hook target MUST implement to receive an inbound CCTP v2 hook. The
///         {CCTPHookExecutor} is the ONLY caller: it invokes this fixed selector so attacker-chosen `hookData`
///         can never pick which function runs on the target. Every context argument is read from the ATTESTED
///         CCTP message (never from `hookData`), so the target can trust `sourceDomain` / `sender` /
///         `mintRecipient` / `amount` as Circle-attested facts; only `payload` is attacker-controlled bytes.
/// @dev SECURITY: a valid Iris attestation authenticates only "someone burned >= 1 uUSDC with these bytes toward
///      this diamond" — it says NOTHING about intent. Treat `payload` as fully adversarial and NEVER grant it
///      authority: the executor calls with no funds and no roles, so a hostile hook gains nothing beyond a plain
///      EOA's reach. Implementations MUST NOT assume the mint went to them, MUST NOT trust `payload`, and any
///      revert here is swallowed by the executor (the mint stands and the CCTP nonce is consumed regardless).
///      Running out of gas in THIS frame is the exception: it reverts the whole relay (mint unwound, nonce live),
///      so a hook that always exhausts its gas can only be bypassed by the `mintRecipient` relaying hook-less
///      itself. The executor sees only this frame, though: when a sub-call this hook makes runs out of gas, the
///      hook keeps its 1/64 reserve and its revert is an ORDINARY failure (swallowed, nonce consumed), so a
///      relayer could pick a gas limit that starves the sub-call and skips the hook for good.
///      Implementations that do gas-hungry work in sub-calls (a vault deposit, a swap) MUST therefore re-raise
///      starvation by consuming ALL remaining gas (`assembly { invalid() }`), which trips the executor's check:
///      either at entry when `gasleft()` is below what the hook needs, or after a low-level sub-call that failed
///      with at most 1/63 of its pre-call gas left. A plain `require`/`revert` does NOT re-raise it — it hands
///      the unspent gas back and reads as an ordinary failure.
interface ICCTPHookReceiver {
    /// @notice Invoked by the {CCTPHookExecutor} after the attested USDC mint, with Circle-attested context.
    /// @param sourceDomain  The CCTP domain the burn originated on (from the attested message header).
    /// @param sender        The burner on the source domain, as a right-aligned `bytes32` (attested).
    /// @param mintRecipient The `bytes32` recipient the USDC was minted to on this chain (attested).
    /// @param amount        The USDC amount actually minted to `mintRecipient` (attested burn amount minus
    ///                      attested feeExecuted).
    /// @param payload       ATTACKER-CONTROLLED hook payload bytes (the Lattice envelope's tail). Untrusted.
    function onCCTPHook(
        uint32 sourceDomain,
        bytes32 sender,
        bytes32 mintRecipient,
        uint256 amount,
        bytes calldata payload
    ) external;
}

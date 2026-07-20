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

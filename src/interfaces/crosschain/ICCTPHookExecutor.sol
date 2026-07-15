// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ICCTPHookExecutor
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Circle CCTP v2 (https://github.com/circlefin/evm-cctp-contracts)
/// @notice The role-less, fund-less indirection the CCTP adapter routes every inbound hook through. Its sole
///         reason to exist is to be the ONLY caller of an attacker-named hook target, so bytes the attacker put
///         in a CCTP burn's `hookData` gain zero authority beyond a plain EOA's: it holds no funds, has no
///         roles, and delegatecalls nothing. Each diamond deploys exactly one at init and stores its address
///         immutably (no swap setter — a swappable executor would be a forgeable trust anchor).
/// @dev CCTP does NOT execute hooks; the destination recipient does. This executor is that recipient's indirection
///      and calls the target with a FIXED selector (`ICCTPHookReceiver.onCCTPHook`), dropping all returndata
///      (return-bomb safe) and never bubbling the target's revert — it reports a plain `bool success`.
interface ICCTPHookExecutor {
    /// @notice `executeHook` was called by an address other than the immutable {relay} diamond.
    error CCTPHookExecutorUnauthorized();

    /// @notice The diamond that deployed this executor — the ONLY address permitted to call {executeHook}.
    function relay() external view returns (address);

    /// @notice Calls `target.onCCTPHook(...)` with Circle-attested context, swallowing any revert/returndata.
    /// @dev MUST revert {CCTPHookExecutorUnauthorized} unless `msg.sender == relay`. The call uses a FIXED
    ///      selector so `payload` can never choose the invoked function, forwards no value, and returns
    ///      `success = false` (never reverts) if the target reverts or return-bombs.
    /// @param sourceDomain  Attested CCTP source domain of the burn.
    /// @param sender        Attested `bytes32` burner on the source domain.
    /// @param mintRecipient Attested `bytes32` mint recipient on this chain.
    /// @param amount        Attested burned/minted USDC amount.
    /// @param nonce         Attested CCTP nonce (passed through for the relay's `HookExecuted` bookkeeping).
    /// @param target        The hook target decoded from the Lattice `hookData` envelope (attacker-chosen).
    /// @param payload       The attacker-controlled hook payload tail.
    /// @return success      Whether `target.onCCTPHook(...)` returned without reverting.
    function executeHook(
        uint32 sourceDomain,
        bytes32 sender,
        bytes32 mintRecipient,
        uint256 amount,
        bytes32 nonce,
        address target,
        bytes calldata payload
    ) external returns (bool success);
}

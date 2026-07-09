// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IETHRegistrarController
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Vendored minimal subset of ENS's `ETHRegistrarController` / `IETHRegistrarController` (https://github.com/ensdomains/ens-contracts). Upstream is MIT.
/// @notice Minimal vendored interface for the LIVE ENS .eth registrar controller generation (the
///         Namechain-era "premigration" controller, live-authorized on the Sepolia BaseRegistrar at
///         `0xdf60C561Ca35AD3C89D24BbA854654b1c3477078` — verified from its on-chain verified ABI and a
///         successful mainnet-flow registration tx). This generation registers in ONE payable call: there is
///         NO commit/reveal (`makeCommitment`/`commit`/`minCommitmentAge` were removed) and NO `rentPrice`
///         view — the controller prices internally and refunds any excess `msg.value` (it reverts
///         `RefundFailed` when the refund cannot be delivered).
/// @dev The `Registration` struct MUST match the deployed ABI byte-for-byte (tuple
///      `(string,address,uint256,bytes32,address,bytes[],uint8,bytes32)`, `register` selector `0xef9c8805`).
///      `secret` remains in the struct for ABI compatibility but no commitment gates it. `reverseRecord` is a
///      BITMASK: bit 1 sets the caller's ethereum reverse record, bit 2 the default reverse record (upstream
///      `REVERSE_RECORD_*_BIT`); both act on `msg.sender`, NOT `owner`. Supplying `data` (or a reverse bit)
///      requires a non-zero `resolver` (`ResolverRequiredWhenDataSupplied` / `ResolverRequiredForReverseRecord`).
///      The controller address is chain-specific and supplied by the caller; it is never hardcoded here.
interface IETHRegistrarController {
    /// @notice A .eth second-level registration (upstream `IETHRegistrarController.Registration`).
    struct Registration {
        string label; // the second-level label ("myvault" for myvault.eth)
        address owner; // the registrant receiving name ownership
        uint256 duration; // registration duration in seconds (MIN_REGISTRATION_DURATION = 28 days)
        bytes32 secret; // legacy commit/reveal blinding secret — ABI-retained, unused by this generation
        address resolver; // resolver set for the name (required when data/reverseRecord used)
        bytes[] data; // resolver multicall ran against the name's node (e.g. setAddr)
        uint8 reverseRecord; // reverse-record BITMASK applied to msg.sender (1 = ethereum, 2 = default)
        bytes32 referrer; // referrer tag (zero for none)
    }

    /// @notice Registers `registration.label`.eth in one call, paying rent from `msg.value` (priced
    ///         internally by the controller; any excess is refunded to the caller).
    /// @param registration The registration to execute; reverts `NameNotAvailable` when taken and
    ///        `DurationTooShort` below the 28-day minimum.
    function register(Registration calldata registration) external payable;

    /// @notice The minimum registration duration in seconds (28 days upstream).
    function MIN_REGISTRATION_DURATION() external view returns (uint256);
}

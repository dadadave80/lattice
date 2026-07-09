// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IENSReverseClaimer
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ENS (https://github.com/ensdomains/ens-contracts)
/// @author Conforms to ENS reverse resolution (https://docs.ens.domains/learn/protocol#reverse-resolution)
/// @notice External interface for the ENS reverse-claim facet: lets a diamond set and advertise its own
///         primary ENS name, so resolving the diamond address returns e.g. `treasury.myproto.eth`.
/// @dev Wraps the ENS `ReverseRegistrar.setName` self-claim flow behind an `ENS_MANAGER_ROLE`-gated
///      setter. The usual `ReverseClaimer` constructor base cannot serve a Diamond proxy (which
///      initializes via `InitializableLib`, not a constructor), so the claim runs through this facet
///      instead. The reverse registrar address is configurable per chain — the self-claim `setName`
///      used here is supported by both the mainnet `ReverseRegistrar` and the ENSIP-11
///      `L2ReverseRegistrar` (the L2 coin-type / signature-based variants for setting *other*
///      addresses' names are out of scope for v1).
interface IENSReverseClaimer {
    /// @dev Thrown when a zero address is supplied as the reverse registrar.
    error ENSReverseClaimerZeroRegistrar();

    /// @dev Emitted when the diamond sets its primary (reverse) ENS name. The diamond is the event
    ///      emitter, so the reverse node (a deterministic function of the diamond address) is omitted.
    /// @param name The ENS name set for the diamond.
    event EnsNameSet(string name);

    /// @dev Emitted when the configured reverse registrar is set or rotated.
    /// @param reverseRegistrar The reverse registrar address now in use.
    event ReverseRegistrarSet(address indexed reverseRegistrar);

    /// @notice Sets the diamond's primary ENS name via the configured reverse registrar.
    /// @dev Gated on `ENS_MANAGER_ROLE`. Calls `IReverseRegistrar.setName(name)` with the diamond as
    ///      `msg.sender`, so the diamond's `addr.reverse` record resolves to `name`. Passing an empty
    ///      string clears the reverse record, matching canonical `ReverseRegistrar` semantics.
    /// @param name The ENS name to set as the diamond's primary name.
    function setEnsName(string calldata name) external;

    /// @notice Sets or rotates the reverse registrar (e.g. per-chain configuration).
    /// @dev Gated on `ENS_MANAGER_ROLE`. Reverts {ENSReverseClaimerZeroRegistrar} for a zero address.
    /// @param reverseRegistrar The reverse registrar to use.
    function setReverseRegistrar(address reverseRegistrar) external;

    /// @notice Returns the diamond's last ENS name set through this facet.
    /// @dev Convenience cache only: it reflects the last name set THROUGH THIS FACET and may not equal
    ///      the live ENS reverse record, which can be changed directly at the resolver or made stale by
    ///      registrar rotation ({setReverseRegistrar}) or a registrar resolver change. Off-chain
    ///      consumers should resolve the live ENS reverse record rather than trust this value.
    /// @return The cached ENS name (empty if never set).
    function ensName() external view returns (string memory);

    /// @notice Returns the currently configured reverse registrar.
    /// @return The reverse registrar address.
    function reverseRegistrar() external view returns (address);
}

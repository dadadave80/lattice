// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ISafeHarborRegistry
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Vendored minimal subset of SEAL Safe Harbor's `SafeHarborRegistry` (https://github.com/security-alliance/safe-harbor).
/// @notice Minimal vendored interface for the SEAL `SafeHarborRegistry` (registry v3.0.0), used by
///         {SafeHarborAdopter}. Adoption is keyed by `msg.sender` — the adopter is whoever calls
///         `adoptSafeHarbor`, so a diamond must make the call itself to be recorded as the adopter.
/// @dev The deployed registry address is chain-specific and supplied by the deployer; never hardcoded.
interface ISafeHarborRegistry {
    /// @dev Emitted when an adopter records an agreement.
    /// @param adopter The adopting entity (`msg.sender`).
    /// @param agreementAddress The adopted agreement contract.
    event SafeHarborAdoption(address indexed adopter, address agreementAddress);

    /// @dev Thrown by {getAgreement} when the queried adopter has no agreement.
    error SafeHarborRegistry__NoAgreement();

    /// @notice Records `agreementAddress` as the agreement adopted by `msg.sender`.
    /// @param agreementAddress The agreement contract to adopt.
    function adoptSafeHarbor(address agreementAddress) external;

    /// @notice Returns the agreement adopted by `adopter` (reverts {SafeHarborRegistry__NoAgreement} if none).
    /// @param adopter The adopter to query.
    /// @return The adopted agreement address.
    function getAgreement(address adopter) external view returns (address);
}

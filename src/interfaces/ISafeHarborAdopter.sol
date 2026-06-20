// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {AgreementDetails} from "@lattice/interfaces/external/IAgreementFactory.sol";

/// @title ISafeHarborAdopter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Integrates the SEAL Whitehat Safe Harbor (https://github.com/security-alliance/safe-harbor)
/// @notice External interface for the Safe Harbor adopter facet: lets a diamond adopt the SEAL Whitehat
///         Safe Harbor agreement on-chain (the legal half of incident response, complementing the
///         EmergencyStop technical half).
/// @dev Adoption in the SEAL `SafeHarborRegistry` is keyed by `msg.sender`, so the diamond adopts itself
///      — the same self-call pattern Lattice uses for `diamondCut`. Because the agreement's
///      asset-recovery addresses and bounty terms are security-critical, all state-changing functions
///      are gated on `SAFE_HARBOR_ADMIN_ROLE`. The registry + factory addresses are configurable per
///      chain (never hardcoded).
interface ISafeHarborAdopter {
    /// @dev Thrown when a zero address is supplied as the Safe Harbor registry.
    error SafeHarborAdopterZeroRegistry();

    /// @dev Thrown when {createAndAdopt} is called with no agreement factory configured, or a zero
    ///      factory is supplied to {setAgreementFactory}.
    error SafeHarborAdopterZeroFactory();

    /// @dev Thrown when a zero agreement address is supplied to {adoptSafeHarbor}.
    error SafeHarborAdopterZeroAgreement();

    /// @dev Emitted when the diamond adopts (or re-adopts) a Safe Harbor agreement.
    /// @param agreement The adopted agreement contract.
    event SafeHarborAdopted(address indexed agreement);

    /// @dev Emitted when the configured Safe Harbor registry is set or rotated.
    event SafeHarborRegistrySet(address indexed registry);

    /// @dev Emitted when the configured agreement factory is set or rotated.
    event AgreementFactorySet(address indexed factory);

    /// @notice Adopts a pre-deployed `agreement` for this diamond via the configured registry.
    /// @dev Gated on `SAFE_HARBOR_ADMIN_ROLE`. The diamond calls the registry itself, so it is recorded
    ///      as the adopter. Re-adopting overwrites the prior agreement (the update path).
    /// @param agreement The agreement contract to adopt.
    function adoptSafeHarbor(address agreement) external;

    /// @notice Creates an agreement (recovery addresses + bounty terms) via the configured factory and
    ///         adopts it for this diamond, in one governed call.
    /// @dev Gated on `SAFE_HARBOR_ADMIN_ROLE`. This is where the security-critical recovery addresses
    ///      are set, so the whole action is role-pinned.
    /// @param details The agreement details (per-chain recovery address, accounts, bounty terms).
    /// @param chainValidator The SEAL ChainValidator contract for this chain.
    /// @param owner The owner of the new agreement (may later update its terms).
    /// @param salt A caller-provided salt for CREATE2 uniqueness.
    /// @return agreement The newly created and adopted agreement address.
    function createAndAdopt(AgreementDetails calldata details, address chainValidator, address owner, bytes32 salt)
        external
        returns (address agreement);

    /// @notice Sets or rotates the Safe Harbor registry (per-chain configuration).
    /// @dev Gated on `SAFE_HARBOR_ADMIN_ROLE`. Reverts {SafeHarborAdopterZeroRegistry} for a zero address.
    /// @param registry The Safe Harbor registry to use.
    function setSafeHarborRegistry(address registry) external;

    /// @notice Sets or rotates the agreement factory (per-chain configuration).
    /// @dev Gated on `SAFE_HARBOR_ADMIN_ROLE`. Reverts {SafeHarborAdopterZeroFactory} for a zero address.
    /// @param factory The agreement factory to use.
    function setAgreementFactory(address factory) external;

    /// @notice Returns the configured Safe Harbor registry.
    function safeHarborRegistry() external view returns (address);

    /// @notice Returns the configured agreement factory.
    function agreementFactory() external view returns (address);

    /// @notice Returns the agreement currently adopted by this diamond (zero if none).
    function safeHarborAgreement() external view returns (address);
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

// Vendored from security-alliance/safe-harbor registry v3.0.0 (src/types/AgreementTypes.sol).
// VERIFY the AgreementDetails layout + the deployed AgreementFactory / chain-validator addresses
// against the live SEAL contracts for your target chain before mainnet use.

/// @notice Inclusion of child contracts in an agreement.
enum ChildContractScope {
    None,
    ExistingOnly,
    All,
    FutureOnly
}

/// @notice Whitehat identity verification requirements.
enum IdentityRequirements {
    Anonymous,
    Pseudonymous,
    Named
}

/// @notice Contact details for the agreement (required for pre-notifying).
struct Contact {
    string name;
    string contact;
}

/// @notice An account in scope for the agreement.
struct Account {
    string accountAddress;
    ChildContractScope childContractScope;
}

/// @notice The scope and recovery address for one chain (CAIP-2 / CAIP-10 string identifiers).
struct Chain {
    string assetRecoveryAddress;
    Account[] accounts;
    string caip2ChainId;
}

/// @notice The bounty terms of the agreement.
struct BountyTerms {
    uint256 bountyPercentage;
    uint256 bountyCapUSD;
    bool retainable;
    IdentityRequirements identity;
    string diligenceRequirements;
    uint256 aggregateBountyCapUSD;
}

/// @notice The full Safe Harbor agreement details.
struct AgreementDetails {
    string protocolName;
    Contact[] contactDetails;
    Chain[] chains;
    BountyTerms bountyTerms;
    string agreementURI;
}

/// @title IAgreementFactory
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Minimal vendored interface for the SEAL Safe Harbor `AgreementFactory` (registry v3.0.0),
///         used by {SafeHarborAdopter} to deploy an `Agreement` holding the protocol's terms.
/// @dev The factory CREATE2-deploys an `Agreement` (Ownable, mutable) owned by `owner`. The deployed
///      factory + chain-validator addresses are chain-specific and supplied by the deployer.
interface IAgreementFactory {
    /// @notice Deploys an `Agreement` holding `details`, owned by `owner`.
    /// @param details The agreement details (recovery addresses, accounts, bounty terms).
    /// @param chainValidator The SEAL ChainValidator contract for this chain.
    /// @param owner The owner of the new agreement (may update its terms).
    /// @param salt A caller-provided salt for CREATE2 uniqueness.
    /// @return agreementAddress The address of the newly deployed agreement.
    function create(AgreementDetails memory details, address chainValidator, address owner, bytes32 salt)
        external
        returns (address agreementAddress);
}

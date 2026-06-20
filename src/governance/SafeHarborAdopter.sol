// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SafeHarborAdopterLib} from "@lattice/governance/libraries/SafeHarborAdopterLib.sol";
import {ISafeHarborAdopter} from "@lattice/interfaces/ISafeHarborAdopter.sol";
import {AgreementDetails} from "@lattice/interfaces/external/IAgreementFactory.sol";

/// @title SafeHarborAdopter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Integrates the SEAL Whitehat Safe Harbor (https://github.com/security-alliance/safe-harbor)
/// @notice Stateless Diamond facet letting a diamond adopt the SEAL Whitehat Safe Harbor agreement
///         on-chain — the legal half of incident response, complementing {EmergencyStop}.
/// @dev All logic lives in {SafeHarborAdopterLib}. The diamond calls the SEAL registry itself
///      (`msg.sender == diamond`). All state-changing functions are gated on `SAFE_HARBOR_ADMIN_ROLE`,
///      managed through the diamond's AccessControl module; the registry + factory are supplied at init
///      and rotated per chain. VERIFY the deployed SEAL addresses + AgreementDetails ABI for your chain
///      before mainnet use.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Lattice original
contract SafeHarborAdopter is ISafeHarborAdopter {
    /// @inheritdoc ISafeHarborAdopter
    function adoptSafeHarbor(address agreement) external virtual {
        SafeHarborAdopterLib.adoptSafeHarbor(agreement);
    }

    /// @inheritdoc ISafeHarborAdopter
    function createAndAdopt(AgreementDetails calldata details, address chainValidator, address owner, bytes32 salt)
        external
        virtual
        returns (address)
    {
        return SafeHarborAdopterLib.createAndAdopt(details, chainValidator, owner, salt);
    }

    /// @inheritdoc ISafeHarborAdopter
    function setSafeHarborRegistry(address registry) external virtual {
        SafeHarborAdopterLib.setSafeHarborRegistry(registry);
    }

    /// @inheritdoc ISafeHarborAdopter
    function setAgreementFactory(address factory) external virtual {
        SafeHarborAdopterLib.setAgreementFactory(factory);
    }

    /// @inheritdoc ISafeHarborAdopter
    function safeHarborRegistry() external view virtual returns (address) {
        return SafeHarborAdopterLib.safeHarborRegistry();
    }

    /// @inheritdoc ISafeHarborAdopter
    function agreementFactory() external view virtual returns (address) {
        return SafeHarborAdopterLib.agreementFactory();
    }

    /// @inheritdoc ISafeHarborAdopter
    function safeHarborAgreement() external view virtual returns (address) {
        return SafeHarborAdopterLib.safeHarborAgreement();
    }
}

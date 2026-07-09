// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SafeHarborAdopterLib} from "@lattice/governance/libraries/SafeHarborAdopterLib.sol";
import {AgreementDetails} from "@lattice/interfaces/external/IAgreementFactory.sol";
import {ISafeHarborAdopter} from "@lattice/interfaces/governance/ISafeHarborAdopter.sol";

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

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect SafeHarborAdopter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `adoptSafeHarbor(address)` 0x344fbd20
    ///      `agreementFactory()` 0x4495ae68
    ///      `createAndAdopt((string,(string,string)[],(string,(string,uint8)[],string)[],(uint256,uint256,bool,uint8,string,uint256),string),address,address,bytes32)` 0x99ce8f17
    ///      `safeHarborAgreement()` 0x9bcc73cb
    ///      `safeHarborRegistry()` 0x23dbb9f6
    ///      `setAgreementFactory(address)` 0xb4e25f6f
    ///      `setSafeHarborRegistry(address)` 0xcfdf871f
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"344fbd204495ae6899ce8f179bcc73cb23dbb9f6b4e25f6fcfdf871f";
    }
}

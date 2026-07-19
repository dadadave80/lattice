// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {AgreementDetails, IAgreementFactory} from "@lattice/interfaces/external/seal/IAgreementFactory.sol";
import {ISafeHarborRegistry} from "@lattice/interfaces/external/seal/ISafeHarborRegistry.sol";
import {ISafeHarborAdopter} from "@lattice/interfaces/governance/ISafeHarborAdopter.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.SafeHarborAdopter")) - 1)) & ~bytes32(uint256(0xff))`.
///      Verify with: `cast index-erc7201 "lattice.storage.SafeHarborAdopter"`.
bytes32 constant SAFE_HARBOR_ADOPTER_STORAGE_SLOT = 0xaaf15994f2af30ab6b279714cd625e3af0592976549136cf56b423f8b1439400;

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant SAFE_HARBOR_ADOPTER_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x2a3e8e12 is `type(ISafeHarborAdopter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x2a3e8e12), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ISAFEHARBORADOPTER_SLOT =
    0xc27d89bdc7ce502086d0749a1bda2c210ca866065fa49ea19147ad53e8e018ad;

/// @dev Role allowed to adopt / update the diamond's Safe Harbor agreement. Distinct, high-stakes
///      permission because the agreement designates the asset-recovery address(es) for rescued funds.
///      Administered by `DEFAULT_ADMIN_ROLE` BY DESIGN (it is not self-administered, since no holder is
///      granted at init — self-administration would render it permanently un-grantable). The
///      recovery-address trust boundary therefore equals the diamond's root admin.
bytes32 constant SAFE_HARBOR_ADMIN_ROLE = keccak256("SAFE_HARBOR_ADMIN_ROLE");

/// @notice ERC-7201 namespaced storage for the SafeHarborAdopter module.
/// @dev APPEND-ONLY: new fields may only be added at the end to preserve the upgrade-safe layout.
/// @custom:storage-location erc7201:lattice.storage.SafeHarborAdopter
struct SafeHarborAdopterStorage {
    /// @dev The SEAL SafeHarborRegistry the diamond adopts through.
    address _safeHarborRegistry;
    /// @dev The SEAL AgreementFactory used by {createAndAdopt} (optional; zero disables that path).
    address _agreementFactory;
}

/// @title SafeHarborAdopterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Integrates the SEAL Whitehat Safe Harbor (https://github.com/security-alliance/safe-harbor)
/// @notice Library letting a diamond adopt the SEAL Whitehat Safe Harbor agreement on-chain — the legal
///         half of incident response, complementing the EmergencyStop technical half.
/// @dev Three-layer pattern: this library holds the logic + namespaced storage; the stateless
///      {SafeHarborAdopter} facet forwards to it. The diamond calls the registry itself
///      (`msg.sender == diamond`), so it is recorded as the adopter. All state-changing functions are
///      gated on `SAFE_HARBOR_ADMIN_ROLE` because the agreement designates the asset-recovery address.
library SafeHarborAdopterLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function safeHarborAdopterStorage() internal pure returns (SafeHarborAdopterStorage storage $) {
        assembly {
            $.slot := SAFE_HARBOR_ADOPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the SafeHarborAdopter module.
    /// @dev Must be called inside a pre/postInitializer block. Reverts {SafeHarborAdopterZeroRegistry}
    ///      for a zero registry; the factory may be zero (set later to enable {createAndAdopt}).
    ///      Registers ISafeHarborAdopter for ERC-165 discovery.
    /// @param _registry The SEAL SafeHarborRegistry for this chain.
    /// @param _factory The SEAL AgreementFactory for this chain (zero allowed).
    function __SafeHarborAdopter_init(address _registry, address _factory) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        if (_registry == address(0)) revert ISafeHarborAdopter.SafeHarborAdopterZeroRegistry();
        SafeHarborAdopterStorage storage $ = safeHarborAdopterStorage();
        $._safeHarborRegistry = _registry;
        $._agreementFactory = _factory;
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the ISafeHarborAdopter interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_ISAFEHARBORADOPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               ADOPTION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Adopts a pre-deployed `agreement` for this diamond. Gated on `SAFE_HARBOR_ADMIN_ROLE`.
    /// @param agreement The agreement contract to adopt.
    function adoptSafeHarbor(address agreement) internal {
        AccessControlLib.checkRole(SAFE_HARBOR_ADMIN_ROLE);
        if (agreement == address(0)) revert ISafeHarborAdopter.SafeHarborAdopterZeroAgreement();
        ISafeHarborRegistry(safeHarborAdopterStorage()._safeHarborRegistry).adoptSafeHarbor(agreement);
        emit ISafeHarborAdopter.SafeHarborAdopted(agreement);
    }

    /// @notice Creates an agreement via the factory and adopts it. Gated on `SAFE_HARBOR_ADMIN_ROLE`.
    /// @param details The agreement details (recovery addresses, accounts, bounty terms).
    /// @param chainValidator The SEAL ChainValidator contract for this chain.
    /// @param owner The owner of the new agreement.
    /// @param salt A caller-provided salt for CREATE2 uniqueness.
    /// @return agreement The newly created and adopted agreement address.
    function createAndAdopt(AgreementDetails calldata details, address chainValidator, address owner, bytes32 salt)
        internal
        returns (address agreement)
    {
        AccessControlLib.checkRole(SAFE_HARBOR_ADMIN_ROLE);
        SafeHarborAdopterStorage storage $ = safeHarborAdopterStorage();
        address factory = $._agreementFactory;
        if (factory == address(0)) revert ISafeHarborAdopter.SafeHarborAdopterZeroFactory();
        agreement = IAgreementFactory(factory).create(details, chainValidator, owner, salt);
        if (agreement == address(0)) revert ISafeHarborAdopter.SafeHarborAdopterZeroAgreement();
        ISafeHarborRegistry($._safeHarborRegistry).adoptSafeHarbor(agreement);
        emit ISafeHarborAdopter.SafeHarborAdopted(agreement);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              CONFIGURATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets or rotates the Safe Harbor registry. Gated on `SAFE_HARBOR_ADMIN_ROLE`.
    /// @param _registry The Safe Harbor registry to use.
    function setSafeHarborRegistry(address _registry) internal {
        AccessControlLib.checkRole(SAFE_HARBOR_ADMIN_ROLE);
        if (_registry == address(0)) revert ISafeHarborAdopter.SafeHarborAdopterZeroRegistry();
        safeHarborAdopterStorage()._safeHarborRegistry = _registry;
        emit ISafeHarborAdopter.SafeHarborRegistrySet(_registry);
    }

    /// @notice Sets or rotates the agreement factory. Gated on `SAFE_HARBOR_ADMIN_ROLE`.
    /// @param _factory The agreement factory to use.
    function setAgreementFactory(address _factory) internal {
        AccessControlLib.checkRole(SAFE_HARBOR_ADMIN_ROLE);
        if (_factory == address(0)) revert ISafeHarborAdopter.SafeHarborAdopterZeroFactory();
        safeHarborAdopterStorage()._agreementFactory = _factory;
        emit ISafeHarborAdopter.AgreementFactorySet(_factory);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the configured Safe Harbor registry.
    function safeHarborRegistry() internal view returns (address) {
        return safeHarborAdopterStorage()._safeHarborRegistry;
    }

    /// @notice Returns the configured agreement factory.
    function agreementFactory() internal view returns (address) {
        return safeHarborAdopterStorage()._agreementFactory;
    }

    /// @notice Returns the agreement currently adopted by this diamond (zero if none).
    /// @dev The SEAL registry reverts {SafeHarborRegistry__NoAgreement} when this diamond has not
    ///      adopted — that case is treated as "none" (zero). Any OTHER revert (e.g. a mis-set registry)
    ///      is re-surfaced rather than silently masked.
    function safeHarborAgreement() internal view returns (address) {
        try ISafeHarborRegistry(safeHarborAdopterStorage()._safeHarborRegistry).getAgreement(address(this)) returns (
            address agreement
        ) {
            return agreement;
        } catch (bytes memory err) {
            if (bytes4(err) != ISafeHarborRegistry.SafeHarborRegistry__NoAgreement.selector) {
                assembly ("memory-safe") {
                    revert(add(err, 0x20), mload(err))
                }
            }
            return address(0);
        }
    }
}

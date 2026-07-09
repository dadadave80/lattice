// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {IENSReverseClaimer} from "@lattice/interfaces/ens/IENSReverseClaimer.sol";
import {IReverseRegistrar} from "@lattice/interfaces/external/IReverseRegistrar.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ENSReverseClaimer")) - 1)) & ~bytes32(uint256(0xff))`.
///      Verify with: `cast index-erc7201 "lattice.storage.ENSReverseClaimer"`.
bytes32 constant ENS_REVERSE_CLAIMER_STORAGE_SLOT = 0x4490f19c91eeff7574cc9707696b972040b89f54488ef7fa354afe94a194c100;

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ENS_REVERSE_CLAIMER_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x84019dd8 is `type(IENSReverseClaimer).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x84019dd8), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IENSREVERSECLAIMER_SLOT =
    0x3c859ae3ba58f26576821324787594a5249343bb61f3f7c4054b439dbc4eff8c;

/// @dev Role allowed to manage the diamond's ENS identity (set its name / rotate the registrar).
bytes32 constant ENS_MANAGER_ROLE = keccak256("ENS_MANAGER_ROLE");

/// @notice ERC-7201 namespaced storage for the ENSReverseClaimer module.
/// @dev APPEND-ONLY: new fields may only be added at the end to preserve the upgrade-safe layout.
/// @custom:storage-location erc7201:lattice.storage.ENSReverseClaimer
struct ENSReverseClaimerStorage {
    /// @dev The ENS reverse registrar (L1 `ReverseRegistrar` or ENSIP-11 `L2ReverseRegistrar`).
    address _reverseRegistrar;
    /// @dev The last ENS name set through this facet — a convenience cache only. May diverge from the
    ///      live ENS reverse record (direct resolver writes, registrar rotation); ENS is authoritative.
    string _ensName;
}

/// @title ENSReverseClaimerLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ENS (https://github.com/ensdomains/ens-contracts)
/// @notice Library letting a diamond claim and advertise its own primary ENS name via ENS reverse
///         resolution, so resolving the diamond address returns its name (e.g. `treasury.myproto.eth`).
/// @dev Three-layer pattern: this library holds all logic and the namespaced storage; the stateless
///      {ENSReverseClaimer} facet forwards to it. Identity changes are gated on `ENS_MANAGER_ROLE`.
///      The diamond calls `IReverseRegistrar.setName` itself, so `msg.sender` at the registrar is the
///      diamond — exactly what makes the diamond's `addr.reverse` record resolve to the chosen name.
library ENSReverseClaimerLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function ensReverseClaimerStorage() internal pure returns (ENSReverseClaimerStorage storage $) {
        assembly {
            $.slot := ENS_REVERSE_CLAIMER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the ENSReverseClaimer module with the reverse registrar to use.
    /// @dev Must be called inside a pre/postInitializer block. Reverts {ENSReverseClaimerZeroRegistrar}
    ///      for a zero registrar. Registers IENSReverseClaimer for ERC-165 discovery.
    /// @param _reverseRegistrar The ENS reverse registrar for this chain.
    function __ENSReverseClaimer_init(address _reverseRegistrar) internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        if (_reverseRegistrar == address(0)) revert IENSReverseClaimer.ENSReverseClaimerZeroRegistrar();
        ensReverseClaimerStorage()._reverseRegistrar = _reverseRegistrar;
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IENSReverseClaimer interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IENSREVERSECLAIMER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              ENS IDENTITY
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets the diamond's primary ENS name via the configured reverse registrar.
    /// @dev Gated on `ENS_MANAGER_ROLE`. The registrar is non-zero by construction (enforced at init and
    ///      in {setReverseRegistrar}), so `setName` always targets a configured registrar. The external
    ///      `setName` call uses a void-typed interface so it works against both the L1 `ReverseRegistrar`
    ///      (which returns `bytes32`, ignored) and the L2 `L2ReverseRegistrar` (which returns nothing).
    ///      Passing an empty string clears the reverse record (canonical `ReverseRegistrar` semantics).
    /// @param name The ENS name to set as the diamond's primary name.
    function setEnsName(string calldata name) internal {
        AccessControlLib.checkRole(ENS_MANAGER_ROLE);
        ENSReverseClaimerStorage storage $ = ensReverseClaimerStorage();
        // Effects before interactions (CEI): cache the name, then call the external registrar.
        $._ensName = name;
        IReverseRegistrar($._reverseRegistrar).setName(name);
        emit IENSReverseClaimer.EnsNameSet(name);
    }

    /// @notice Sets or rotates the reverse registrar (per-chain configuration).
    /// @dev Gated on `ENS_MANAGER_ROLE`. Reverts {ENSReverseClaimerZeroRegistrar} for a zero address.
    ///      The registrar is trusted code reached via an external call in {setEnsName}; only an
    ///      `ENS_MANAGER_ROLE` holder can point the diamond at it.
    /// @param _reverseRegistrar The reverse registrar to use.
    function setReverseRegistrar(address _reverseRegistrar) internal {
        AccessControlLib.checkRole(ENS_MANAGER_ROLE);
        if (_reverseRegistrar == address(0)) revert IENSReverseClaimer.ENSReverseClaimerZeroRegistrar();
        ensReverseClaimerStorage()._reverseRegistrar = _reverseRegistrar;
        emit IENSReverseClaimer.ReverseRegistrarSet(_reverseRegistrar);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the diamond's last ENS name set through this facet.
    function ensName() internal view returns (string memory) {
        return ensReverseClaimerStorage()._ensName;
    }

    /// @notice Returns the currently configured reverse registrar.
    function reverseRegistrar() internal view returns (address) {
        return ensReverseClaimerStorage()._reverseRegistrar;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ENSReverseClaimerLib} from "@lattice/ens/libraries/ENSReverseClaimerLib.sol";
import {IENSReverseClaimer} from "@lattice/interfaces/ens/IENSReverseClaimer.sol";

/// @title ENSReverseClaimer
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ENS (https://github.com/ensdomains/ens-contracts)
/// @author Conforms to ENS reverse resolution (https://docs.ens.domains/learn/protocol#reverse-resolution)
/// @notice Stateless Diamond facet letting a diamond claim and advertise its own primary ENS name via
///         ENS reverse resolution. Inherit this in your Diamond to make the contract resolve to e.g.
///         `treasury.myproto.eth` in explorers and wallets.
/// @dev All logic lives in {ENSReverseClaimerLib}. Identity changes are gated on `ENS_MANAGER_ROLE`
///      (managed through the diamond's AccessControl module). The registrar is supplied at init and
///      can be rotated per chain via {setReverseRegistrar}.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Lattice original
contract ENSReverseClaimer is IENSReverseClaimer {
    /// @inheritdoc IENSReverseClaimer
    function setEnsName(string calldata name) external virtual {
        ENSReverseClaimerLib.setEnsName(name);
    }

    /// @inheritdoc IENSReverseClaimer
    function setReverseRegistrar(address reverseRegistrar) external virtual {
        ENSReverseClaimerLib.setReverseRegistrar(reverseRegistrar);
    }

    /// @inheritdoc IENSReverseClaimer
    function ensName() external view virtual returns (string memory) {
        return ENSReverseClaimerLib.ensName();
    }

    /// @inheritdoc IENSReverseClaimer
    function reverseRegistrar() external view virtual returns (address) {
        return ENSReverseClaimerLib.reverseRegistrar();
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ENSReverseClaimer methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `ensName()` 0x8ef71b8d
    ///      `reverseRegistrar()` 0x80869853
    ///      `setEnsName(string)` 0xdf0487bc
    ///      `setReverseRegistrar(address)` 0x557499ba
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"8ef71b8d80869853df0487bc557499ba";
    }
}

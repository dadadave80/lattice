// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ENSSubnameIssuerLib} from "@lattice/ens/libraries/ENSSubnameIssuerLib.sol";
import {IENSSubnameIssuer} from "@lattice/interfaces/ens/IENSSubnameIssuer.sol";

/// @title ENSSubnameIssuer
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ENS (https://github.com/ensdomains/ens-contracts)
/// @author Integrates the ENS NameWrapper (https://docs.ens.domains/wrapper/overview)
/// @notice Stateless Diamond facet letting a diamond that owns a parent ENS name mint subnames
///         (e.g. `treasury.myproto.eth`) via the ENS NameWrapper.
/// @dev All logic lives in {ENSSubnameIssuerLib}. Issuance is gated on `ENS_SUBNAME_ISSUER_ROLE`; the
///      NameWrapper is supplied at init and rotated per chain via {setNameWrapper}.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Lattice original
contract ENSSubnameIssuer is IENSSubnameIssuer {
    /// @inheritdoc IENSSubnameIssuer
    function issueSubname(
        bytes32 parentNode,
        string calldata label,
        address owner,
        address resolver,
        uint64 ttl,
        uint32 fuses,
        uint64 expiry
    ) external virtual returns (bytes32) {
        return ENSSubnameIssuerLib.issueSubname(parentNode, label, owner, resolver, ttl, fuses, expiry);
    }

    /// @inheritdoc IENSSubnameIssuer
    function setNameWrapper(address nameWrapper_) external virtual {
        ENSSubnameIssuerLib.setNameWrapper(nameWrapper_);
    }

    /// @inheritdoc IENSSubnameIssuer
    function nameWrapper() external view virtual returns (address) {
        return ENSSubnameIssuerLib.nameWrapper();
    }
}

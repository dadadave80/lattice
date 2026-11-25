// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ENSSubnameIssuerV2Lib} from "@lattice/ens/libraries/ENSSubnameIssuerV2Lib.sol";
import {IENSSubnameIssuerV2} from "@lattice/interfaces/ens/IENSSubnameIssuerV2.sol";

/// @title ENSSubnameIssuerV2
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ENS (https://github.com/ensdomains/contracts-v2)
/// @notice Issues subnames under canonical ENSv2 parents that grant the diamond registrar authority.
/// @custom:lattice-source Lattice original
/// @custom:lattice-requires AccessControl|AccessControlEnumerable|AccessControlTimed convention role-management-surface;
/// @custom:lattice-family none
/// @custom:lattice-owns none;
/// @custom:lattice-touches lattice.storage.ENSSubnameIssuerV2;
/// @custom:lattice-seam none;
/// @custom:lattice-init ENSSubnameIssuerV2Init
contract ENSSubnameIssuerV2 is IENSSubnameIssuerV2 {
    /// @inheritdoc IENSSubnameIssuerV2
    function issueEnsSubnameV2(
        bytes calldata parentDnsName,
        string calldata label,
        address owner,
        address childRegistry,
        address resolver,
        uint256 ownerRoles,
        uint64 expiry
    ) external returns (uint256 tokenId) {
        return ENSSubnameIssuerV2Lib.issueEnsSubnameV2(
            parentDnsName, label, owner, childRegistry, resolver, ownerRoles, expiry
        );
    }

    /// @inheritdoc IENSSubnameIssuerV2
    function ensUniversalHelper() external view returns (address) {
        return ENSSubnameIssuerV2Lib.ensUniversalHelper();
    }

    /// @inheritdoc IENSSubnameIssuerV2
    function setEnsUniversalHelper(address helper) external {
        ENSSubnameIssuerV2Lib.setEnsUniversalHelper(helper);
    }

    /// @notice ERC-8153 packed selectors in method identifier order.
    function exportSelectors() external pure returns (bytes memory selectors) {
        selectors = hex"eccbf4d94c856fa3fdfad8f7";
    }
}

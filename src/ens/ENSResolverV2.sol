// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ENSResolverV2Lib} from "@lattice/ens/libraries/ENSResolverV2Lib.sol";
import {IENSResolverV2} from "@lattice/interfaces/ens/IENSResolverV2.sol";

/// @title ENSResolverV2
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ENS Universal Resolver (https://github.com/ensdomains/contracts-v2)
/// @notice Synchronous ENSv2 ETH address resolution for a diamond.
/// @custom:lattice-source Lattice original
/// @custom:lattice-requires AccessControl|AccessControlEnumerable|AccessControlTimed convention role-management-surface;
/// @custom:lattice-family none
/// @custom:lattice-owns none;
/// @custom:lattice-touches lattice.storage.ENSResolverV2;
/// @custom:lattice-seam none;
/// @custom:lattice-init ENSResolverV2Init
contract ENSResolverV2 is IENSResolverV2 {
    /// @inheritdoc IENSResolverV2
    function resolveEnsAddressV2(bytes calldata dnsName) external view returns (address) {
        return ENSResolverV2Lib.resolveEnsAddressV2(dnsName);
    }

    /// @inheritdoc IENSResolverV2
    function ensUniversalResolver() external view returns (address) {
        return ENSResolverV2Lib.ensUniversalResolver();
    }

    /// @inheritdoc IENSResolverV2
    function setEnsUniversalResolver(address endpoint) external {
        ENSResolverV2Lib.setEnsUniversalResolver(endpoint);
    }

    /// @notice ERC-8153 packed selectors in signature order.
    function exportSelectors() external pure returns (bytes memory) {
        return hex"12211cf9b8dec831a4c7f819";
    }
}

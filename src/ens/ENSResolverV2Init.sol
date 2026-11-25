// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ENSResolverV2Lib} from "@lattice/ens/libraries/ENSResolverV2Lib.sol";

/// @title ENSResolverV2Init
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Initializes ENSv2 resolution in the diamond's existing initialization window.
/// @custom:lattice-kind step
contract ENSResolverV2Init {
    /// @notice Stores the Universal Resolver proxy and registers IENSResolverV2.
    /// @param universalResolver The authenticated ENSv2 proxy for this chain.
    /// @custom:lattice-initializes ENSResolverV2;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call Initializable hard enclosing-initializing-window;
    /// @custom:lattice-param universalResolver;
    /// @custom:lattice-registers-interfaces
    function init(address universalResolver) external {
        ENSResolverV2Lib.__ENSResolverV2_init(universalResolver);
    }
}

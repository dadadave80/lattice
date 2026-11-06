// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title MetadataFoldFixture
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @custom:lattice-requires ERC20 hard first record;
/// @custom:lattice-requires AccessControl convention second record;
/// @custom:lattice-family none
contract MetadataFoldFixture {
    /// @custom:lattice-kind step
    /// @custom:lattice-param delay unit=seconds rule=nonzero;
    /// @custom:lattice-param admin authority;
    /// @custom:lattice-registers-interfaces
    function init(uint256 delay, address admin) external pure {
        (delay, admin);
    }

    /// @custom:lattice-registers-interfaces
    /// @custom:lattice-param admin authority;
    function misordered(address admin) external pure {
        (admin);
    }
}

/// @title MetadataMissingFixture
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @custom:lattice-requires none;
/// @custom:lattice-family none
/// @custom:lattice-owns none;
/// @custom:lattice-touches none;
/// @custom:lattice-seam none;
contract MetadataMissingFixture {}

/// @title MetadataDanglingFixture
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @custom:lattice-requires DoesNotExist hard mutation;
/// @custom:lattice-family none
/// @custom:lattice-owns none;
/// @custom:lattice-touches none;
/// @custom:lattice-init none
/// @custom:lattice-seam none;
contract MetadataDanglingFixture {}

/// @title MetadataDanglingInitializerFixture
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @custom:lattice-kind step
contract MetadataDanglingInitializerFixture {
    /// @custom:lattice-initializes DoesNotExist;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call none;
    /// @custom:lattice-param none;
    function init() external pure {}
}

/// @title MetadataMissingParameterFixture
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @custom:lattice-kind step
contract MetadataMissingParameterFixture {
    /// @custom:lattice-initializes ERC20;
    /// @custom:lattice-after none;
    /// @custom:lattice-same-call none;
    function init(address admin) external pure {
        (admin);
    }
}

/// @title MetadataNonInitializerContractFixture
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @custom:lattice-requires none;
/// @custom:lattice-family none
/// @custom:lattice-owns none;
/// @custom:lattice-touches none;
/// @custom:lattice-init ERC20
/// @custom:lattice-seam none;
contract MetadataNonInitializerContractFixture {}

/// @title MetadataNonInitializerLibraryFixture
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @custom:lattice-requires none;
/// @custom:lattice-family none
/// @custom:lattice-owns none;
/// @custom:lattice-touches none;
/// @custom:lattice-init ERC20Lib
/// @custom:lattice-seam none;
contract MetadataNonInitializerLibraryFixture {}

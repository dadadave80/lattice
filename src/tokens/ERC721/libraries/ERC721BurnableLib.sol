// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC721Lib} from "@lattice/tokens/ERC721/libraries/ERC721Lib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev 0x42966c68 is `type(IERC721Burnable).interfaceId` (the `burn(uint256)` selector).
/// `keccak256(abi.encode(bytes4(0x42966c68), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC721BURNABLE_SLOT = 0x9eb38abe883a9d9203f59f04d3952f6b497989121d4c2afe4ca6d5038b9dfc43;

/// @title ERC721BurnableLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC721/extensions/ERC721Burnable.sol)
/// @notice Library implementing the ERC-721 burn extension. Adds no own storage: it burns through {ERC721Lib}.
/// @dev Burns call {ERC721Lib._update} directly. An extension that observes token movement by `Replace`-ing the
///      base transfer selectors (an Enumerable, Pausable or Votes facet) would not see these burns; issue #234
///      decides how such extensions hook movement.
library ERC721BurnableLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the IERC721Burnable interface for ERC-165 discovery.
    /// @dev Must be called inside a pre/postInitializer block. No own storage to initialize.
    function __ERC721Burnable_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IERC721Burnable interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC721BURNABLE_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             BURN OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Destroys `tokenId`, authorized by the caller.
    /// @dev A non-zero `auth` makes {ERC721Lib._update} run `_checkAuthorized`, which reverts
    ///      {IERC721.ERC721NonexistentToken} for an unminted or burned id, so the previous owner needs no check here.
    function burn(uint256 tokenId) internal {
        ERC721Lib._update(address(0), tokenId, msg.sender);
    }
}

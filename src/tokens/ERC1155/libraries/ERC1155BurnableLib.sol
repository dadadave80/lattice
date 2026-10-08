// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1155Lib} from "@lattice/tokens/ERC1155/libraries/ERC1155Lib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev 0x9e094e9e is `type(IERC1155Burnable).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x9e094e9e), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC1155BURNABLE_SLOT = 0xb792d4a365dc518babbaf5a6b3fa80d3f09c413d4a7f831e1cc47184f1a864a9;

/// @title ERC1155BurnableLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC1155/extensions/ERC1155Burnable.sol)
/// @notice Library implementing the ERC-1155 burn extension. Adds no own storage: burns debit the {ERC1155Lib}
///         balances.
library ERC1155BurnableLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the IERC1155Burnable interface for ERC-165 discovery.
    /// @dev Must be called inside a pre/postInitializer block. No own storage to initialize.
    function __ERC1155Burnable_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IERC1155Burnable interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC1155BURNABLE_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             BURN OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Destroys `value` tokens of type `id` from `account`. The caller must be `account` or an approved
    ///         operator of `account`.
    function burn(address account, uint256 id, uint256 value) internal {
        ERC1155Lib._checkAuthorized(msg.sender, account);
        ERC1155Lib._burn(account, id, value);
    }

    /// @notice Batched version of {burn}.
    function burnBatch(address account, uint256[] memory ids, uint256[] memory values) internal {
        ERC1155Lib._checkAuthorized(msg.sender, account);
        ERC1155Lib._burnBatch(account, ids, values);
    }
}

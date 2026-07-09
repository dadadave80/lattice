// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {ITokenBound} from "@lattice/interfaces/accounts/ITokenBound.sol";
import {IERC721} from "@lattice/interfaces/tokens/IERC721.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC6551Account")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC6551_ACCOUNT_STORAGE_SLOT = 0x5d509296c8693d1a2071f7702ffb166090e7cdcee4fc11a42df61b6a19026100;

/// @dev ERC-165 map slots. `keccak256(abi.encode(bytes4(id), 0x9ca7f3e2…c1c4200))`.
///      IERC6551Account = 0x6faff5f1; IERC6551Executable = 0x51945447.
bytes32 constant ERC165_MAP_IERC6551ACCOUNT_SLOT = 0xe5e50471a231013bea8f6034ec0b978814d697120ebd88e3624ed42959ed0a66;
bytes32 constant ERC165_MAP_IERC6551EXECUTABLE_SLOT =
    0x7119a8e42d55700f1f34f34e17ffb769e414497fcab2ff2004aa97c610742b4b;

/// @dev ERC-6551 `isValidSigner` success magic value (its own selector).
bytes4 constant ERC6551_VALID_SIGNER_MAGIC = 0x523e3260;

/// @notice ERC-7201 namespaced storage for the token-bound account.
/// @custom:storage-location erc7201:lattice.storage.ERC6551Account
struct ERC6551AccountStorage {
    /// @notice Home chain of the bound token. APPEND-ONLY.
    uint256 _chainId;
    /// @notice Bound ERC-721 contract. APPEND-ONLY.
    address _tokenContract;
    /// @notice Bound token id. APPEND-ONLY.
    uint256 _tokenId;
    /// @notice Monotonic state counter (bumped on each execution). APPEND-ONLY.
    uint256 _state;
}

/// @title ERC6551AccountLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-6551 reference (https://github.com/erc6551/reference)
/// @notice Logic + ERC-7201 storage for the ERC-6551 token-bound account. The account is controlled by the
///         current owner of the bound ERC-721 token: that owner is the sole valid signer and the only caller of
///         `execute`. The binding is set once at init.
/// @dev v1 supports `operation == 0` (CALL) and resolves ownership only on the token's home chain (a token
///      bound on a foreign chain has no on-chain-resolvable owner → no valid signer). `state` bumps on each
///      execution so consumers can detect account mutations.
library ERC6551AccountLib {
    function erc6551AccountStorage() internal pure returns (ERC6551AccountStorage storage $) {
        assembly {
            $.slot := ERC6551_ACCOUNT_STORAGE_SLOT
        }
    }

    /// @notice Binds the account to `(chainId, tokenContract, tokenId)` and registers the ERC-6551 ids.
    function __ERC6551Account_init(uint256 chainId, address tokenContract, uint256 tokenId) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        ERC6551AccountStorage storage $ = erc6551AccountStorage();
        $._chainId = chainId;
        $._tokenContract = tokenContract;
        $._tokenId = tokenId;
        registerInterfaces();
        emit ITokenBound.Bound(chainId, tokenContract, tokenId);
    }

    /// @notice Writes `true` to the ERC-165 map slots for `IERC6551Account` and `IERC6551Executable`.
    function registerInterfaces() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC6551ACCOUNT_SLOT, true)
            sstore(ERC165_MAP_IERC6551EXECUTABLE_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    function token() internal view returns (uint256 chainId, address tokenContract, uint256 tokenId) {
        ERC6551AccountStorage storage $ = erc6551AccountStorage();
        return ($._chainId, $._tokenContract, $._tokenId);
    }

    function state() internal view returns (uint256) {
        return erc6551AccountStorage()._state;
    }

    /// @notice Returns the ERC-6551 magic value iff `signer` is the bound token's current owner.
    function isValidSigner(address signer, bytes calldata) internal view returns (bytes4) {
        return (signer != address(0) && signer == _tokenOwner()) ? ERC6551_VALID_SIGNER_MAGIC : bytes4(0);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 EXECUTION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Executes a CALL on behalf of the token owner. Reverts {InvalidSigner} for any other caller and
    ///         {UnsupportedOperation} for `operation != 0`. Bumps `state`; bubbles inner revert data.
    function execute(address to, uint256 value, bytes calldata data, uint8 operation)
        internal
        returns (bytes memory result)
    {
        if (msg.sender != _tokenOwner()) revert ITokenBound.InvalidSigner(msg.sender);
        if (operation != 0) revert ITokenBound.UnsupportedOperation(operation);
        ++erc6551AccountStorage()._state;
        bool ok;
        (ok, result) = to.call{value: value}(data);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(result, 0x20), mload(result))
            }
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice The bound token's current owner, or `address(0)` if bound on another chain or unresolvable.
    function _tokenOwner() private view returns (address) {
        ERC6551AccountStorage storage $ = erc6551AccountStorage();
        if ($._chainId != block.chainid) return address(0);
        try IERC721($._tokenContract).ownerOf($._tokenId) returns (address o) {
            return o;
        } catch {
            return address(0);
        }
    }
}

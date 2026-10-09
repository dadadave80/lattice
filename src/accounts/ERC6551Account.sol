// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC6551AccountLib} from "@lattice/accounts/libraries/ERC6551AccountLib.sol";
import {IERC6551Account, IERC6551Executable} from "@lattice/interfaces/external/ercs/IERC6551.sol";

/// @title ERC6551Account
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-6551 reference (https://github.com/erc6551/reference)
/// @notice ERC-6551 token-bound account facet. The Diamond becomes an account owned by a specific ERC-721
///         token; the token's current owner is the sole valid signer and the only caller of `execute`.
/// @dev Stateless delegator — logic/storage live in {ERC6551AccountLib}. v1 supports `operation == 0` (CALL)
///      and resolves ownership only on the token's home chain. The bound token is set once at initialization.
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source ERC-6551
contract ERC6551Account is IERC6551Account, IERC6551Executable {
    /// @inheritdoc IERC6551Account
    receive() external payable virtual {}

    /// @inheritdoc IERC6551Account
    function isValidSigner(address signer, bytes calldata context) external view virtual returns (bytes4) {
        return ERC6551AccountLib.isValidSigner(signer, context);
    }

    /// @inheritdoc IERC6551Account
    function state() external view virtual returns (uint256) {
        return ERC6551AccountLib.state();
    }

    /// @inheritdoc IERC6551Account
    function token() external view virtual returns (uint256 chainId, address tokenContract, uint256 tokenId) {
        return ERC6551AccountLib.token();
    }

    /// @inheritdoc IERC6551Executable
    function execute(address to, uint256 value, bytes calldata data, uint8 operation)
        external
        payable
        virtual
        returns (bytes memory)
    {
        return ERC6551AccountLib.execute(to, value, data, operation);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect ERC6551Account methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. `receive()` has no selector and is not exported: behind a diamond, plain
    ///      ETH transfers reach the cut {Receive} facet (its export is 0x00000000). Chunks:
    ///      `execute(address,uint256,bytes,uint8)` 0x51945447
    ///      `isValidSigner(address,bytes)` 0x523e3260
    ///      `state()` 0xc19d93fb
    ///      `token()` 0xfc0c546a
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors = hex"51945447523e3260c19d93fbfc0c546a";
    }
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title ITokenBound
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Lattice error/event surface of the ERC-6551 `ERC6551Account` facet. The standard `token` /
///         `state` / `isValidSigner` / `execute` functions are on the vendored `IERC6551Account` /
///         `IERC6551Executable`.
/// @dev The account is controlled by the owner of the bound ERC-721 token. v1 supports `operation == 0` (CALL)
///       and resolves ownership only on the token's home chain.
interface ITokenBound {
    /// @notice Emitted once when the account is bound to its token at initialization.
    event Bound(uint256 chainId, address indexed tokenContract, uint256 indexed tokenId);

    /// @notice The caller is not the bound token's owner (the only valid signer).
    error InvalidSigner(address signer);

    /// @notice The execution `operation` is not supported (v1: only `0` == CALL).
    error UnsupportedOperation(uint8 operation);
}

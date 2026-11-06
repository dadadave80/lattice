// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ICompliance
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-3643 (https://eips.ethereum.org/EIPS/eip-3643)
/// @notice Fresh declaration of the standard CC0 ABI; implementation is authored independently.
interface ICompliance {
    error ERC3643InvalidToken(address token);
    error ERC3643TokenAlreadyBound(address boundToken);
    error ERC3643TokenNotBound(address token);
    error ERC3643UnauthorizedToken(address caller);

    event TokenBound(address token);

    event TokenUnbound(address token);

    function bindToken(address token) external;

    function unbindToken(address token) external;

    function transferred(address from, address to, uint256 amount) external;

    function created(address to, uint256 amount) external;

    function destroyed(address from, uint256 amount) external;

    function canTransfer(address from, address to, uint256 amount) external view returns (bool);

    function getTokenBound() external view returns (address);
}

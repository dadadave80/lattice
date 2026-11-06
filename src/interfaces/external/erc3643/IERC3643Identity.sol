// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IERC3643Identity
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author ABI-equivalent interface authored fresh from ERC-3643's public CC0 ABI (https://github.com/ethereum/ERCs/blob/7dafd1125fffbd3832316edeb739608ad82bb4c4/assets/erc-3643/ONCHAINID/IIdentity.sol).
///         Upstream license: CC0-1.0.
interface IERC3643Identity {
    function keyHasPurpose(bytes32 key, uint256 purpose) external view returns (bool);
    function getClaim(bytes32 claimId)
        external
        view
        returns (
            uint256 topic,
            uint256 scheme,
            address issuer,
            bytes memory signature,
            bytes memory data,
            string memory uri
        );
}

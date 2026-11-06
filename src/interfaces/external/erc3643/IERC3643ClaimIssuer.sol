// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC3643Identity} from "@lattice/interfaces/external/erc3643/IERC3643Identity.sol";

/// @title IERC3643ClaimIssuer
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author ABI-equivalent interface authored fresh from ERC-3643's public CC0 ABI (https://github.com/ethereum/ERCs/blob/7dafd1125fffbd3832316edeb739608ad82bb4c4/assets/erc-3643/ONCHAINID/IClaimIssuer.sol).
///         Upstream license: CC0-1.0.
interface IERC3643ClaimIssuer {
    function isClaimValid(IERC3643Identity identity, uint256 topic, bytes calldata signature, bytes calldata data)
        external
        view
        returns (bool);
}

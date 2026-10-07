// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.4;

/// @title IHRC719
/// @author Vendored minimal subset of hiero-ledger/hiero-contracts `contracts/token-service/IHRC719.sol`
///         (https://github.com/hiero-ledger/hiero-contracts/blob/main/contracts/token-service/IHRC719.sol),
///         commit 5ade6c8 (2026-09-09). Upstream license: Apache-2.0 (Hedera Hashgraph, LLC).
/// @notice HIP-719 token-address facade: every HTS token address carries proxy bytecode that redirects these
///         selectors (and the ERC-20/721 ones) to the HTS system contract for the CALLER's account.
interface IHRC719 {
    function associate() external returns (uint256 responseCode);
    function dissociate() external returns (uint256 responseCode);
    function isAssociated() external view returns (bool associated);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {euint64, externalEuint64} from "@lattice/interfaces/external/fhevm/EncryptedTypes.sol";

/// @title IERC7984Mintable
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin Confidential Contracts (https://github.com/OpenZeppelin/openzeppelin-confidential-contracts)
/// @notice Role-gated confidential mint for an ERC-7984 (confidential fungible token) diamond. The interface id
///         is `0x1b4d3d0d`, the selector of OpenZeppelin's `IERC7984Rwa.confidentialMint`.
/// @dev Declares no events or errors and does not inherit {IERC7984}, which would change the id. A mint emits
///      {IERC7984.ConfidentialTransfer} from `address(0)`.
interface IERC7984Mintable {
    /// @notice Mints an externally encrypted `encryptedAmount`, proven by `inputProof`, to `to`. The caller must
    ///         hold `ERC7984_MINTER_ROLE`. A mint that would overflow the total supply mints zero.
    /// @dev Reverts, in order:
    ///      - {IERC7984.ERC7984UnauthorizedCaller} with `address(this)` when the diamond calls itself;
    ///      - {IERC7984.ERC7984NotInitialized} when the token was never initialized;
    ///      - `AccessControlUnauthorizedAccount(msg.sender, ERC7984_MINTER_ROLE)` when the caller lacks the role;
    ///      - the input verification errors: with a proof, the host input verifier's errors for a proof that does not
    ///        verify for the caller; with an empty proof, `SenderNotAllowedToUseHandle(handle, msg.sender)` when the
    ///        handle is not allowed to the caller, and the executor's `InvalidType()` when it is not an `euint64`;
    ///      - {IERC7984.ERC7984InvalidReceiver} with `to` when `to` is the zero address or the diamond.
    /// @return minted The minted encrypted amount handle, allowed to the caller, `to` and the diamond.
    function confidentialMint(address to, externalEuint64 encryptedAmount, bytes calldata inputProof)
        external
        returns (euint64 minted);
}

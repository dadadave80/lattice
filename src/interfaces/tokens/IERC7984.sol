// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ebool, euint64, externalEuint64} from "@lattice/interfaces/external/fhevm/EncryptedTypes.sol";

/// @title IERC7984
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin Confidential Contracts (https://github.com/OpenZeppelin/openzeppelin-confidential-contracts)
/// @notice Confidential fungible token interface (ERC-7984): balances and amounts are encrypted
///         `euint64` handles. The interface id is `0x4958f2a4`.
/// @dev Errors and events are declared here, the Lattice convention. Amount handles are `bytes32` on the wire.
interface IERC7984 {
    /// @notice The `until` timestamp up to which `operator` may move `holder`'s tokens was set.
    event OperatorSet(address indexed holder, address indexed operator, uint48 until);

    /// @notice An encrypted `amount` moved from `from` to `to`.
    event ConfidentialTransfer(address indexed from, address indexed to, euint64 indexed amount);

    /// @notice An encrypted amount was publicly disclosed as `amount`.
    event AmountDisclosed(euint64 indexed encryptedAmount, uint64 amount);

    /// @notice The receiver is the zero address, or the diamond itself.
    error ERC7984InvalidReceiver(address receiver);

    /// @notice The sender is the zero address.
    error ERC7984InvalidSender(address sender);

    /// @notice `spender` is not an operator of the holder.
    error ERC7984UnauthorizedSpender(address holder, address spender);

    /// @notice `user` may not use the encrypted `amount` handle.
    error ERC7984UnauthorizedUseOfEncryptedAmount(euint64 amount, address user);

    /// @notice The caller is not allowed; the diamond reports `address(this)` for a self-call.
    error ERC7984UnauthorizedCaller(address caller);

    /// @notice `user` may not use the encrypted `amount` handle (receiver callback check).
    error ERC7984UtilsUnauthorizedUseOfEncryptedAmount(euint64 amount, address user);

    /// @notice The diamond already routes `selector` to `facet`, a selector this token would shadow.
    error ERC7984DiamondCallerInstalled(bytes4 selector, address facet);

    /// @notice The host is an EIP-7702 (code delegation for externally owned accounts) delegated account.
    error ERC7984DelegatedHost(address host);

    /// @notice The token was used before initialization.
    error ERC7984NotInitialized();

    /// @notice Returns the token name.
    function name() external view returns (string memory);

    /// @notice Returns the token symbol.
    function symbol() external view returns (string memory);

    /// @notice Returns the number of decimals (6).
    function decimals() external view returns (uint8);

    /// @notice Returns the contract-level metadata URI.
    function contractURI() external view returns (string memory);

    /// @notice Returns the encrypted total supply handle.
    function confidentialTotalSupply() external view returns (euint64);

    /// @notice Returns the encrypted balance handle of `account`.
    function confidentialBalanceOf(address account) external view returns (euint64);

    /// @notice Returns whether `spender` is currently an operator of `holder`.
    function isOperator(address holder, address spender) external view returns (bool);

    /// @notice Makes the caller's tokens movable by `operator` until the `until` timestamp.
    function setOperator(address operator, uint48 until) external;

    /// @notice Transfers an externally encrypted `encryptedAmount`, proven by `inputProof`, to `to`.
    /// @return The transferred encrypted amount handle.
    function confidentialTransfer(address to, externalEuint64 encryptedAmount, bytes calldata inputProof)
        external
        returns (euint64);

    /// @notice Transfers the already-encrypted `amount` handle to `to`.
    /// @return The transferred encrypted amount handle.
    function confidentialTransfer(address to, euint64 amount) external returns (euint64);

    /// @notice Operator transfer of an externally encrypted amount from `from` to `to`.
    /// @return The transferred encrypted amount handle.
    function confidentialTransferFrom(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) external returns (euint64);

    /// @notice Operator transfer of the already-encrypted `amount` handle from `from` to `to`.
    /// @return The transferred encrypted amount handle.
    function confidentialTransferFrom(address from, address to, euint64 amount) external returns (euint64);

    /// @notice Like {confidentialTransfer} with an input proof, then calls the receiver with `data`.
    /// @return The transferred encrypted amount handle.
    function confidentialTransferAndCall(
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof,
        bytes calldata data
    ) external returns (euint64);

    /// @notice Like {confidentialTransfer} with a handle, then calls the receiver with `data`.
    /// @return The transferred encrypted amount handle.
    function confidentialTransferAndCall(address to, euint64 amount, bytes calldata data) external returns (euint64);

    /// @notice Like {confidentialTransferFrom} with an input proof, then calls the receiver with `data`.
    /// @return The transferred encrypted amount handle.
    function confidentialTransferFromAndCall(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof,
        bytes calldata data
    ) external returns (euint64);

    /// @notice Like {confidentialTransferFrom} with a handle, then calls the receiver with `data`.
    /// @return The transferred encrypted amount handle.
    function confidentialTransferFromAndCall(address from, address to, euint64 amount, bytes calldata data)
        external
        returns (euint64);
}

/// @title IERC7984Disclosure
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin Confidential Contracts (https://github.com/OpenZeppelin/openzeppelin-confidential-contracts)
/// @notice Public disclosure of an encrypted amount. Outside the ERC-7984 interface id.
interface IERC7984Disclosure {
    /// @notice `requester` asked for `encryptedAmount` to be made publicly decryptable.
    event AmountDiscloseRequested(euint64 indexed encryptedAmount, address indexed requester);

    /// @notice Marks `encryptedAmount` publicly decryptable, so the key management service can sign its cleartext.
    function requestDiscloseEncryptedAmount(euint64 encryptedAmount) external;

    /// @notice Verifies the key management service proof and publishes `cleartextAmount` for `encryptedAmount`.
    function discloseEncryptedAmount(euint64 encryptedAmount, uint64 cleartextAmount, bytes calldata decryptionProof)
        external;
}

/// @title IERC7984Receiver
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin Confidential Contracts (https://github.com/OpenZeppelin/openzeppelin-confidential-contracts)
/// @notice Callback for contracts receiving ERC-7984 tokens through the `...AndCall` transfers.
interface IERC7984Receiver {
    /// @notice Called after `amount` was transferred from `from`, moved by `operator`.
    /// @return An encrypted boolean; an encrypted false makes the token refund the transfer.
    function onConfidentialTransferReceived(address operator, address from, euint64 amount, bytes calldata data)
        external
        returns (ebool);
}

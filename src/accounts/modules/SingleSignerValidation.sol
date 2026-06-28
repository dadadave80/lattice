// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {PackedUserOperation} from "@lattice/interfaces/external/IAccount.sol";
import {IERC165, IERC6900Module, IERC6900ValidationModule} from "@lattice/interfaces/external/IERC6900.sol";
import {ECDSA} from "@lattice/utils/libraries/ECDSA.sol";
import {SignatureChecker} from "@lattice/utils/libraries/SignatureChecker.sol";

/// @title SingleSignerValidation
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice A reference ERC-6900 validation module: one signer per `(account, entityId)`. Validates user
///         operations (ECDSA over the EIP-191 user-op-hash), runtime calls (the caller must be the signer), and
///         ERC-1271 signatures (against the digest the account hands it).
/// @dev A standalone module — invoked by the account via CALL, so it runs in its OWN storage (`msg.sender` is the
///      account; `signerOf[account][entityId]` is per-account). For ERC-1271, the Lattice account has ALREADY
///      bound the digest to its domain via ERC-7739 before calling {validateSignature}, so this module does a
///      plain signer check (no extra rehashing). Reference quality: minimal, no upgradeability, no enumeration.
contract SingleSignerValidation is IERC6900ValidationModule {
    /// @dev ERC-1271 return values.
    bytes4 internal constant _1271_MAGIC = 0x1626ba7e;
    bytes4 internal constant _1271_INVALID = 0xffffffff;
    /// @dev ERC-4337 authorizer field: success = 0, signature failure = 1.
    uint256 internal constant _SIG_OK = 0;
    uint256 internal constant _SIG_FAIL = 1;

    /// @notice The signer authorized for `(account, entityId)`.
    mapping(address account => mapping(uint32 entityId => address signer)) public signerOf;

    event SignerSet(address indexed account, uint32 indexed entityId, address signer);

    /// @notice The runtime caller is not the configured signer.
    error NotAuthorized(address account, uint32 entityId, address sender);

    /// @inheritdoc IERC6900Module
    /// @dev `data = abi.encode(uint32 entityId, address signer)`.
    function onInstall(bytes calldata data) external {
        (uint32 entityId, address signer) = abi.decode(data, (uint32, address));
        signerOf[msg.sender][entityId] = signer;
        emit SignerSet(msg.sender, entityId, signer);
    }

    /// @inheritdoc IERC6900Module
    /// @dev `data = abi.encode(uint32 entityId)`.
    function onUninstall(bytes calldata data) external {
        uint32 entityId = abi.decode(data, (uint32));
        delete signerOf[msg.sender][entityId];
    }

    /// @inheritdoc IERC6900ValidationModule
    function validateUserOp(uint32 entityId, PackedUserOperation calldata userOp, bytes32 userOpHash)
        external
        view
        returns (uint256)
    {
        return SignatureChecker.isValidSignatureNow(
            signerOf[msg.sender][entityId], ECDSA.toEthSignedMessageHash(userOpHash), userOp.signature
        )
            ? _SIG_OK
            : _SIG_FAIL;
    }

    /// @inheritdoc IERC6900ValidationModule
    function validateRuntime(address account, uint32 entityId, address sender, uint256, bytes calldata, bytes calldata)
        external
        view
    {
        if (sender != signerOf[account][entityId]) revert NotAuthorized(account, entityId, sender);
    }

    /// @inheritdoc IERC6900ValidationModule
    function validateSignature(address account, uint32 entityId, address, bytes32 hash, bytes calldata signature)
        external
        view
        returns (bytes4)
    {
        // `hash` is already ERC-7739 account-domain-bound; a plain signer check suffices.
        return SignatureChecker.isValidSignatureNow(signerOf[account][entityId], hash, signature)
            ? _1271_MAGIC
            : _1271_INVALID;
    }

    /// @inheritdoc IERC6900Module
    function moduleId() external pure returns (string memory) {
        return "lattice.single-signer-validation.1.0.0";
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC6900Module).interfaceId
            || interfaceId == type(IERC6900ValidationModule).interfaceId;
    }
}

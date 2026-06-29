// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {IERC20Permit} from "@lattice/interfaces/tokens/IERC20Permit.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {ECDSA} from "@lattice/utils/libraries/ECDSA.sol";
import {EIP712Lib} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC20PERMIT_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev 0x9d8ff7da is `type(IERC20Permit).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x9d8ff7da), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC20PERMIT_SLOT = 0x31d570801fe317e940436657728da1f6ff9fa61ca17b4eaff38ae98d162c1920;

/// @dev EIP-712 typehash for the Permit struct.
bytes32 constant PERMIT_TYPEHASH =
    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

/// @title ERC20PermitLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from OpenZeppelin (https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/token/ERC20/extensions/ERC20Permit.sol)
/// @notice Library implementing ERC-2612 permit-based approvals for ERC-20 tokens.
/// @dev No own storage — relies on EIP712 and Nonces slots already present.
library ERC20PermitLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the IERC20Permit interface for ERC-165 discovery.
    /// @dev No own storage to initialize. EIP712 and Nonces must be initialized separately.
    function __ERC20Permit_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IERC20Permit interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC20PERMIT_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           PERMIT OPERATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Sets approval via a signed permit.
    /// @param owner     The token owner granting the approval.
    /// @param spender   The address being approved.
    /// @param value     The allowance amount.
    /// @param deadline  The block.timestamp after which the signature is invalid.
    /// @param v         Signature component.
    /// @param r         Signature component.
    /// @param s         Signature component.
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        internal
    {
        if (block.timestamp > deadline) {
            revert IERC20Permit.ERC2612ExpiredSignature(deadline);
        }

        uint256 nonce = NoncesLib.useNonce(owner);

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonce, deadline));
        bytes32 hash = EIP712Lib.hashTypedDataV4(structHash);

        address signer = ECDSA.recover(hash, v, r, s);
        if (signer != owner) {
            revert IERC20Permit.ERC2612InvalidSigner(signer, owner);
        }

        ERC20Lib._approve(owner, spender, value, true);
    }
}

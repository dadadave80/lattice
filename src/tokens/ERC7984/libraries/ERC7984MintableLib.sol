// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {euint64, externalEuint64} from "@lattice/interfaces/external/fhevm/EncryptedTypes.sol";
import {FHEVMLib} from "@lattice/privacy/libraries/FHEVMLib.sol";
import {ERC7984Lib} from "@lattice/tokens/ERC7984/libraries/ERC7984Lib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev 0x1b4d3d0d is `type(IERC7984Mintable).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x1b4d3d0d), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC7984MINTABLE_SLOT = 0x61d79fd359ce91f5258997bc3b46cd751395217defe06fb10974f8bdf41dd3b9;

/// @dev Role authorized to mint confidential tokens to any account. Its admin is `DEFAULT_ADMIN_ROLE`.
bytes32 constant ERC7984_MINTER_ROLE = keccak256("ERC7984_MINTER_ROLE");

/// @title ERC7984MintableLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin Confidential Contracts (https://github.com/OpenZeppelin/openzeppelin-confidential-contracts)
/// @notice Role-gated confidential mint for the Lattice ERC-7984 (confidential fungible token), from
///         OpenZeppelin Confidential Contracts 0.5.3 `ERC7984Rwa.confidentialMint`. Adds no own storage: it writes
///         the {ERC7984Lib} supply and balances and reads the shared AccessControl roles.
/// @dev Differences from OpenZeppelin:
///      - Only the encrypted-input overload ships: no plaintext mint (it publishes every amount and aliases the
///        first supply handle), no proof-free `euint64` overload (it widens the self-call surface), no burn.
///      - {ERC7984Lib.guard} runs before the role check, so a self-call reverts
///        {IERC7984.ERC7984UnauthorizedCaller} even when the diamond holds the role.
///      - While the total supply is uninitialized, the amount is re-derived as `add(asEuint64(0), amount)`, so the
///        first supply handle is computed by the diamond and is never the minter's input handle. Re-deriving on
///        every mint lowers the per-transaction mint ceiling on a token with supply to 12, so it runs on the
///        first mint only.
///      Limits of that re-derivation: handles are deterministic per block and name no caller, so a minter that is
///      a contract can, in the same transaction as its own mint, recompute and persist access control list (ACL)
///      grants on handles whose value it chose (its minted handles, the supply handles its own consecutive mints
///      produce while it is the only supply writer, and a never-credited recipient's first balance) and publish
///      them. It cannot recompute a handle with an operand it is not allowed on. Separately, the minter is allowed
///      on `minted` and an overflowing mint mints zero, so each mint of a chosen amount `a` reveals whether the
///      total supply exceeds `2^64-1-a`; at most 64 mints recover the supply.
library ERC7984MintableLib {
    /// @notice Registers the IERC7984Mintable ERC-165 interface. Must be called inside a pre/postInitializer
    ///         block.
    function __ERC7984Mintable_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for IERC7984Mintable (id 0x1b4d3d0d).
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC7984MINTABLE_SLOT, true)
        }
    }

    /// @notice Mints `encryptedAmount`, proven by `inputProof`, to `to`; the caller must hold
    ///         {ERC7984_MINTER_ROLE}. An overflowing mint mints zero.
    /// @return minted The minted handle, allowed to the caller, `to` and the diamond.
    function confidentialMint(address to, externalEuint64 encryptedAmount, bytes calldata inputProof)
        internal
        returns (euint64 minted)
    {
        ERC7984Lib.guard();
        AccessControlLib.checkRole(ERC7984_MINTER_ROLE);
        euint64 amount = FHEVMLib.fromExternal(encryptedAmount, inputProof);
        if (!FHEVMLib.isInitialized(ERC7984Lib.confidentialTotalSupply())) {
            amount = FHEVMLib.add(FHEVMLib.asEuint64(0), amount);
        }
        minted = ERC7984Lib._mint(to, amount);
        FHEVMLib.allow(minted, msg.sender);
    }
}

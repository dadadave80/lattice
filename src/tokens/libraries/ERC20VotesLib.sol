// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ContextLib} from "@diamond/libraries/ContextLib.sol";
import {InitializableLib} from "@diamond/libraries/InitializableLib.sol";
import {NoncesLib} from "@lattice/utils/libraries/NoncesLib.sol";
import {ERC20Lib} from "@lattice/tokens/libraries/ERC20Lib.sol";
import {VotesLib} from "@lattice/governance/libraries/VotesLib.sol";
import {IERC20} from "@lattice/interfaces/IERC20.sol";
import {IERC20Votes} from "@lattice/interfaces/IERC20Votes.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev ERC-165 storage location (same across all Lattice modules).
/// `keccak256(abi.encode(uint256(keccak256("diamond.lib.storage.ERC165")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC20VOTES_ERC165_STORAGE_LOCATION =
    0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200;

/// @dev IERC20Votes has only errors (no functions), so type(IERC20Votes).interfaceId == 0x00000000.
/// `keccak256(abi.encode(bytes4(0x00000000), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC20VOTES_SLOT =
    0x290decd9548b62a8d60345a988386fc84ba6bc95484008f6362f93160ef3e563;

/// @title ERC20VotesLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Library adding checkpoint-based voting power to ERC-20 tokens.
/// @dev No own storage — uses ERC20 and Votes slots already present in Diamond storage.
///      Max token supply is capped at type(uint208).max so checkpoint values never overflow.
library ERC20VotesLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Marks ERC20Votes as initialized and registers the interface.
    /// @dev No own storage to initialize. ERC20, EIP712, Nonces, and Votes must be
    ///      initialized separately in the same initializer block.
    function __ERC20Votes_init() internal {
        bytes32 s = InitializableLib.initializableSlot();
        InitializableLib.checkInitializing(s);
        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IERC20Votes interface via ERC-165.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC20VOTES_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              SUPPLY CAP
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the maximum supply that can be checkpointed safely (type(uint208).max).
    function _maxSupply() internal pure returns (uint256) {
        return type(uint208).max;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           TOKEN OPERATIONS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice ERC-20 transfer with vote-checkpoint update.
    /// @dev Uses ContextLib.msgSender() for Diamond-compatible caller resolution.
    function transfer(address to, uint256 value) internal returns (bool) {
        address owner = ContextLib.msgSender();
        ERC20Lib._transfer(owner, to, value);
        VotesLib._transferVotingUnits(owner, to, value);
        return true;
    }

    /// @notice ERC-20 transferFrom with vote-checkpoint update.
    function transferFrom(address from, address to, uint256 value) internal returns (bool) {
        address spender = ContextLib.msgSender();
        ERC20Lib._spendAllowance(from, spender, value);
        ERC20Lib._transfer(from, to, value);
        VotesLib._transferVotingUnits(from, to, value);
        return true;
    }

    /// @notice Mints `value` tokens to `to`, enforcing the uint208 supply cap.
    /// @dev Follows OZ v5 order: update balances first, then check post-mint supply against cap.
    ///      This matches OZ ERC20Votes._update which calls super._update before reading totalSupply().
    function _mint(address to, uint256 value) internal {
        if (to == address(0)) revert IERC20.ERC20InvalidReceiver(address(0));
        // 1. Update balances and totalSupply first (matches OZ super._update order).
        ERC20Lib._update(address(0), to, value);
        // 2. Check post-mint supply against cap (reads committed totalSupply, not a pre-mint estimate).
        uint256 supply = ERC20Lib.totalSupply();
        uint256 cap = _maxSupply();
        if (supply > cap) {
            revert IERC20Votes.ERC20ExceededSafeSupply(supply, cap);
        }
        // 3. Update vote checkpoints.
        VotesLib._transferVotingUnits(address(0), to, value);
    }

    /// @notice Burns `value` tokens from `from`.
    function _burn(address from, uint256 value) internal {
        if (from == address(0)) revert IERC20.ERC20InvalidSender(address(0));
        ERC20Lib._update(from, address(0), value);
        VotesLib._transferVotingUnits(from, address(0), value);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         DELEGATION (VOTES-AWARE)
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Delegates votes from the caller to `delegatee`.
    /// @dev Reads caller's ERC-20 balance as voting units before delegating.
    function delegate(address delegatee) internal {
        address sender = ContextLib.msgSender();
        uint256 units = ERC20Lib.balanceOf(sender);
        VotesLib.delegate(delegatee, units);
    }

    /// @notice Delegates votes via an EIP-712 signature, using the signer's ERC-20 balance.
    /// @dev Two-step: first recover the signer (to read their balance), then delegate.
    ///      The nonce is consumed inside the second call via VotesLib.delegateBySig.
    function delegateBySig(address delegatee, uint256 nonce, uint256 expiry, uint8 v, bytes32 r, bytes32 s) internal {
        // Step 1: Recover the signer (validates expiry, but does NOT consume nonce yet).
        address signer = VotesLib._recoverDelegationSigner(delegatee, nonce, expiry, v, r, s);
        // Step 2: Read the signer's current ERC-20 balance as voting units.
        uint256 units = ERC20Lib.balanceOf(signer);
        // Step 3: Consume nonce and delegate with the correct voting weight.
        NoncesLib.useCheckedNonce(signer, nonce);
        VotesLib._delegate(signer, delegatee, units);
    }
}

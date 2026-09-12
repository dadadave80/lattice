// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {HederaResponseCodes} from "@lattice/interfaces/external/hedera/HederaResponseCodes.sol";
import {IHederaAccountService} from "@lattice/interfaces/external/hedera/IHederaAccountService.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

/// @dev 0x96c247cb is `type(IHASSignatureVerifier).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x96c247cb), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IHASSIGNATUREVERIFIER_SLOT =
    0x6abd9841429d5258dad1bcd53196ecd11f06899bbc66ddc8c90a5bb0ca520e26;

/// @dev The Hedera Account Service system contract (HIP-632 / HIP-906). No bytecode; never `delegatecall` it.
address constant HAS_SYSTEM_CONTRACT = 0x000000000000000000000000000000000000016a;

/// @title HASSignatureVerifierLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from hiero-ledger/hiero-contracts (https://github.com/hiero-ledger/hiero-contracts)
/// @notice Stateless wrapper around HAS `isAuthorizedRaw` / `isAuthorized`, shaped like {SignatureChecker}:
///         a `view` that returns `false` instead of bubbling the system contract's reverts. Plugs into
///         {AccountSignerLib.isValidSignatureNow} as the `HederaAccount` signer type.
/// @dev Both HAS functions are view-classified by the network, so `staticcall` is valid. Gas is the ecrecover
///      precompile cost (3,000) per simple key. The raw path rejects key lists / threshold keys by reverting —
///      use {isAuthorized} with a protobuf `SignatureMap` for those.
library HASSignatureVerifierLib {
    /// @notice Registers the IHASSignatureVerifier ERC-165 interface.
    /// @dev Must be called between `preInitializer` / `postInitializer`.
    function __HASSignatureVerifier_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for IHASSignatureVerifier.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IHASSIGNATUREVERIFIER_SLOT, true)
        }
    }

    /// @notice True if `signature` is valid over `messageHash` for `account`'s simple key; false otherwise
    ///         (including every system-contract revert).
    function isAuthorizedRaw(address account, bytes32 messageHash, bytes memory signature)
        internal
        view
        returns (bool authorized)
    {
        (bool ok, bytes memory ret) = HAS_SYSTEM_CONTRACT.staticcall(
            abi.encodeCall(IHederaAccountService.isAuthorizedRaw, (account, abi.encodePacked(messageHash), signature))
        );
        if (!ok || ret.length < 32) return false;
        return abi.decode(ret, (bool));
    }

    /// @notice True if `signatureMap` satisfies `account`'s key structure over `message`; false otherwise.
    function isAuthorized(address account, bytes memory message, bytes memory signatureMap)
        internal
        view
        returns (bool authorized)
    {
        (bool ok, bytes memory ret) = HAS_SYSTEM_CONTRACT.staticcall(
            abi.encodeCall(IHederaAccountService.isAuthorized, (account, message, signatureMap))
        );
        if (!ok || ret.length < 64) return false;
        (int64 code, bool result) = abi.decode(ret, (int64, bool));
        return code == HederaResponseCodes.SUCCESS && result;
    }
}

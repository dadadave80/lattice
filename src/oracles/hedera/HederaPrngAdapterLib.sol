// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IPrngSystemContract} from "@lattice/interfaces/external/hedera/IPrngSystemContract.sol";
import {IHederaPrngAdapter} from "@lattice/interfaces/oracles/IHederaPrngAdapter.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

/// @dev 0x8e848f42 is `type(IHederaPrngAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x8e848f42), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IHEDERAPRNGADAPTER_SLOT = 0xe34a308c0f52419d136ed1b5d11f586cf680db1cc128f8b2678f2b24615706b7;

/// @dev The PRNG system contract (HIP-351). No bytecode; never `delegatecall` or `staticcall` it.
address constant PRNG_SYSTEM_CONTRACT = 0x0000000000000000000000000000000000000169;

/// @title HederaPrngAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from hiero-ledger/hiero-contracts (https://github.com/hiero-ledger/hiero-contracts)
/// @notice Stateless wrapper around the PRNG system contract; `drawInRange` mirrors the upstream helper's
///         modulo reduction (bias is negligible for ranges far below 2^32 but is NOT uniform in general).
library HederaPrngAdapterLib {
    function __HederaPrngAdapter_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IHEDERAPRNGADAPTER_SLOT, true)
        }
    }

    function drawSeed() internal returns (bytes32 seed) {
        (bool ok, bytes memory ret) =
            PRNG_SYSTEM_CONTRACT.call(abi.encodeCall(IPrngSystemContract.getPseudorandomSeed, ()));
        if (!ok || ret.length < 32) revert IHederaPrngAdapter.HederaPrngCallFailed();
        seed = abi.decode(ret, (bytes32));
        emit IHederaPrngAdapter.HederaSeedDrawn(seed, msg.sender);
    }

    function drawInRange(uint32 lo, uint32 hi) internal returns (uint32 number) {
        if (lo >= hi) revert IHederaPrngAdapter.HederaPrngInvalidRange(lo, hi);
        uint256 seed = uint256(drawSeed());
        number = uint32(lo + (seed % (uint256(hi) - lo)));
    }
}

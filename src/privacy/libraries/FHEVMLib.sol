// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @notice Addresses of the three host contracts of a Fully Homomorphic Encryption Virtual Machine (FHEVM)
///         coprocessor deployment, in the field order of Zama's own configuration struct.
/// @dev Carries no storage-location annotation: it is only the layout of the shared coprocessor slot,
///      {FHEVMLib.CONFIG_SLOT}.
struct CoprocessorConfig {
    address acl;
    address executor;
    address kmsVerifier;
}

/// @title FHEVMLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from Zama FHEVM (https://github.com/zama-ai/fhevm)
/// @notice Thin host library for confidential (FHEVM) tokens. This section pins the coprocessor addresses
///         per supported chain and writes them into the shared configuration slot.
library FHEVMLib {
    //*//////////////////////////////////////////////////////////////////////////
    //                                 CONFIGURATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Zama's coprocessor configuration slot, `keccak256(abi.encode(uint256(keccak256("confidential.storage.config")) - 1)) & ~bytes32(uint256(0xff))`.
    ///      Sharing it keeps Zama's `FHE` library reading the addresses written here.
    bytes32 internal constant CONFIG_SLOT = 0x9e7b61f58c47dc699ac88507c4f5bb9f121c03808c5676a8078fe583e4649700;

    /// @notice The chain has no pinned coprocessor deployment.
    error FHEVMUnsupportedChain(uint256 chainId);

    /// @notice The slot already holds a coprocessor configuration that differs from this chain's pinned one.
    error FHEVMConflictingCoprocessor(address acl, address executor, address kmsVerifier);

    /// @dev Binds the coprocessor configuration to {CONFIG_SLOT}.
    function config() internal pure returns (CoprocessorConfig storage $) {
        bytes32 slot = CONFIG_SLOT;
        assembly ("memory-safe") {
            $.slot := slot
        }
    }

    /// @notice The pinned coprocessor addresses for `chainId`: Ethereum mainnet (1), Sepolia (11155111) and the
    ///         local test chain (31337). Chain 31337 is for local tests only.
    function hostsFor(uint256 chainId) internal pure returns (CoprocessorConfig memory) {
        if (chainId == 1) {
            return CoprocessorConfig({
                acl: 0xcA2E8f1F656CD25C01F05d0b243Ab1ecd4a8ffb6,
                executor: 0xD82385dADa1ae3E969447f20A3164F6213100e75,
                kmsVerifier: 0x77627828a55156b04Ac0DC0eb30467f1a552BB03
            });
        }
        if (chainId == 11155111) {
            return CoprocessorConfig({
                acl: 0xf0Ffdc93b7E186bC2f8CB3dAA75D86d1930A433D,
                executor: 0x92C920834Ec8941d2C77D188936E1f7A6f49c127,
                kmsVerifier: 0xbE0E383937d564D7FF0BC3b46c51f0bF8d5C311A
            });
        }
        if (chainId == 31337) {
            return CoprocessorConfig({
                acl: 0x50157CFfD6bBFA2DECe204a89ec419c23ef5755D,
                executor: 0xe3a9105a3a932253A70F126eb1E3b589C643dD24,
                kmsVerifier: 0x901F8942346f7AB3a01F6D7613119Bca447Bb030
            });
        }
        revert FHEVMUnsupportedChain(chainId);
    }

    /// @notice Writes the pinned configuration for `block.chainid` into {CONFIG_SLOT}.
    /// @dev An empty slot is written; an identical stored configuration is left untouched; anything else
    ///      reverts with {FHEVMConflictingCoprocessor} carrying the stored values.
    function setCoprocessorForChain() internal {
        CoprocessorConfig memory pinned = hostsFor(block.chainid);
        CoprocessorConfig storage $ = config();
        (address acl, address executor, address kmsVerifier) = ($.acl, $.executor, $.kmsVerifier);
        if (acl == address(0) && executor == address(0) && kmsVerifier == address(0)) {
            $.acl = pinned.acl;
            $.executor = pinned.executor;
            $.kmsVerifier = pinned.kmsVerifier;
        } else if (acl != pinned.acl || executor != pinned.executor || kmsVerifier != pinned.kmsVerifier) {
            revert FHEVMConflictingCoprocessor(acl, executor, kmsVerifier);
        }
    }
}

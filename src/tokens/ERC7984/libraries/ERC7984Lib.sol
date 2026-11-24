// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib} from "@diamond/libraries/DiamondLib.sol";
import {euint64} from "@lattice/interfaces/external/fhevm/EncryptedTypes.sol";
import {IERC7984} from "@lattice/interfaces/tokens/IERC7984.sol";
import {FHEVMLib} from "@lattice/privacy/libraries/FHEVMLib.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.ERC7984")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant ERC7984_STORAGE_SLOT = 0x42be1389dbc49dc1fd4c53bd478bd0e15a7bcc0e33c6883a051e5e4ca46dae00;

/// @dev 0x4958f2a4 is `type(IERC7984).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x4958f2a4), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IERC7984_SLOT = 0x05394c17de469f9a9f592c618d1e81bb7ac4870bb830dcd0e2bf9bb49b66747a;

/// @notice Storage struct for the ERC-7984 (confidential fungible token) module.
/// @custom:storage-location erc7201:lattice.storage.ERC7984
struct ERC7984Storage {
    mapping(address account => euint64) _balances;
    mapping(address holder => mapping(address spender => uint48)) _operators;
    euint64 _totalSupply;
    string _name;
    string _symbol;
    string _contractURI;
}

/// @title ERC7984Lib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Adapted for EIP-2535 from OpenZeppelin Confidential Contracts (https://github.com/OpenZeppelin/openzeppelin-confidential-contracts)
/// @notice Library implementing the ERC-7984 confidential fungible token over a Fully Homomorphic Encryption
///         Virtual Machine (FHEVM) coprocessor. All state lives in an ERC-7201 slot.
/// @dev Differences from OpenZeppelin Confidential Contracts 0.5.3 `ERC7984`:
///      - `__ERC7984_init` sets the metadata in the diamond's initializer, not a constructor, and pins the
///        coprocessor configuration for `block.chainid` ({FHEVMLib.setCoprocessorForChain}).
///      - `__ERC7984_init` refuses a diamond that routes any of the 15 diamond-caller selectors
///        ({requireNoDiamondCaller}) and a host that is an EIP-7702 delegated externally owned account (EOA)
///        ({requireNotDelegatedHost}). Both checks live here, so a composite initializer that calls
///        `__ERC7984_init` directly inherits them.
///      - `__ERC7984_init` registers {IERC7984} through ERC-165 (interface detection); that map slot,
///        {ERC165_MAP_IERC7984_SLOT}, doubles as the token's init marker.
library ERC7984Lib {
    /// @dev The 15 deny-list selectors, packed: functions through which the diamond calls a target its caller
    ///      chooses, or validates an ERC-1271 signature as itself. In order, by facet: AccessManager (1),
    ///      TimelockController (2), Governor (1), ERC7821Executor (1), ERC7579ModuleConfig (1), ERC6551Account (1),
    ///      ERC6900Executor (3), AggregatorExecAdapter (1), HSSAdapter (2), HSSAdapterRecovery (1), and
    ///      `isValidSignature` (ERC1271Signature, ERC6900Signature).
    bytes internal constant DENIED_SELECTORS =
        hex"1cff79cd134008d3e38335e52656227de9ae5c53d691c96451945447b61d27f634fcd5bef2680c0f8e845c306f5bfde8193704bb8670ca3b1626ba7e";

    //*//////////////////////////////////////////////////////////////////////////
    //                              STORAGE ACCESS
    //////////////////////////////////////////////////////////////////////////*//

    function erc7984Storage() internal pure returns (ERC7984Storage storage $) {
        assembly {
            $.slot := ERC7984_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INITIALIZATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Initializes the ERC-7984 module with its metadata and the coprocessor configuration.
    /// @dev Must be called inside a pre/postInitializer block. Mints nothing and makes no host call. A repeat
    ///      overwrites the metadata; a conflicting stored coprocessor configuration reverts.
    function __ERC7984_init(string memory name_, string memory symbol_, string memory contractURI_) internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        requireNoDiamondCaller();
        requireNotDelegatedHost();
        FHEVMLib.setCoprocessorForChain();

        ERC7984Storage storage $ = erc7984Storage();
        $._name = name_;
        $._symbol = symbol_;
        $._contractURI = contractURI_;

        registerInterface();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                           ERC-165 REGISTRATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers support for the IERC7984 interface via ERC-165, which also sets the init marker.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IERC7984_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                               HOST CHECKS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Reverts {IERC7984.ERC7984DiamondCallerInstalled} on the first deny-list selector the diamond routes.
    function requireNoDiamondCaller() internal view {
        bytes memory denied = DENIED_SELECTORS;
        uint256 count = denied.length / 4;
        for (uint256 i; i < count; ++i) {
            bytes4 sel;
            assembly ("memory-safe") {
                sel := mload(add(add(denied, 0x20), mul(i, 4)))
            }
            address facet = DiamondLib.diamondStorage().selectorToFacetAndPosition[sel].facetAddress;
            if (facet != address(0)) revert IERC7984.ERC7984DiamondCallerInstalled(sel, facet);
        }
    }

    /// @notice Reverts {IERC7984.ERC7984DelegatedHost} when this account's code starts with the EIP-7702
    ///         delegation designator `0xef0100`.
    /// @dev EIP-3541 forbids deployed code starting `0xef`, so only a delegated EOA matches. Its key can act as
    ///      the token without any facet.
    function requireNotDelegatedHost() internal view {
        bytes3 prefix;
        assembly ("memory-safe") {
            mstore(0x00, 0)
            extcodecopy(address(), 0x00, 0, 3)
            prefix := mload(0x00)
        }
        if (prefix == 0xef0100) revert IERC7984.ERC7984DelegatedHost(address(this));
    }
}

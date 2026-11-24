// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DiamondLib} from "@diamond/libraries/DiamondLib.sol";
import {ebool, euint64, externalEuint64} from "@lattice/interfaces/external/fhevm/EncryptedTypes.sol";
import {IERC7984, IERC7984Disclosure, IERC7984Receiver} from "@lattice/interfaces/tokens/IERC7984.sol";
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
///      - Entry guard: {guard} runs first on 10 entrypoints, the eight movers, {setOperator} and
///        {requestDiscloseEncryptedAmount}. A call from the diamond itself reverts
///        {IERC7984.ERC7984UnauthorizedCaller} with `address(this)`, so a self-call relay cannot spend the
///        diamond's access control list (ACL) grants; Multicall delegatecalls and keeps the outer sender. An unset
///        init marker then reverts {IERC7984.ERC7984NotInitialized}, so a diamond whose shared coprocessor slot
///        was written by another `FHE.sol` initializer, without `__ERC7984_init`, never goes live. Views and
///        {discloseEncryptedAmount}, which needs a valid Key Management Service (KMS) proof and writes no storage,
///        stay open.
///      - No receiving at the diamond: `_transfer` and `_mint` revert {IERC7984.ERC7984InvalidReceiver} with
///        `address(this)` next to the zero-address checks, since the entry guard would strand any balance the
///        diamond held.
///      - Library form: {decimals} is fixed at 6, the caller is `msg.sender` (no `_msgSender()`), nothing is
///        `virtual`, and the errors and events are declared on {IERC7984} and {IERC7984Disclosure}.
///        `ERC7984UtilsUnauthorizedUseOfEncryptedAmount` takes the receiver's `ebool` reply as `euint64`; both
///        encode as `bytes32`, so the selector is unchanged.
///      - Host calls go through the thin {FHEVMLib}, whose `tryIncrease`/`tryDecrease` are OpenZeppelin's
///        `FHESafeMath`.
///      Kept as in OpenZeppelin 0.5.3: zero-value transfers by anyone (the ERC requires their events), operators
///      receive transient access to the amounts they move, disclosure is not tied to a request and can be
///      replayed, `setOperator(self)` and `setOperator(address(0))` are inert, and there is no reentrancy guard.
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

    //*//////////////////////////////////////////////////////////////////////////
    //                               ENTRY GUARD
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Reverts {IERC7984.ERC7984UnauthorizedCaller} when the diamond calls itself, then
    ///         {IERC7984.ERC7984NotInitialized} when `__ERC7984_init` never ran (the init marker is unset).
    /// @dev Call it first in every entrypoint that acts on a caller-supplied handle, moves balances, sets
    ///      operators or requests disclosure, extensions included.
    function guard() internal view {
        if (msg.sender == address(this)) revert IERC7984.ERC7984UnauthorizedCaller(address(this));
        bool initialized;
        assembly ("memory-safe") {
            initialized := sload(ERC165_MAP_IERC7984_SLOT)
        }
        if (!initialized) revert IERC7984.ERC7984NotInitialized();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  VIEWS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the token name.
    function name() internal view returns (string memory) {
        return erc7984Storage()._name;
    }

    /// @notice Returns the token symbol.
    function symbol() internal view returns (string memory) {
        return erc7984Storage()._symbol;
    }

    /// @notice Returns the contract-level metadata URI.
    function contractURI() internal view returns (string memory) {
        return erc7984Storage()._contractURI;
    }

    /// @notice Returns the number of decimals, fixed at 6.
    function decimals() internal pure returns (uint8) {
        return 6;
    }

    /// @notice Returns the encrypted total supply handle.
    function confidentialTotalSupply() internal view returns (euint64) {
        return erc7984Storage()._totalSupply;
    }

    /// @notice Returns the encrypted balance handle of `account`.
    function confidentialBalanceOf(address account) internal view returns (euint64) {
        return erc7984Storage()._balances[account];
    }

    /// @notice Whether `spender` may move `holder`'s tokens: `holder` itself, or an operator whose `until` has not
    ///         passed.
    function isOperator(address holder, address spender) internal view returns (bool) {
        return holder == spender || block.timestamp <= erc7984Storage()._operators[holder][spender];
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                OPERATORS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Makes the caller's tokens movable by `operator` until `until`. Operators get transient access to the
    ///         amounts of the transfers they initiate.
    function setOperator(address operator, uint48 until) internal {
        guard();
        _setOperator(msg.sender, operator, until);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 MOVERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Transfers an externally encrypted amount, proven by `inputProof`, from the caller to `to`.
    function confidentialTransfer(address to, externalEuint64 encryptedAmount, bytes calldata inputProof)
        internal
        returns (euint64)
    {
        guard();
        return _transfer(msg.sender, to, FHEVMLib.fromExternal(encryptedAmount, inputProof));
    }

    /// @notice Transfers the `amount` handle, which the caller must be allowed to use, from the caller to `to`.
    function confidentialTransfer(address to, euint64 amount) internal returns (euint64) {
        guard();
        _requireAllowed(amount);
        return _transfer(msg.sender, to, amount);
    }

    /// @notice Operator transfer of an externally encrypted amount from `from` to `to`.
    function confidentialTransferFrom(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof
    ) internal returns (euint64 transferred) {
        guard();
        _requireOperator(from);
        transferred = _transfer(from, to, FHEVMLib.fromExternal(encryptedAmount, inputProof));
        FHEVMLib.allowTransient(transferred, msg.sender);
    }

    /// @notice Operator transfer of the `amount` handle, which the caller must be allowed to use.
    function confidentialTransferFrom(address from, address to, euint64 amount) internal returns (euint64 transferred) {
        guard();
        _requireAllowed(amount);
        _requireOperator(from);
        transferred = _transfer(from, to, amount);
        FHEVMLib.allowTransient(transferred, msg.sender);
    }

    /// @notice {confidentialTransfer} with an input proof, then calls the receiver with `data`.
    function confidentialTransferAndCall(
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof,
        bytes calldata data
    ) internal returns (euint64) {
        guard();
        return _transferAndCall(msg.sender, to, FHEVMLib.fromExternal(encryptedAmount, inputProof), data);
    }

    /// @notice {confidentialTransfer} with a handle, then calls the receiver with `data`.
    function confidentialTransferAndCall(address to, euint64 amount, bytes calldata data) internal returns (euint64) {
        guard();
        _requireAllowed(amount);
        return _transferAndCall(msg.sender, to, amount, data);
    }

    /// @notice {confidentialTransferFrom} with an input proof, then calls the receiver with `data`.
    function confidentialTransferFromAndCall(
        address from,
        address to,
        externalEuint64 encryptedAmount,
        bytes calldata inputProof,
        bytes calldata data
    ) internal returns (euint64) {
        guard();
        _requireOperator(from);
        return _transferAndCall(from, to, FHEVMLib.fromExternal(encryptedAmount, inputProof), data);
    }

    /// @notice {confidentialTransferFrom} with a handle, then calls the receiver with `data`.
    function confidentialTransferFromAndCall(address from, address to, euint64 amount, bytes calldata data)
        internal
        returns (euint64)
    {
        guard();
        _requireAllowed(amount);
        _requireOperator(from);
        return _transferAndCall(from, to, amount, data);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                DISCLOSURE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Makes `encryptedAmount` publicly decryptable and emits {IERC7984Disclosure.AmountDiscloseRequested}.
    /// @dev Both the caller and the diamond must be allowed to use `encryptedAmount`.
    function requestDiscloseEncryptedAmount(euint64 encryptedAmount) internal {
        guard();
        _requireAllowed(encryptedAmount);
        FHEVMLib.makePubliclyDecryptable(encryptedAmount);
        emit IERC7984Disclosure.AmountDiscloseRequested(encryptedAmount, msg.sender);
    }

    /// @notice Verifies a KMS public decryption proof of `encryptedAmount` to `cleartextAmount` and emits
    ///         {IERC7984.AmountDisclosed}.
    /// @dev Not tied to a prior {requestDiscloseEncryptedAmount}.
    function discloseEncryptedAmount(euint64 encryptedAmount, uint64 cleartextAmount, bytes calldata decryptionProof)
        internal
    {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = euint64.unwrap(encryptedAmount);
        FHEVMLib.checkSignatures(handles, abi.encode(cleartextAmount), decryptionProof);
        emit IERC7984.AmountDisclosed(encryptedAmount, cleartextAmount);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                             INTERNAL MOVERS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Mints up to `amount` to `to`; the supply never overflows, and an overflowing mint mints zero.
    function _mint(address to, euint64 amount) internal returns (euint64 transferred) {
        if (to == address(0)) revert IERC7984.ERC7984InvalidReceiver(address(0));
        if (to == address(this)) revert IERC7984.ERC7984InvalidReceiver(address(this));
        return _update(address(0), to, amount);
    }

    /// @notice Burns up to `amount` from `from`; a burn above the balance burns zero.
    function _burn(address from, euint64 amount) internal returns (euint64 transferred) {
        if (from == address(0)) revert IERC7984.ERC7984InvalidSender(address(0));
        return _update(from, address(0), amount);
    }

    function _setOperator(address holder, address operator, uint48 until) private {
        erc7984Storage()._operators[holder][operator] = until;
        emit IERC7984.OperatorSet(holder, operator, until);
    }

    function _transfer(address from, address to, euint64 amount) private returns (euint64 transferred) {
        if (from == address(0)) revert IERC7984.ERC7984InvalidSender(address(0));
        if (to == address(0)) revert IERC7984.ERC7984InvalidReceiver(address(0));
        if (to == address(this)) revert IERC7984.ERC7984InvalidReceiver(address(this));
        return _update(from, to, amount);
    }

    /// @dev Transfers `amount` from `from` to `to`, calls the receiver and refunds `sent` unless it replies an
    ///      encrypted true. Returns `sent - refund`, transiently allowed to the caller only. The refund is
    ///      best-effort: a receiver that spends during the callback and replies false keeps the tokens.
    function _transferAndCall(address from, address to, euint64 amount, bytes calldata data)
        private
        returns (euint64 transferred)
    {
        euint64 sent = _transfer(from, to, amount);
        ebool success = _checkOnTransferReceived(msg.sender, from, to, sent, data);
        euint64 refund = _update(to, from, FHEVMLib.select(success, FHEVMLib.asEuint64(0), sent));
        transferred = FHEVMLib.sub(sent, refund);
        FHEVMLib.allowTransient(transferred, msg.sender);
    }

    /// @dev Moves up to `amount` from `from` to `to`, minting or burning when either is the zero address, and
    ///      emits {IERC7984.ConfidentialTransfer} with the amount actually moved.
    function _update(address from, address to, euint64 amount) private returns (euint64 transferred) {
        ERC7984Storage storage $ = erc7984Storage();
        ebool success;
        euint64 ptr;

        if (from == address(0)) {
            (success, ptr) = FHEVMLib.tryIncrease($._totalSupply, amount);
            FHEVMLib.allowThis(ptr);
            $._totalSupply = ptr;
        } else {
            euint64 fromBalance = $._balances[from];
            (success, ptr) = FHEVMLib.tryDecrease(fromBalance, amount);
            FHEVMLib.allowThis(ptr);
            FHEVMLib.allow(ptr, from);
            $._balances[from] = ptr;
        }

        transferred = FHEVMLib.select(success, amount, FHEVMLib.asEuint64(0));

        if (to == address(0)) {
            ptr = FHEVMLib.sub($._totalSupply, transferred);
            FHEVMLib.allowThis(ptr);
            $._totalSupply = ptr;
        } else {
            ptr = FHEVMLib.add($._balances[to], transferred);
            FHEVMLib.allowThis(ptr);
            FHEVMLib.allow(ptr, to);
            $._balances[to] = ptr;
        }

        if (from != address(0)) FHEVMLib.allow(transferred, from);
        if (to != address(0)) FHEVMLib.allow(transferred, to);
        FHEVMLib.allowThis(transferred);
        emit IERC7984.ConfidentialTransfer(from, to, transferred);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            RECEIVER CALLBACK
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev OpenZeppelin `ERC7984Utils.checkOnTransferReceived`. A receiver with no code accepts. A receiver with
    ///      code must reply an encrypted boolean it may use itself, or the uninitialized handle (treated as false);
    ///      a revert with no data is {IERC7984.ERC7984InvalidReceiver}, and any other revert bubbles up unchanged.
    function _checkOnTransferReceived(address operator, address from, address to, euint64 amount, bytes calldata data)
        private
        returns (ebool)
    {
        if (to.code.length == 0) return FHEVMLib.asEbool(true);
        try IERC7984Receiver(to).onConfidentialTransferReceived(operator, from, amount, data) returns (ebool retval) {
            if (FHEVMLib.isInitialized(retval) && !FHEVMLib.isAllowed(retval, to)) {
                revert IERC7984.ERC7984UtilsUnauthorizedUseOfEncryptedAmount(euint64.wrap(ebool.unwrap(retval)), to);
            }
            return retval;
        } catch (bytes memory reason) {
            if (reason.length == 0) revert IERC7984.ERC7984InvalidReceiver(to);
            assembly ("memory-safe") {
                revert(add(reason, 0x20), mload(reason))
            }
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CHECKS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Security requirement 1: the caller must be allowed to use a caller-supplied `amount` handle.
    function _requireAllowed(euint64 amount) private view {
        if (!FHEVMLib.isAllowed(amount, msg.sender)) {
            revert IERC7984.ERC7984UnauthorizedUseOfEncryptedAmount(amount, msg.sender);
        }
    }

    function _requireOperator(address from) private view {
        if (!isOperator(from, msg.sender)) revert IERC7984.ERC7984UnauthorizedSpender(from, msg.sender);
    }
}

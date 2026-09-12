// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {HederaResponseCodes} from "@lattice/interfaces/external/hedera/HederaResponseCodes.sol";
import {IHRC719} from "@lattice/interfaces/external/hedera/IHRC719.sol";
import {IHederaTokenService} from "@lattice/interfaces/external/hedera/IHederaTokenService.sol";
import {IHTSAdapter} from "@lattice/interfaces/tokens/IHTSAdapter.sol";
import {EnumerableSet} from "@lattice/utils/libraries/EnumerableSet.sol";
import {InitializableLib} from "@lattice/utils/libraries/InitializableLib.sol";

//*//////////////////////////////////////////////////////////////////////////
//                                  STORAGE
//////////////////////////////////////////////////////////////////////////*//

/// @dev `keccak256(abi.encode(uint256(keccak256("lattice.storage.HTSAdapter")) - 1)) & ~bytes32(uint256(0xff))`.
bytes32 constant HTS_ADAPTER_STORAGE_SLOT = 0x91b64afeea686e80e2bda212862c0850ed3389288ac3f914b1109537d6e3f500;

/// @dev 0x37ae8968 is `type(IHTSAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0x37ae8968), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_IHTSADAPTER_SLOT = 0x0785670462ca582bde40afa31cf7989a7c25557d842b1003652c1ca6b4044d81;

/// @dev Role allowed to associate / dissociate the diamond and create tokens it will treasury.
bytes32 constant HTS_MANAGER_ROLE = keccak256("HTS_MANAGER_ROLE");
/// @dev Role allowed to move the diamond's HTS balances and mint / burn its tokens.
bytes32 constant HTS_OPERATOR_ROLE = keccak256("HTS_OPERATOR_ROLE");

/// @dev The Hedera Token Service system contract (HIP-206). Has no bytecode; must never be `delegatecall`ed.
address constant HTS_SYSTEM_CONTRACT = 0x0000000000000000000000000000000000000167;

/// @dev HTS `TokenKey.keyType` bits: admin (1) | supply (16).
uint256 constant HTS_KEY_ADMIN = 1;
uint256 constant HTS_KEY_SUPPLY = 16;
/// @dev Default auto-renew period (90 days) — the value hiero-contracts' helper injects when none is given.
int64 constant HTS_DEFAULT_AUTO_RENEW_PERIOD = 7_776_000;

/// @notice ERC-7201 namespaced storage for HTSAdapter.
/// @custom:storage-location erc7201:lattice.storage.HTSAdapter
struct HTSAdapterStorage {
    /// @notice HTS tokens created by this diamond (treasury + key holder). APPEND-ONLY.
    EnumerableSet.AddressSet _createdTokens;
}

/// @title HTSAdapterLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from hiero-ledger/hiero-contracts (https://github.com/hiero-ledger/hiero-contracts)
/// @notice Logic + ERC-7201 storage for the diamond's Hedera Token Service account: associations, transfers of
///         its own balances, and creation / mint / burn of tokens it holds the keys to.
/// @dev All system-contract calls are plain `call`s from the diamond (a facet `delegatecall` frame): HTS sees
///      `msg.sender == diamond`, so the diamond's account is the one whose associations, balances, allowances,
///      and keys are checked. Because that frame IS a delegatecall frame, HTS activates only
///      `delegatableContractId` keys for the diamond — never `contractId` keys — so every key this library
///      sets on a created token uses `delegatableContractId = address(this)`.
library HTSAdapterLib {
    using EnumerableSet for EnumerableSet.AddressSet;

    //*//////////////////////////////////////////////////////////////////////////
    //                                  STORAGE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Returns the ERC-7201 storage struct for HTSAdapter.
    function htsAdapterStorage() internal pure returns (HTSAdapterStorage storage $) {
        assembly {
            $.slot := HTS_ADAPTER_STORAGE_SLOT
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                              INITIALISATION
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Registers the IHTSAdapter ERC-165 interface.
    /// @dev Must be called between `preInitializer` / `postInitializer`.
    function __HTSAdapter_init() internal {
        InitializableLib.checkInitializing(InitializableLib.initializableSlot());
        registerInterface();
    }

    /// @notice Writes `true` to the ERC-165 map slot for IHTSAdapter.
    function registerInterface() internal {
        assembly ("memory-safe") {
            sstore(ERC165_MAP_IHTSADAPTER_SLOT, true)
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   READS
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice True if the diamond is associated with `token` (HIP-719 facade on the token address).
    function isAssociated(address token) internal view returns (bool) {
        return IHRC719(token).isAssociated();
    }

    /// @notice True if `token` is an HTS token.
    function isHTSToken(address token) internal view returns (bool isToken) {
        bytes memory ret = _staticcall(abi.encodeCall(IHederaTokenService.isToken, (token)));
        (int64 code, bool result) = abi.decode(ret, (int64, bool));
        return code == HederaResponseCodes.SUCCESS && result;
    }

    /// @notice HTS token type (0 fungible, 1 non-fungible); reverts {HTSNotAToken} for a non-token.
    function htsTokenType(address token) internal view returns (int32 tokenType) {
        bytes memory ret = _staticcall(abi.encodeCall(IHederaTokenService.getTokenType, (token)));
        int64 code;
        (code, tokenType) = abi.decode(ret, (int64, int32));
        if (code != HederaResponseCodes.SUCCESS) revert IHTSAdapter.HTSNotAToken(token);
    }

    /// @notice The HTS tokens created by this diamond.
    function createdTokens() internal view returns (address[] memory) {
        return htsAdapterStorage()._createdTokens.values();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                   ADMIN
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Associates the diamond with `token`. Caller must hold HTS_MANAGER_ROLE.
    function associateToken(address token) internal {
        AccessControlLib.checkRole(HTS_MANAGER_ROLE);
        int64 code = _callForCode(abi.encodeCall(IHederaTokenService.associateToken, (address(this), token)));
        _check(IHederaTokenService.associateToken.selector, code, token, address(this));
        emit IHTSAdapter.HTSTokenAssociated(token);
    }

    /// @notice Dissociates the diamond from `token`. Caller must hold HTS_MANAGER_ROLE.
    function dissociateToken(address token) internal {
        AccessControlLib.checkRole(HTS_MANAGER_ROLE);
        int64 code = _callForCode(abi.encodeCall(IHederaTokenService.dissociateToken, (address(this), token)));
        _check(IHederaTokenService.dissociateToken.selector, code, token, address(this));
        emit IHTSAdapter.HTSTokenDissociated(token);
    }

    /// @notice Creates a fungible token treasuried and key-controlled by the diamond. Caller must hold
    ///         HTS_MANAGER_ROLE. Forwards `msg.value` as the creation fee.
    function createFungibleToken(
        string calldata name,
        string calldata symbol,
        string calldata memo,
        int32 decimals,
        int64 initialSupply,
        int64 maxSupply
    ) internal returns (address token) {
        AccessControlLib.checkRole(HTS_MANAGER_ROLE);
        if (initialSupply < 0 || maxSupply < 0 || (maxSupply != 0 && initialSupply > maxSupply)) {
            revert IHTSAdapter.HTSInvalidAmount();
        }
        IHederaTokenService.HederaToken memory t = _tokenTemplate(name, symbol, memo, maxSupply);
        (bool ok, bytes memory ret) = HTS_SYSTEM_CONTRACT.call{value: msg.value}(
            abi.encodeCall(IHederaTokenService.createFungibleToken, (t, initialSupply, decimals))
        );
        token = _decodeCreate(IHederaTokenService.createFungibleToken.selector, ok, ret);
        htsAdapterStorage()._createdTokens.add(token);
        emit IHTSAdapter.HTSTokenCreated(token, true);
    }

    /// @notice Creates a non-fungible token treasuried and key-controlled by the diamond. Caller must hold
    ///         HTS_MANAGER_ROLE. Forwards `msg.value` as the creation fee.
    function createNonFungibleToken(string calldata name, string calldata symbol, string calldata memo, int64 maxSupply)
        internal
        returns (address token)
    {
        AccessControlLib.checkRole(HTS_MANAGER_ROLE);
        if (maxSupply < 0) revert IHTSAdapter.HTSInvalidAmount();
        IHederaTokenService.HederaToken memory t = _tokenTemplate(name, symbol, memo, maxSupply);
        (bool ok, bytes memory ret) =
            HTS_SYSTEM_CONTRACT.call{value: msg.value}(abi.encodeCall(IHederaTokenService.createNonFungibleToken, (t)));
        token = _decodeCreate(IHederaTokenService.createNonFungibleToken.selector, ok, ret);
        htsAdapterStorage()._createdTokens.add(token);
        emit IHTSAdapter.HTSTokenCreated(token, false);
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  OPERATOR
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice Transfers `amount` of `token` from the diamond to `to`. Caller must hold HTS_OPERATOR_ROLE.
    function transferToken(address token, address to, int64 amount) internal {
        AccessControlLib.checkRole(HTS_OPERATOR_ROLE);
        if (amount <= 0) revert IHTSAdapter.HTSInvalidAmount();
        int64 code = _callForCode(abi.encodeCall(IHederaTokenService.transferToken, (token, address(this), to, amount)));
        _check(IHederaTokenService.transferToken.selector, code, token, address(this));
        emit IHTSAdapter.HTSTokenTransferred(token, address(this), to, amount);
    }

    /// @notice Spends the allowance `from` granted the diamond: moves `amount` of `token` from `from` to `to`.
    ///         Caller must hold HTS_OPERATOR_ROLE.
    function transferTokenFrom(address token, address from, address to, int64 amount) internal {
        AccessControlLib.checkRole(HTS_OPERATOR_ROLE);
        if (amount <= 0) revert IHTSAdapter.HTSInvalidAmount();
        int64 code =
            _callForCode(abi.encodeCall(IHederaTokenService.transferFrom, (token, from, to, uint256(uint64(amount)))));
        _check(IHederaTokenService.transferFrom.selector, code, token, from);
        emit IHTSAdapter.HTSTokenTransferred(token, from, to, amount);
    }

    /// @notice Transfers NFT `serialNumber` of `token` from the diamond to `to`. Caller must hold HTS_OPERATOR_ROLE.
    function transferNFT(address token, address to, int64 serialNumber) internal {
        AccessControlLib.checkRole(HTS_OPERATOR_ROLE);
        int64 code =
            _callForCode(abi.encodeCall(IHederaTokenService.transferNFT, (token, address(this), to, serialNumber)));
        _check(IHederaTokenService.transferNFT.selector, code, token, address(this));
        emit IHTSAdapter.HTSTokenTransferred(token, address(this), to, 1);
    }

    /// @notice Mints to the treasury (the diamond). Caller must hold HTS_OPERATOR_ROLE.
    function mintToken(address token, int64 amount, bytes[] calldata metadata)
        internal
        returns (int64 newTotalSupply, int64[] memory serialNumbers)
    {
        AccessControlLib.checkRole(HTS_OPERATOR_ROLE);
        if (amount < 0) revert IHTSAdapter.HTSInvalidAmount();
        (bool ok, bytes memory ret) =
            HTS_SYSTEM_CONTRACT.call(abi.encodeCall(IHederaTokenService.mintToken, (token, amount, metadata)));
        int64 code = HederaResponseCodes.UNKNOWN;
        if (ok) (code, newTotalSupply, serialNumbers) = abi.decode(ret, (int64, int64, int64[]));
        _check(IHederaTokenService.mintToken.selector, code, token, address(this));
        emit IHTSAdapter.HTSTokenMinted(token, amount == 0 ? int64(int256(metadata.length)) : amount, newTotalSupply);
    }

    /// @notice Burns from the treasury (the diamond). Caller must hold HTS_OPERATOR_ROLE.
    function burnToken(address token, int64 amount, int64[] calldata serialNumbers)
        internal
        returns (int64 newTotalSupply)
    {
        AccessControlLib.checkRole(HTS_OPERATOR_ROLE);
        if (amount < 0) revert IHTSAdapter.HTSInvalidAmount();
        (bool ok, bytes memory ret) =
            HTS_SYSTEM_CONTRACT.call(abi.encodeCall(IHederaTokenService.burnToken, (token, amount, serialNumbers)));
        int64 code = HederaResponseCodes.UNKNOWN;
        if (ok) (code, newTotalSupply) = abi.decode(ret, (int64, int64));
        _check(IHederaTokenService.burnToken.selector, code, token, address(this));
        emit IHTSAdapter.HTSTokenBurned(
            token, amount == 0 ? int64(int256(serialNumbers.length)) : amount, newTotalSupply
        );
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                 INTERNALS
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Builds the create-token template: diamond = treasury + auto-renew account, admin + supply keys as
    ///      `delegatableContractId(diamond)` (the ONLY key form a facet call can activate), 90-day auto-renew.
    function _tokenTemplate(string calldata name, string calldata symbol, string calldata memo, int64 maxSupply)
        private
        view
        returns (IHederaTokenService.HederaToken memory t)
    {
        IHederaTokenService.TokenKey[] memory keys = new IHederaTokenService.TokenKey[](1);
        keys[0].keyType = HTS_KEY_ADMIN | HTS_KEY_SUPPLY;
        keys[0].key.delegatableContractId = address(this);
        t.name = name;
        t.symbol = symbol;
        t.memo = memo;
        t.treasury = address(this);
        t.tokenSupplyType = maxSupply != 0; // false = INFINITE, true = FINITE
        t.maxSupply = maxSupply;
        t.tokenKeys = keys;
        t.expiry.autoRenewAccount = address(this);
        t.expiry.autoRenewPeriod = HTS_DEFAULT_AUTO_RENEW_PERIOD;
    }

    /// @dev Decodes a `create*` return; maps a failed frame to UNKNOWN like hiero-contracts' helper does.
    function _decodeCreate(bytes4 selector, bool ok, bytes memory ret) private pure returns (address token) {
        int64 code = HederaResponseCodes.UNKNOWN;
        if (ok) (code, token) = abi.decode(ret, (int64, address));
        _check(selector, code, token, address(0));
    }

    /// @dev Plain `call` into HTS returning the response code (UNKNOWN when the frame itself failed).
    function _callForCode(bytes memory data) private returns (int64 code) {
        (bool ok, bytes memory ret) = HTS_SYSTEM_CONTRACT.call(data);
        code = ok ? abi.decode(ret, (int64)) : HederaResponseCodes.UNKNOWN;
    }

    /// @dev `staticcall` into HTS for the view-classified getters; a halted frame surfaces as {HTSCallFailed}.
    function _staticcall(bytes memory data) private view returns (bytes memory ret) {
        bool ok;
        (ok, ret) = HTS_SYSTEM_CONTRACT.staticcall(data);
        if (!ok || ret.length < 64) revert IHTSAdapter.HTSCallFailed(bytes4(data), HederaResponseCodes.UNKNOWN);
    }

    /// @dev Maps an HTS response code to the typed error for `selector`; no-op on SUCCESS.
    function _check(bytes4 selector, int64 code, address token, address account) private pure {
        if (code == HederaResponseCodes.SUCCESS) return;
        if (code == HederaResponseCodes.TOKEN_NOT_ASSOCIATED_TO_ACCOUNT) {
            revert IHTSAdapter.HTSTokenNotAssociated(token, account);
        }
        if (code == HederaResponseCodes.TOKEN_ALREADY_ASSOCIATED_TO_ACCOUNT) {
            revert IHTSAdapter.HTSTokenAlreadyAssociated(token, account);
        }
        if (
            code == HederaResponseCodes.INSUFFICIENT_TOKEN_BALANCE
                || code == HederaResponseCodes.INSUFFICIENT_ACCOUNT_BALANCE
        ) revert IHTSAdapter.HTSInsufficientBalance(token, account);
        if (code == HederaResponseCodes.TRANSACTION_REQUIRES_ZERO_TOKEN_BALANCES) {
            revert IHTSAdapter.HTSNonZeroBalance(token, account);
        }
        if (
            code == HederaResponseCodes.INVALID_SIGNATURE
                || code == HederaResponseCodes.INVALID_FULL_PREFIX_SIGNATURE_FOR_PRECOMPILE
        ) revert IHTSAdapter.HTSKeyNotActive(token);
        if (code == HederaResponseCodes.TOKEN_HAS_NO_SUPPLY_KEY) revert IHTSAdapter.HTSTokenNoSupplyKey(token);
        if (code == HederaResponseCodes.TOKEN_MAX_SUPPLY_REACHED) revert IHTSAdapter.HTSMaxSupplyReached(token);
        if (code == HederaResponseCodes.TOKEN_IS_PAUSED) revert IHTSAdapter.HTSTokenPaused(token);
        if (code == HederaResponseCodes.ACCOUNT_FROZEN_FOR_TOKEN) revert IHTSAdapter.HTSAccountFrozen(token, account);
        if (code == HederaResponseCodes.ACCOUNT_KYC_NOT_GRANTED_FOR_TOKEN) {
            revert IHTSAdapter.HTSKycNotGranted(token, account);
        }
        if (
            code == HederaResponseCodes.SPENDER_DOES_NOT_HAVE_ALLOWANCE
                || code == HederaResponseCodes.AMOUNT_EXCEEDS_ALLOWANCE
        ) revert IHTSAdapter.HTSAllowanceExceeded(token, account);
        if (code == HederaResponseCodes.INSUFFICIENT_GAS) revert IHTSAdapter.HTSInsufficientGas();
        if (code == HederaResponseCodes.INVALID_TOKEN_ID) revert IHTSAdapter.HTSNotAToken(token);
        if (
            code == HederaResponseCodes.INVALID_TOKEN_MINT_AMOUNT
                || code == HederaResponseCodes.INVALID_TOKEN_BURN_AMOUNT
                || code == HederaResponseCodes.INVALID_TOKEN_NFT_SERIAL_NUMBER
        ) revert IHTSAdapter.HTSInvalidAmount();
        revert IHTSAdapter.HTSCallFailed(selector, code);
    }
}

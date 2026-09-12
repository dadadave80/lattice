// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {HederaResponseCodes} from "@lattice/interfaces/external/hedera/HederaResponseCodes.sol";
import {IHRC719} from "@lattice/interfaces/external/hedera/IHRC719.sol";
import {IHederaTokenService} from "@lattice/interfaces/external/hedera/IHederaTokenService.sol";

/// @notice Minimal HIP-719 token facade stand-in deployed BY the mock system contract at every created token
///         address: `isAssociated()` answers for the caller, like the real proxy bytecode does.
contract MockHRC719Token is IHRC719 {
    MockHederaTokenService immutable hts;

    constructor() {
        hts = MockHederaTokenService(payable(msg.sender));
    }

    function associate() external returns (uint256) {
        return uint256(uint64(hts.associateToken(msg.sender, address(this))));
    }

    function dissociate() external returns (uint256) {
        return uint256(uint64(hts.dissociateToken(msg.sender, address(this))));
    }

    function isAssociated() external view returns (bool) {
        return hts.associated(msg.sender, address(this));
    }
}

/// @title MockHederaTokenService
/// @notice `vm.etch`-able stand-in for the HTS system contract at 0x167. Returns RESPONSE CODES (never reverts)
///         like the real system contract, keeps just enough state (associations, balances, supply key holder)
///         to exercise the adapter's happy paths, and lets a test force any code for the next call of a selector.
/// @dev Must not rely on constructor state: an etched contract starts with empty storage. Token addresses are
///      real contracts (MockHRC719Token) so the HIP-719 `isAssociated()` facade path can be unit-tested.
contract MockHederaTokenService {
    mapping(address account => mapping(address token => bool)) public associated;
    mapping(address token => mapping(address account => int64)) public balanceOf;
    mapping(address token => address) public supplyKeyHolder;
    mapping(address token => int64) public totalSupply;
    mapping(address token => int32) public tokenType; // 0 FT, 1 NFT
    mapping(address token => bool) public tokenExists;
    mapping(bytes4 selector => int64) public forcedCode;
    address[] public tokens;

    /// @notice Force the next call of `selector` to return `code` (0 clears).
    function force(bytes4 selector, int64 code) external {
        forcedCode[selector] = code;
    }

    function _consumeForced(bytes4 selector) private returns (int64 code) {
        code = forcedCode[selector];
        if (code != 0) delete forcedCode[selector];
    }

    // ---- associations ----
    function associateToken(address account, address token) public returns (int64) {
        int64 forced = _consumeForced(IHederaTokenService.associateToken.selector);
        if (forced != 0) return forced;
        if (!tokenExists[token]) return HederaResponseCodes.INVALID_TOKEN_ID;
        if (associated[account][token]) return HederaResponseCodes.TOKEN_ALREADY_ASSOCIATED_TO_ACCOUNT;
        associated[account][token] = true;
        return HederaResponseCodes.SUCCESS;
    }

    function dissociateToken(address account, address token) public returns (int64) {
        int64 forced = _consumeForced(IHederaTokenService.dissociateToken.selector);
        if (forced != 0) return forced;
        if (!associated[account][token]) return HederaResponseCodes.TOKEN_NOT_ASSOCIATED_TO_ACCOUNT;
        if (balanceOf[token][account] != 0) return HederaResponseCodes.TRANSACTION_REQUIRES_ZERO_TOKEN_BALANCES;
        associated[account][token] = false;
        return HederaResponseCodes.SUCCESS;
    }

    // ---- transfers (sender authorization = msg.sender is the sender, like a contract moving its own funds) ----
    function transferToken(address token, address sender, address receiver, int64 amount) external returns (int64) {
        int64 forced = _consumeForced(IHederaTokenService.transferToken.selector);
        if (forced != 0) return forced;
        if (!tokenExists[token]) return HederaResponseCodes.INVALID_TOKEN_ID;
        if (sender != msg.sender) return HederaResponseCodes.INVALID_FULL_PREFIX_SIGNATURE_FOR_PRECOMPILE;
        if (!associated[sender][token]) return HederaResponseCodes.TOKEN_NOT_ASSOCIATED_TO_ACCOUNT;
        if (!associated[receiver][token]) return HederaResponseCodes.TOKEN_NOT_ASSOCIATED_TO_ACCOUNT;
        if (balanceOf[token][sender] < amount) return HederaResponseCodes.INSUFFICIENT_TOKEN_BALANCE;
        balanceOf[token][sender] -= amount;
        balanceOf[token][receiver] += amount;
        return HederaResponseCodes.SUCCESS;
    }

    // ---- supply (authorization = msg.sender holds the supply key; the real network additionally requires the
    //      key to be a delegatableContractId key when the caller runs in a delegatecall frame) ----
    function mintToken(address token, int64 amount, bytes[] memory metadata)
        external
        returns (int64, int64, int64[] memory serials)
    {
        int64 forced = _consumeForced(IHederaTokenService.mintToken.selector);
        if (forced != 0) return (forced, 0, serials);
        if (!tokenExists[token]) return (HederaResponseCodes.INVALID_TOKEN_ID, 0, serials);
        if (supplyKeyHolder[token] == address(0)) return (HederaResponseCodes.TOKEN_HAS_NO_SUPPLY_KEY, 0, serials);
        if (supplyKeyHolder[token] != msg.sender) {
            return (HederaResponseCodes.INVALID_FULL_PREFIX_SIGNATURE_FOR_PRECOMPILE, 0, serials);
        }
        int64 minted = tokenType[token] == 0 ? amount : int64(int256(metadata.length));
        totalSupply[token] += minted;
        balanceOf[token][msg.sender] += minted; // treasury == key holder in the mock
        if (tokenType[token] == 1) {
            serials = new int64[](metadata.length);
            for (uint256 i; i < metadata.length; ++i) {
                serials[i] = totalSupply[token] - minted + int64(int256(i)) + 1;
            }
        }
        return (HederaResponseCodes.SUCCESS, totalSupply[token], serials);
    }

    function burnToken(address token, int64 amount, int64[] memory serials) external returns (int64, int64) {
        int64 forced = _consumeForced(IHederaTokenService.burnToken.selector);
        if (forced != 0) return (forced, 0);
        if (supplyKeyHolder[token] != msg.sender) {
            return (HederaResponseCodes.INVALID_FULL_PREFIX_SIGNATURE_FOR_PRECOMPILE, 0);
        }
        int64 burned = tokenType[token] == 0 ? amount : int64(int256(serials.length));
        if (balanceOf[token][msg.sender] < burned) return (HederaResponseCodes.INSUFFICIENT_TOKEN_BALANCE, 0);
        totalSupply[token] -= burned;
        balanceOf[token][msg.sender] -= burned;
        return (HederaResponseCodes.SUCCESS, totalSupply[token]);
    }

    // ---- creation: the caller becomes treasury + supply key holder; the fee is whatever HBAR was sent ----
    function createFungibleToken(IHederaTokenService.HederaToken memory t, int64 initialSupply, int32)
        external
        payable
        returns (int64, address token)
    {
        int64 forced = _consumeForced(IHederaTokenService.createFungibleToken.selector);
        if (forced != 0) return (forced, address(0));
        if (msg.value == 0) return (HederaResponseCodes.INSUFFICIENT_PAYER_BALANCE, address(0));
        token = _create(t, 0);
        totalSupply[token] = initialSupply;
        balanceOf[token][t.treasury] = initialSupply;
        return (HederaResponseCodes.SUCCESS, token);
    }

    function createNonFungibleToken(IHederaTokenService.HederaToken memory t)
        external
        payable
        returns (int64, address token)
    {
        int64 forced = _consumeForced(IHederaTokenService.createNonFungibleToken.selector);
        if (forced != 0) return (forced, address(0));
        if (msg.value == 0) return (HederaResponseCodes.INSUFFICIENT_PAYER_BALANCE, address(0));
        token = _create(t, 1);
        return (HederaResponseCodes.SUCCESS, token);
    }

    function _create(IHederaTokenService.HederaToken memory t, int32 type_) private returns (address token) {
        token = address(new MockHRC719Token());
        tokenExists[token] = true;
        tokenType[token] = type_;
        associated[t.treasury][token] = true;
        tokens.push(token);
        // Honour the key semantics that matter for a diamond: only a delegatableContractId key activates for a
        // caller running in a delegatecall frame, which is every facet call. A contractId key is recorded as
        // "no holder" so a mint from a diamond fails the way the network would fail it.
        for (uint256 i; i < t.tokenKeys.length; ++i) {
            if (t.tokenKeys[i].keyType & 16 != 0) supplyKeyHolder[token] = t.tokenKeys[i].key.delegatableContractId;
        }
    }

    // ---- queries ----
    function getTokenType(address token) external view returns (int64, int32) {
        if (!tokenExists[token]) return (HederaResponseCodes.INVALID_TOKEN_ID, -1);
        return (HederaResponseCodes.SUCCESS, tokenType[token]);
    }

    function isTokenQuery(address token) external view returns (int64, bool) {
        return (HederaResponseCodes.SUCCESS, tokenExists[token]);
    }

    /// @dev `isToken(address)` clashes with the public mapping getter name, so route the real selector here.
    fallback() external payable {
        if (msg.sig == IHederaTokenService.isToken.selector) {
            address token = abi.decode(msg.data[4:], (address));
            bytes memory ret = abi.encode(HederaResponseCodes.SUCCESS, tokenExists[token]);
            assembly {
                return(add(ret, 0x20), mload(ret))
            }
        }
        bytes memory unsupported = abi.encode(HederaResponseCodes.NOT_SUPPORTED);
        assembly {
            return(add(unsupported, 0x20), mload(unsupported))
        }
    }

    receive() external payable {}
}

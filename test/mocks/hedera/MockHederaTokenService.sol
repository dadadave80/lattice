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
///         like the real system contract, keeps just enough state (associations, balances, NFT serial owners,
///         allowances, treasury, admin / supply key holders) to exercise the adapter's happy paths, records the
///         `HederaToken` body every create submitted, and lets a test force any code for the next call of a
///         selector.
/// @dev Must not rely on constructor state: an etched contract starts with empty storage. Token addresses are
///      real contracts (MockHRC719Token) so the HIP-719 `isAssociated()` facade path can be unit-tested.
///      {forceRevert} is the ONE deviation from "never reverts": it is off by default and must be armed per
///      selector, and it exists only so the adapter's halted-frame defaults (response code UNKNOWN) are
///      reachable — a code the system contract itself can never return.
contract MockHederaTokenService {
    mapping(address account => mapping(address token => bool)) public associated;
    mapping(address token => mapping(address account => int64)) public balanceOf;
    mapping(address token => mapping(int64 serial => address owner)) public nftOwner;
    mapping(address token => int64) public lastSerial;
    mapping(address token => mapping(address owner => mapping(address spender => uint256))) public allowances;
    mapping(address token => address) public treasury;
    mapping(address token => address) public adminKeyHolder;
    mapping(address token => address) public supplyKeyHolder;
    mapping(address token => int64) public totalSupply;
    mapping(address token => int32) public tokenType; // 0 FT, 1 NFT
    mapping(address token => bool) public tokenExists;
    mapping(bytes4 selector => int64) public forcedCode;
    mapping(bytes4 selector => bool) public forcedRevert;
    mapping(address token => IHederaTokenService.HederaToken) private _submittedToken;
    address[] public tokens;

    /// @notice A test armed {forceRevert} for `selector`, so this frame halts instead of returning a code.
    error HTSFrameHalted(bytes4 selector);

    /// @notice Force the next call of `selector` to return `code` (0 clears).
    function force(bytes4 selector, int64 code) external {
        forcedCode[selector] = code;
    }

    /// @notice Arm (`on`) or disarm the frame-failure injector for `selector`: an armed selector REVERTS.
    /// @dev Off by default, and sticky rather than one-shot — the revert rolls back any self-disarm — so a
    ///      test that needs the selector working again must clear it explicitly.
    function forceRevert(bytes4 selector, bool on) external {
        forcedRevert[selector] = on;
    }

    /// @notice The `HederaToken` body submitted when `token` was created, recorded verbatim.
    function submittedToken(address token) external view returns (IHederaTokenService.HederaToken memory) {
        return _submittedToken[token];
    }

    /// @notice TEST HELPER — deliberately NOT an HTS selector. Seeds the allowance `owner` granted `spender`
    ///         on `token`, standing in for the `approve` / `approveNFT` transaction a counterparty signs off-chain.
    function seedAllowance(address token, address owner, address spender, uint256 amount) external {
        allowances[token][owner][spender] = amount;
    }

    function _consumeForced(bytes4 selector) private returns (int64 code) {
        code = forcedCode[selector];
        if (code != 0) delete forcedCode[selector];
    }

    /// @dev The opt-in halt: an armed selector never reaches its response-code logic.
    function _failFrame(bytes4 selector) private view {
        if (forcedRevert[selector]) revert HTSFrameHalted(selector);
    }

    /// @dev Field-by-field because the legacy pipeline cannot copy a `TokenKey[] memory` straight to storage.
    function _record(address token, IHederaTokenService.HederaToken memory t) private {
        IHederaTokenService.HederaToken storage submitted = _submittedToken[token];
        submitted.name = t.name;
        submitted.symbol = t.symbol;
        submitted.treasury = t.treasury;
        submitted.memo = t.memo;
        submitted.tokenSupplyType = t.tokenSupplyType;
        submitted.maxSupply = t.maxSupply;
        submitted.freezeDefault = t.freezeDefault;
        submitted.expiry = t.expiry;
        for (uint256 i; i < t.tokenKeys.length; ++i) {
            submitted.tokenKeys.push(t.tokenKeys[i]);
        }
    }

    // ---- associations ----
    function associateToken(address account, address token) public returns (int64) {
        _failFrame(IHederaTokenService.associateToken.selector);
        int64 forced = _consumeForced(IHederaTokenService.associateToken.selector);
        if (forced != 0) return forced;
        if (!tokenExists[token]) return HederaResponseCodes.INVALID_TOKEN_ID;
        if (associated[account][token]) return HederaResponseCodes.TOKEN_ALREADY_ASSOCIATED_TO_ACCOUNT;
        associated[account][token] = true;
        return HederaResponseCodes.SUCCESS;
    }

    function dissociateToken(address account, address token) public returns (int64) {
        _failFrame(IHederaTokenService.dissociateToken.selector);
        int64 forced = _consumeForced(IHederaTokenService.dissociateToken.selector);
        if (forced != 0) return forced;
        if (!associated[account][token]) return HederaResponseCodes.TOKEN_NOT_ASSOCIATED_TO_ACCOUNT;
        // A treasury can never dissociate itself, however empty it is: the consensus node's dissociate handler
        // refuses with ACCOUNT_IS_TREASURY BEFORE it ever looks at the balance.
        if (treasury[token] == account) return HederaResponseCodes.ACCOUNT_IS_TREASURY;
        if (balanceOf[token][account] != 0) return HederaResponseCodes.TRANSACTION_REQUIRES_ZERO_TOKEN_BALANCES;
        associated[account][token] = false;
        return HederaResponseCodes.SUCCESS;
    }

    // ---- transfers (sender authorization = msg.sender is the sender, like a contract moving its own funds) ----
    function transferToken(address token, address sender, address receiver, int64 amount) external returns (int64) {
        _failFrame(IHederaTokenService.transferToken.selector);
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

    function transferNFT(address token, address sender, address receiver, int64 serialNumber) external returns (int64) {
        _failFrame(IHederaTokenService.transferNFT.selector);
        int64 forced = _consumeForced(IHederaTokenService.transferNFT.selector);
        if (forced != 0) return forced;
        if (!tokenExists[token]) return HederaResponseCodes.INVALID_TOKEN_ID;
        if (sender != msg.sender) return HederaResponseCodes.INVALID_FULL_PREFIX_SIGNATURE_FOR_PRECOMPILE;
        if (!associated[sender][token]) return HederaResponseCodes.TOKEN_NOT_ASSOCIATED_TO_ACCOUNT;
        if (!associated[receiver][token]) return HederaResponseCodes.TOKEN_NOT_ASSOCIATED_TO_ACCOUNT;
        if (nftOwner[token][serialNumber] != sender) return HederaResponseCodes.SENDER_DOES_NOT_OWN_NFT_SERIAL_NO;
        nftOwner[token][serialNumber] = receiver;
        balanceOf[token][sender] -= 1;
        balanceOf[token][receiver] += 1;
        return HederaResponseCodes.SUCCESS;
    }

    /// @dev Allowance path: the SPENDER is `msg.sender`, so the diamond spends what `from` granted it. Every
    ///      check runs before the first write — a response code is not a revert, so a half-applied transfer
    ///      would persist.
    function transferFrom(address token, address from, address to, uint256 amount) external returns (int64) {
        _failFrame(IHederaTokenService.transferFrom.selector);
        int64 forced = _consumeForced(IHederaTokenService.transferFrom.selector);
        if (forced != 0) return forced;
        if (!tokenExists[token]) return HederaResponseCodes.INVALID_TOKEN_ID;
        uint256 allowed = allowances[token][from][msg.sender];
        if (allowed == 0) return HederaResponseCodes.SPENDER_DOES_NOT_HAVE_ALLOWANCE;
        if (allowed < amount) return HederaResponseCodes.AMOUNT_EXCEEDS_ALLOWANCE;
        if (!associated[from][token]) return HederaResponseCodes.TOKEN_NOT_ASSOCIATED_TO_ACCOUNT;
        if (!associated[to][token]) return HederaResponseCodes.TOKEN_NOT_ASSOCIATED_TO_ACCOUNT;
        int64 value = int64(int256(amount));
        if (balanceOf[token][from] < value) return HederaResponseCodes.INSUFFICIENT_TOKEN_BALANCE;
        allowances[token][from][msg.sender] = allowed - amount;
        balanceOf[token][from] -= value;
        balanceOf[token][to] += value;
        return HederaResponseCodes.SUCCESS;
    }

    // ---- supply (authorization = msg.sender holds the supply key; the real network additionally requires the
    //      key to be a delegatableContractId key when the caller runs in a delegatecall frame) ----
    function mintToken(address token, int64 amount, bytes[] memory metadata)
        external
        returns (int64, int64, int64[] memory serials)
    {
        _failFrame(IHederaTokenService.mintToken.selector);
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
            // Serials come from a monotonic per-token counter, never from the supply: a burned serial is gone
            // for good and must never be handed out again.
            serials = new int64[](metadata.length);
            for (uint256 i; i < metadata.length; ++i) {
                int64 serial = lastSerial[token] + 1;
                lastSerial[token] = serial;
                nftOwner[token][serial] = msg.sender; // treasury == key holder in the mock
                serials[i] = serial;
            }
        }
        return (HederaResponseCodes.SUCCESS, totalSupply[token], serials);
    }

    function burnToken(address token, int64 amount, int64[] memory serials) external returns (int64, int64) {
        _failFrame(IHederaTokenService.burnToken.selector);
        int64 forced = _consumeForced(IHederaTokenService.burnToken.selector);
        if (forced != 0) return (forced, 0);
        if (supplyKeyHolder[token] != msg.sender) {
            return (HederaResponseCodes.INVALID_FULL_PREFIX_SIGNATURE_FOR_PRECOMPILE, 0);
        }
        int64 burned = tokenType[token] == 0 ? amount : int64(int256(serials.length));
        // Validate every listed serial before touching state (a returned code cannot roll back a write).
        if (tokenType[token] == 1) {
            for (uint256 i; i < serials.length; ++i) {
                if (nftOwner[token][serials[i]] != msg.sender) {
                    return (HederaResponseCodes.SENDER_DOES_NOT_OWN_NFT_SERIAL_NO, 0);
                }
            }
        }
        if (balanceOf[token][msg.sender] < burned) return (HederaResponseCodes.INSUFFICIENT_TOKEN_BALANCE, 0);
        if (tokenType[token] == 1) {
            for (uint256 i; i < serials.length; ++i) {
                delete nftOwner[token][serials[i]];
            }
        }
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
        _failFrame(IHederaTokenService.createFungibleToken.selector);
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
        _failFrame(IHederaTokenService.createNonFungibleToken.selector);
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
        treasury[token] = t.treasury;
        associated[t.treasury][token] = true;
        tokens.push(token);
        _record(token, t);
        // Honour the key semantics that matter for a diamond: only a delegatableContractId key is verified
        // and accepted for a caller running in a delegatecall frame, which is every facet call. A contractId
        // key is recorded as "no holder" so a mint from a diamond fails.
        //
        // This is deliberately STRICTER than the live network for one shape. Testnet 2026-09-12 showed a
        // `contractId(<diamond>)` key minting fine, because on a relay-deployed diamond that key is
        // byte-identical to the diamond's own account key — the dispatched child's payer key — and the node
        // elides a required key equal to the payer key before verifying it. The mock models the rule rather
        // than the elision on purpose: the elision does not hold for a diamond whose account key is not
        // contractId(self), for a contractId nested in a KeyList/ThresholdKey, or for a key naming another
        // contract, so a test that relied on it would encode an accident. See docs/guides/hedera.md. Admin (bit 1) and
        // supply (bit 16) are recorded separately — a token may carry either without the other.
        for (uint256 i; i < t.tokenKeys.length; ++i) {
            if (t.tokenKeys[i].keyType & 1 != 0) adminKeyHolder[token] = t.tokenKeys[i].key.delegatableContractId;
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

// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.4;

/// @title IHederaTokenService
/// @author Vendored minimal subset of hiero-ledger/hiero-contracts `contracts/token-service/IHederaTokenService.sol`
///         (https://github.com/hiero-ledger/hiero-contracts/blob/main/contracts/token-service/IHederaTokenService.sol),
///         commit 5ade6c8 (2026-09-09). Upstream license: Apache-2.0 (Hedera Hashgraph, LLC).
/// @notice ABI of the Hedera Token Service system contract at `0x0000000000000000000000000000000000000167`.
///         Struct layouts are byte-identical to upstream (they define the create/update selectors). Only the
///         functions Lattice's HTS modules call are kept; every function returns an `int64` response code
///         (`HederaResponseCodes.SUCCESS == 22`) instead of reverting.
/// @dev Getters are declared non-`view` upstream; Lattice calls the view-classified ones through `staticcall`.
interface IHederaTokenService {
    struct Expiry {
        int64 second;
        address autoRenewAccount;
        int64 autoRenewPeriod;
    }

    /// @dev Exactly one member must be populated. `contractId` activates only when the given contract's OWN
    ///      code runs in the frame that calls HTS; `delegatableContractId` also activates when that contract
    ///      is merely the recipient of the frame (i.e. it is running another contract's code via
    ///      `delegatecall` — every EIP-2535 facet call). Diamonds MUST use `delegatableContractId`.
    struct KeyValue {
        bool inheritAccountKey;
        address contractId;
        bytes ed25519;
        bytes ECDSA_secp256k1;
        address delegatableContractId;
    }

    /// @dev `keyType` bit field: 1 admin, 2 kyc, 4 freeze, 8 wipe, 16 supply, 32 fee schedule, 64 pause.
    struct TokenKey {
        uint256 keyType;
        KeyValue key;
    }

    struct HederaToken {
        string name;
        string symbol;
        address treasury;
        string memo;
        bool tokenSupplyType;
        int64 maxSupply;
        bool freezeDefault;
        TokenKey[] tokenKeys;
        Expiry expiry;
    }

    struct FixedFee {
        int64 amount;
        address tokenId;
        bool useHbarsForPayment;
        bool useCurrentTokenForPayment;
        address feeCollector;
    }

    struct FractionalFee {
        int64 numerator;
        int64 denominator;
        int64 minimumAmount;
        int64 maximumAmount;
        bool netOfTransfers;
        address feeCollector;
    }

    struct RoyaltyFee {
        int64 numerator;
        int64 denominator;
        int64 amount;
        address tokenId;
        bool useHbarsForPayment;
        address feeCollector;
    }

    struct TokenInfo {
        HederaToken token;
        int64 totalSupply;
        bool deleted;
        bool defaultKycStatus;
        bool pauseStatus;
        FixedFee[] fixedFees;
        FractionalFee[] fractionalFees;
        RoyaltyFee[] royaltyFees;
        string ledgerId;
    }

    struct FungibleTokenInfo {
        TokenInfo tokenInfo;
        int32 decimals;
    }

    // ---- associations ----
    function associateToken(address account, address token) external returns (int64 responseCode);
    function dissociateToken(address account, address token) external returns (int64 responseCode);

    // ---- transfers ----
    function transferToken(address token, address sender, address receiver, int64 amount)
        external
        returns (int64 responseCode);
    function transferNFT(address token, address sender, address receiver, int64 serialNumber)
        external
        returns (int64 responseCode);
    function transferFrom(address token, address from, address to, uint256 amount) external returns (int64 responseCode);

    // ---- supply ----
    function mintToken(address token, int64 amount, bytes[] memory metadata)
        external
        returns (int64 responseCode, int64 newTotalSupply, int64[] memory serialNumbers);
    function burnToken(address token, int64 amount, int64[] memory serialNumbers)
        external
        returns (int64 responseCode, int64 newTotalSupply);

    // ---- creation / keys ----
    function createFungibleToken(HederaToken memory token, int64 initialTotalSupply, int32 decimals)
        external
        payable
        returns (int64 responseCode, address tokenAddress);
    function createNonFungibleToken(HederaToken memory token)
        external
        payable
        returns (int64 responseCode, address tokenAddress);
    function updateTokenKeys(address token, TokenKey[] memory keys) external returns (int64 responseCode);

    // ---- queries (view-classified by the network; call via staticcall) ----
    function isToken(address token) external returns (int64 responseCode, bool isToken);
    function getTokenType(address token) external returns (int64 responseCode, int32 tokenType);
    function getTokenInfo(address token) external returns (int64 responseCode, TokenInfo memory tokenInfo);
    function getFungibleTokenInfo(address token)
        external
        returns (int64 responseCode, FungibleTokenInfo memory fungibleTokenInfo);
    function getTokenKey(address token, uint256 keyType) external returns (int64 responseCode, KeyValue memory key);
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.4;

/// @title HederaResponseCodes
/// @author Vendored minimal subset of hiero-ledger/hiero-contracts `contracts/common/HederaResponseCodes.sol`
///         (https://github.com/hiero-ledger/hiero-contracts/blob/main/contracts/common/HederaResponseCodes.sol),
///         commit 5ade6c8 (2026-09-09). Upstream license: Apache-2.0 (Hedera Hashgraph, LLC).
/// @notice The `ResponseCodeEnum` ordinals (`response_code.proto`) that Hedera system contracts return in place
///         of reverting. Values MUST stay identical to upstream; only the codes Lattice maps are kept.
library HederaResponseCodes {
    int64 internal constant OK = 0;
    int64 internal constant INVALID_TRANSACTION = 1;
    int64 internal constant INVALID_SIGNATURE = 7;
    int64 internal constant INSUFFICIENT_PAYER_BALANCE = 10;
    int64 internal constant NOT_SUPPORTED = 13;
    int64 internal constant INVALID_ACCOUNT_ID = 15;
    int64 internal constant INVALID_CONTRACT_ID = 16;
    int64 internal constant UNKNOWN = 21;
    int64 internal constant SUCCESS = 22;
    int64 internal constant INSUFFICIENT_ACCOUNT_BALANCE = 28;
    int64 internal constant INVALID_SOLIDITY_ADDRESS = 29;
    int64 internal constant INSUFFICIENT_GAS = 30;
    int64 internal constant CONTRACT_REVERT_EXECUTED = 33;
    int64 internal constant ACCOUNT_FROZEN_FOR_TOKEN = 165;
    int64 internal constant TOKENS_PER_ACCOUNT_LIMIT_EXCEEDED = 166;
    int64 internal constant INVALID_TOKEN_ID = 167;
    int64 internal constant INVALID_TREASURY_ACCOUNT_FOR_TOKEN = 170;
    int64 internal constant ACCOUNT_KYC_NOT_GRANTED_FOR_TOKEN = 176;
    int64 internal constant INSUFFICIENT_TOKEN_BALANCE = 178;
    int64 internal constant TOKEN_WAS_DELETED = 179;
    int64 internal constant TOKEN_HAS_NO_SUPPLY_KEY = 180;
    int64 internal constant TOKEN_HAS_NO_WIPE_KEY = 181;
    int64 internal constant INVALID_TOKEN_MINT_AMOUNT = 182;
    int64 internal constant INVALID_TOKEN_BURN_AMOUNT = 183;
    int64 internal constant TOKEN_NOT_ASSOCIATED_TO_ACCOUNT = 184;
    int64 internal constant TOKEN_ALREADY_ASSOCIATED_TO_ACCOUNT = 194;
    int64 internal constant TRANSACTION_REQUIRES_ZERO_TOKEN_BALANCES = 195;
    int64 internal constant ACCOUNT_IS_TREASURY = 196;
    int64 internal constant INVALID_TOKEN_NFT_SERIAL_NUMBER = 225;
    int64 internal constant TOKEN_MAX_SUPPLY_REACHED = 236;
    int64 internal constant SENDER_DOES_NOT_OWN_NFT_SERIAL_NO = 237;
    int64 internal constant NO_REMAINING_AUTOMATIC_ASSOCIATIONS = 262;
    int64 internal constant TOKEN_IS_PAUSED = 265;
    int64 internal constant SPENDER_DOES_NOT_HAVE_ALLOWANCE = 292;
    int64 internal constant AMOUNT_EXCEEDS_ALLOWANCE = 293;
    int64 internal constant MAX_ENTITIES_IN_PRICE_REGIME_HAVE_BEEN_CREATED = 325;
    int64 internal constant INVALID_FULL_PREFIX_SIGNATURE_FOR_PRECOMPILE = 326;
    int64 internal constant SCHEDULE_EXPIRY_IS_BUSY = 370;
}

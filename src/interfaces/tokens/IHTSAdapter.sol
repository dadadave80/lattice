// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

/// @title IHTSAdapter
/// @author Modified from hiero-ledger/hiero-contracts (https://github.com/hiero-ledger/hiero-contracts)
/// @notice Interface for the HTSAdapter Diamond facet — the diamond as a Hedera Token Service account: it
///         associates itself with HTS tokens, moves its own balances, and creates / mints / burns tokens
///         whose supply and admin keys are held by the diamond (as `delegatableContractId` keys).
/// @dev Every HTS system-contract call returns an `int64` response code instead of reverting; the facet maps
///      the common codes to the typed errors below and everything else to {HTSCallFailed}. Amounts are
///      `int64` and NFT serials are `int64`, exactly as HTS defines them.
interface IHTSAdapter {
    // -------------------------------------------------------------------------
    //                                  Events
    // -------------------------------------------------------------------------

    /// @notice Emitted when the diamond associates itself with `token`.
    event HTSTokenAssociated(address indexed token);

    /// @notice Emitted when the diamond dissociates itself from `token`.
    event HTSTokenDissociated(address indexed token);

    /// @notice Emitted when the diamond creates an HTS token (it is the treasury and key holder).
    event HTSTokenCreated(address indexed token, bool fungible);

    /// @notice Emitted on a successful HTS transfer initiated by the diamond.
    event HTSTokenTransferred(address indexed token, address indexed from, address indexed to, int64 amount);

    /// @notice Emitted after a successful mint (`amount` is units for FT, number of serials for NFT).
    event HTSTokenMinted(address indexed token, int64 amount, int64 newTotalSupply);

    /// @notice Emitted after a successful burn.
    event HTSTokenBurned(address indexed token, int64 amount, int64 newTotalSupply);

    // -------------------------------------------------------------------------
    //                                  Errors
    // -------------------------------------------------------------------------

    /// @notice `account` is not associated with `token` (HTS 184).
    error HTSTokenNotAssociated(address token, address account);
    /// @notice `account` is already associated with `token` (HTS 194).
    error HTSTokenAlreadyAssociated(address token, address account);
    /// @notice `account` holds too little of `token` (HTS 178 / 28).
    error HTSInsufficientBalance(address token, address account);
    /// @notice `account` still holds a balance of `token`, so it cannot be dissociated (HTS 195).
    error HTSNonZeroBalance(address token, address account);
    /// @notice No active key authorized the operation (HTS 7 / 326). For a diamond this almost always means a
    ///         token key was set as `contractId` instead of `delegatableContractId`.
    error HTSKeyNotActive(address token);
    /// @notice `token` has no supply key (HTS 180).
    error HTSTokenNoSupplyKey(address token);
    /// @notice The mint would exceed `token`'s max supply (HTS 236).
    error HTSMaxSupplyReached(address token);
    /// @notice `token` is paused (HTS 265).
    error HTSTokenPaused(address token);
    /// @notice `account` is frozen for `token` (HTS 165).
    error HTSAccountFrozen(address token, address account);
    /// @notice `account` has no KYC grant for `token` (HTS 176).
    error HTSKycNotGranted(address token, address account);
    /// @notice The diamond's allowance from `owner` on `token` is missing or too small (HTS 292 / 293).
    error HTSAllowanceExceeded(address token, address owner);
    /// @notice The frame did not carry enough gas for the system-contract fee (HTS 30).
    error HTSInsufficientGas();
    /// @notice `token` is not an HTS token (HTS 167 / `isToken` false).
    error HTSNotAToken(address token);
    /// @notice An amount, serial list, or supply parameter was invalid (HTS 182 / 183 / 225 or local check).
    error HTSInvalidAmount();
    /// @notice Catch-all: HTS function `selector` returned `responseCode`.
    error HTSCallFailed(bytes4 selector, int64 responseCode);

    // -------------------------------------------------------------------------
    //                                   Reads
    // -------------------------------------------------------------------------

    /// @notice True if the diamond is associated with `token` (HIP-719 facade `isAssociated()`).
    function isAssociated(address token) external view returns (bool associated);

    /// @notice True if `token` is an HTS token (`isToken` on the system contract).
    function isHTSToken(address token) external view returns (bool isToken);

    /// @notice HTS token type: 0 fungible, 1 non-fungible.
    function htsTokenType(address token) external view returns (int32 tokenType);

    /// @notice The HTS tokens this diamond created (it is their treasury and key holder).
    function createdTokens() external view returns (address[] memory tokens);

    // -------------------------------------------------------------------------
    //                         Admin (HTS_MANAGER_ROLE)
    // -------------------------------------------------------------------------

    /// @notice Associates the diamond with `token` so it can hold and receive it.
    function associateToken(address token) external;

    /// @notice Dissociates the diamond from `token` (its balance must be zero).
    function dissociateToken(address token) external;

    /// @notice Creates a fungible HTS token with the diamond as treasury, auto-renew account, and holder of the
    ///         admin + supply keys (`delegatableContractId`). `msg.value` pays the network's creation fee.
    /// @param maxSupply Zero for an infinite supply; otherwise the finite cap.
    function createFungibleToken(
        string calldata name,
        string calldata symbol,
        string calldata memo,
        int32 decimals,
        int64 initialSupply,
        int64 maxSupply
    ) external payable returns (address token);

    /// @notice Creates a non-fungible HTS token with the diamond as treasury / key holder. `msg.value` pays the fee.
    function createNonFungibleToken(string calldata name, string calldata symbol, string calldata memo, int64 maxSupply)
        external
        payable
        returns (address token);

    // -------------------------------------------------------------------------
    //                        Operator (HTS_OPERATOR_ROLE)
    // -------------------------------------------------------------------------

    /// @notice Transfers `amount` of `token` from the diamond's own balance to `to`.
    function transferToken(address token, address to, int64 amount) external;

    /// @notice Transfers `amount` of `token` from `from` to `to` using the allowance `from` granted the diamond.
    function transferTokenFrom(address token, address from, address to, int64 amount) external;

    /// @notice Transfers NFT `serialNumber` of `token` owned by the diamond to `to`.
    function transferNFT(address token, address to, int64 serialNumber) external;

    /// @notice Mints `amount` units (FT) or `metadata.length` serials (NFT) to the treasury. Requires the diamond
    ///         to hold the supply key as a `delegatableContractId` key.
    function mintToken(address token, int64 amount, bytes[] calldata metadata)
        external
        returns (int64 newTotalSupply, int64[] memory serialNumbers);

    /// @notice Burns `amount` units (FT) or the given `serialNumbers` (NFT) from the treasury.
    function burnToken(address token, int64 amount, int64[] calldata serialNumbers)
        external
        returns (int64 newTotalSupply);
}

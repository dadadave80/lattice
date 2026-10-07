// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IHTSAdapter} from "@lattice/interfaces/tokens/IHTSAdapter.sol";
import {HTSAdapterLib} from "@lattice/tokens/hedera/HTSAdapterLib.sol";

/// @title HTSAdapter
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from hiero-ledger/hiero-contracts (https://github.com/hiero-ledger/hiero-contracts)
/// @notice Diamond facet that makes the diamond a first-class Hedera Token Service account: association,
///         treasury transfers, and creation / mint / burn of tokens keyed to the diamond.
/// @dev Stateless delegator — all logic and storage live in HTSAdapterLib. Consumers inherit this contract
///      and add AccessControl + an initializer. Only meaningful on Hedera (chain ids 295 / 296 / 297 / 298).
/// @custom:lattice-version 0.1.0
/// @custom:lattice-source Hedera
contract HTSAdapter is IHTSAdapter {
    /// @inheritdoc IHTSAdapter
    function isAssociated(address token) external view virtual override returns (bool associated) {
        return HTSAdapterLib.isAssociated(token);
    }

    /// @inheritdoc IHTSAdapter
    function isHTSToken(address token) external view virtual override returns (bool isToken) {
        return HTSAdapterLib.isHTSToken(token);
    }

    /// @inheritdoc IHTSAdapter
    function htsTokenType(address token) external view virtual override returns (int32 tokenType) {
        return HTSAdapterLib.htsTokenType(token);
    }

    /// @inheritdoc IHTSAdapter
    function createdTokens() external view virtual override returns (address[] memory tokens) {
        return HTSAdapterLib.createdTokens();
    }

    /// @inheritdoc IHTSAdapter
    function associateToken(address token) external virtual override {
        HTSAdapterLib.associateToken(token);
    }

    /// @inheritdoc IHTSAdapter
    function dissociateToken(address token) external virtual override {
        HTSAdapterLib.dissociateToken(token);
    }

    /// @inheritdoc IHTSAdapter
    function createFungibleToken(
        string calldata name,
        string calldata symbol,
        string calldata memo,
        int32 decimals,
        int64 initialSupply,
        int64 maxSupply
    ) external payable virtual override returns (address token) {
        return HTSAdapterLib.createFungibleToken(name, symbol, memo, decimals, initialSupply, maxSupply);
    }

    /// @inheritdoc IHTSAdapter
    function createNonFungibleToken(string calldata name, string calldata symbol, string calldata memo, int64 maxSupply)
        external
        payable
        virtual
        override
        returns (address token)
    {
        return HTSAdapterLib.createNonFungibleToken(name, symbol, memo, maxSupply);
    }

    /// @inheritdoc IHTSAdapter
    function transferToken(address token, address to, int64 amount) external virtual override {
        HTSAdapterLib.transferToken(token, to, amount);
    }

    /// @inheritdoc IHTSAdapter
    function transferTokenFrom(address token, address from, address to, int64 amount) external virtual override {
        HTSAdapterLib.transferTokenFrom(token, from, to, amount);
    }

    /// @inheritdoc IHTSAdapter
    function transferNFT(address token, address to, int64 serialNumber) external virtual override {
        HTSAdapterLib.transferNFT(token, to, serialNumber);
    }

    /// @inheritdoc IHTSAdapter
    function mintToken(address token, int64 amount, bytes[] calldata metadata)
        external
        virtual
        override
        returns (int64 newTotalSupply, int64[] memory serialNumbers)
    {
        return HTSAdapterLib.mintToken(token, amount, metadata);
    }

    /// @inheritdoc IHTSAdapter
    function burnToken(address token, int64 amount, int64[] calldata serialNumbers)
        external
        virtual
        override
        returns (int64 newTotalSupply)
    {
        return HTSAdapterLib.burnToken(token, amount, serialNumbers);
    }

    /// @notice ERC-8153 selector export: this facet's cuttable selectors, tightly packed (4 bytes each).
    /// @dev Excludes `exportSelectors()` itself (0x0ef22643) - it is never cut into a diamond. Order matches
    ///      `forge inspect HTSAdapter methodIdentifiers` (alphabetical by signature); kept in exact parity by
    ///      ExportSelectorsParityTest. Chunks:
    ///      `associateToken(address)` 0xa7efe348
    ///      `burnToken(address,int64,int64[])` 0xd6910d06
    ///      `createFungibleToken(string,string,string,int32,int64,int64)` 0xdeaac2bb
    ///      `createNonFungibleToken(string,string,string,int64)` 0x6830760a
    ///      `createdTokens()` 0x54771086
    ///      `dissociateToken(address)` 0xd5d607b6
    ///      `htsTokenType(address)` 0xcaaf0325
    ///      `isAssociated(address)` 0xd55fe582
    ///      `isHTSToken(address)` 0x20cab858
    ///      `mintToken(address,int64,bytes[])` 0xe0f4059a
    ///      `transferNFT(address,address,int64)` 0x84ec4652
    ///      `transferToken(address,address,int64)` 0x75fd1606
    ///      `transferTokenFrom(address,address,address,int64)` 0x5f34cf96
    function exportSelectors() external pure virtual returns (bytes memory selectors) {
        selectors =
            hex"a7efe348d6910d06deaac2bb6830760a54771086d5d607b6caaf0325d55fe58220cab858e0f4059a84ec465275fd16065f34cf96";
    }
}

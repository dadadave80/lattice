// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ICompliance} from "@lattice/interfaces/tokens/erc3643/ICompliance.sol";
import {IERC3643} from "@lattice/interfaces/tokens/erc3643/IERC3643.sol";
import {IIdentityRegistry} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistry.sol";
import {ERC20Lib} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {ERC3643Lib} from "@lattice/tokens/ERC3643/libraries/ERC3643Lib.sol";

/// @title ERC3643
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-3643 (https://eips.ethereum.org/EIPS/eip-3643)
/// @notice Clean-room permissioned token facet for the closed immutable ERC-3643 composition.
/// @dev Owns the entire ERC20 surface. The canonical initializer rejects other accounting movers,
///      cut/execution routes and unknown facets; it is not a sandbox for arbitrary malicious initializers.
/// @custom:lattice-source ERC-3643 CC0 standard
/// @custom:lattice-requires OwnableFacet convention issuer-owner-management;
/// @custom:lattice-requires ERC3643AgentRole convention token-agent-management;
/// @custom:lattice-requires ERC3643IdentityRegistry hard co-located-isVerified-self-call;
/// @custom:lattice-requires ERC3643Compliance convention compliance-management;
/// @custom:lattice-family erc20-transfer
/// @custom:lattice-owns allowance(address,address);
/// @custom:lattice-owns approve(address,uint256);
/// @custom:lattice-owns balanceOf(address);
/// @custom:lattice-owns decimals();
/// @custom:lattice-owns name();
/// @custom:lattice-owns symbol();
/// @custom:lattice-owns totalSupply();
/// @custom:lattice-owns transfer(address,uint256);
/// @custom:lattice-owns transferFrom(address,address,uint256);
/// @custom:lattice-owns pause();
/// @custom:lattice-owns unpause();
/// @custom:lattice-owns paused();
/// @custom:lattice-owns version();
/// @custom:lattice-touches lattice.storage.ERC20;
/// @custom:lattice-touches lattice.storage.ERC3643;
/// @custom:lattice-touches lattice.storage.ERC3643IdentityRegistryStorage;
/// @custom:lattice-touches lattice.storage.ERC3643Compliance;
/// @custom:lattice-touches transient:lattice.storage.ERC20TemporaryApproval;
/// @custom:lattice-touches transient:lattice.storage.ERC3643Execution;
/// @custom:lattice-seam none;
/// @custom:lattice-init ERC3643Init
contract ERC3643 is IERC3643 {
    function name() external view returns (string memory) {
        return ERC20Lib.name();
    }

    function symbol() external view returns (string memory) {
        return ERC20Lib.symbol();
    }

    function decimals() external view returns (uint8) {
        return ERC3643Lib.decimals();
    }

    function totalSupply() external view returns (uint256) {
        return ERC20Lib.totalSupply();
    }

    function balanceOf(address account) external view returns (uint256) {
        return ERC20Lib.balanceOf(account);
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return ERC20Lib.allowance(owner, spender);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        return ERC20Lib.approve(spender, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return ERC3643Lib.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        return ERC3643Lib.transferFrom(from, to, amount);
    }

    function onchainID() external view returns (address) {
        return ERC3643Lib.onchainID();
    }

    function version() external pure returns (string memory) {
        return ERC3643Lib.version();
    }

    function identityRegistry() external view returns (IIdentityRegistry) {
        return IIdentityRegistry(ERC3643Lib.identityRegistry());
    }

    function compliance() external view returns (ICompliance) {
        return ICompliance(ERC3643Lib.compliance());
    }

    function paused() external view returns (bool) {
        return ERC3643Lib.paused();
    }

    function isFrozen(address wallet) external view returns (bool) {
        return ERC3643Lib.isFrozen(wallet);
    }

    function getFrozenTokens(address wallet) external view returns (uint256) {
        return ERC3643Lib.getFrozenTokens(wallet);
    }

    function setName(string calldata name_) external {
        ERC3643Lib.setName(name_);
    }

    function setSymbol(string calldata symbol_) external {
        ERC3643Lib.setSymbol(symbol_);
    }

    function setOnchainID(address identity_) external {
        ERC3643Lib.setOnchainID(identity_);
    }

    function setIdentityRegistry(address registry) external {
        ERC3643Lib.setIdentityRegistry(registry);
    }

    function setCompliance(address next) external {
        ERC3643Lib.setCompliance(next);
    }

    function pause() external {
        ERC3643Lib.pause();
    }

    function unpause() external {
        ERC3643Lib.unpause();
    }

    function setAddressFrozen(address wallet, bool freeze) external {
        ERC3643Lib.setAddressFrozen(wallet, freeze);
    }

    function freezePartialTokens(address wallet, uint256 amount) external {
        ERC3643Lib.freezePartialTokens(wallet, amount);
    }

    function unfreezePartialTokens(address wallet, uint256 amount) external {
        ERC3643Lib.unfreezePartialTokens(wallet, amount);
    }

    function forcedTransfer(address from, address to, uint256 amount) external returns (bool) {
        return ERC3643Lib.forcedTransfer(from, to, amount);
    }

    function mint(address to, uint256 amount) external {
        ERC3643Lib.mint(to, amount);
    }

    function burn(address from, uint256 amount) external {
        ERC3643Lib.burn(from, amount);
    }

    function recoveryAddress(address lost, address target, address identity_) external returns (bool) {
        return ERC3643Lib.recoveryAddress(lost, target, identity_);
    }

    function batchTransfer(address[] calldata to, uint256[] calldata amounts) external {
        ERC3643Lib.batchTransfer(to, amounts);
    }

    function batchForcedTransfer(address[] calldata from, address[] calldata to, uint256[] calldata amounts) external {
        ERC3643Lib.batchForcedTransfer(from, to, amounts);
    }

    function batchMint(address[] calldata to, uint256[] calldata amounts) external {
        ERC3643Lib.batchMint(to, amounts);
    }

    function batchBurn(address[] calldata from, uint256[] calldata amounts) external {
        ERC3643Lib.batchBurn(from, amounts);
    }

    function batchSetAddressFrozen(address[] calldata wallets, bool[] calldata freeze) external {
        ERC3643Lib.batchSetAddressFrozen(wallets, freeze);
    }

    function batchFreezePartialTokens(address[] calldata wallets, uint256[] calldata amounts) external {
        ERC3643Lib.batchFreezePartialTokens(wallets, amounts);
    }

    function batchUnfreezePartialTokens(address[] calldata wallets, uint256[] calldata amounts) external {
        ERC3643Lib.batchUnfreezePartialTokens(wallets, amounts);
    }

    /// @notice ERC-8153 packed selectors; excludes exportSelectors itself.
    function exportSelectors() external pure returns (bytes memory) {
        return hex"dd62ed3e095ea7b370a082314a6cc67742a47abcfc7e5fa8685731071a7af37988d695b24710362d9dc29fac6290865d313ce5679fc1d0e7125c4a33158b1a57134e18f4e583983640c10f1906fdde03aba637058456cb595c975abb9285948ac69c09cff8981789cbf3f861c47f00273d1ddc5bb84c824695d89b4118160ddda9059cbb23b872dd1fe56f7d3f4ba83a54fd4d50";
    }
}

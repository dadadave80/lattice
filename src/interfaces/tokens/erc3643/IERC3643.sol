// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@lattice/interfaces/tokens/IERC20.sol";
import {ICompliance} from "@lattice/interfaces/tokens/erc3643/ICompliance.sol";
import {IIdentityRegistry} from "@lattice/interfaces/tokens/erc3643/IIdentityRegistry.sol";

/// @title IERC3643
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from ERC-3643 (https://eips.ethereum.org/EIPS/eip-3643)
/// @notice Fresh declaration of the standard CC0 ABI; implementation is authored independently.
interface IERC3643 is IERC20 {
    event UpdatedTokenInformation(
        string indexed newName,
        string indexed newSymbol,
        uint8 newDecimals,
        string newVersion,
        address indexed newOnchainID
    );

    event IdentityRegistryAdded(address indexed identityRegistry);

    event ComplianceAdded(address indexed compliance);

    event RecoverySuccess(address indexed lostWallet, address indexed newWallet, address indexed investorOnchainID);

    event AddressFrozen(address indexed userAddress, bool indexed isFrozen, address indexed owner);

    event TokensFrozen(address indexed userAddress, uint256 amount);

    event TokensUnfrozen(address indexed userAddress, uint256 amount);

    event Paused(address userAddress);

    event Unpaused(address userAddress);

    function setName(string calldata name) external;

    function setSymbol(string calldata symbol) external;

    function setOnchainID(address onchainID) external;

    function pause() external;

    function unpause() external;

    function setAddressFrozen(address userAddress, bool freeze) external;

    function freezePartialTokens(address userAddress, uint256 amount) external;

    function unfreezePartialTokens(address userAddress, uint256 amount) external;

    function setIdentityRegistry(address identityRegistry) external;

    function setCompliance(address compliance) external;

    function forcedTransfer(address from, address to, uint256 amount) external returns (bool);

    function mint(address to, uint256 amount) external;

    function burn(address userAddress, uint256 amount) external;

    function recoveryAddress(address lostWallet, address newWallet, address investorOnchainID) external returns (bool);

    function batchTransfer(address[] calldata toList, uint256[] calldata amounts) external;

    function batchForcedTransfer(address[] calldata fromList, address[] calldata toList, uint256[] calldata amounts)
        external;

    function batchMint(address[] calldata toList, uint256[] calldata amounts) external;

    function batchBurn(address[] calldata userAddresses, uint256[] calldata amounts) external;

    function batchSetAddressFrozen(address[] calldata userAddresses, bool[] calldata freeze) external;

    function batchFreezePartialTokens(address[] calldata userAddresses, uint256[] calldata amounts) external;

    function batchUnfreezePartialTokens(address[] calldata userAddresses, uint256[] calldata amounts) external;

    function onchainID() external view returns (address);

    function version() external view returns (string memory);

    function identityRegistry() external view returns (IIdentityRegistry);

    function compliance() external view returns (ICompliance);

    function paused() external view returns (bool);

    function isFrozen(address userAddress) external view returns (bool);

    function getFrozenTokens(address userAddress) external view returns (uint256);
}

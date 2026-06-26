// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

// IERC7579 — Minimal modular smart-account interfaces (executor-module subset).
// Vendored from OpenZeppelin Contracts `contracts/interfaces/draft-IERC7579.sol` (MIT, the OZ split form).
// Vendored subset — do not add an openzeppelin-contracts dependency. Lattice implements the EXECUTOR-module
// subset (type 2) in v1. Interface ids (Solidity excludes inherited fns): IERC7579Execution = 0x3f3f9537,
// IERC7579AccountConfig = 0xbe1d6cf6, IERC7579ModuleConfig = 0x232dbb4a.

uint256 constant MODULE_TYPE_VALIDATOR = 1;
uint256 constant MODULE_TYPE_EXECUTOR = 2;
uint256 constant MODULE_TYPE_FALLBACK = 3;
uint256 constant MODULE_TYPE_HOOK = 4;

/// @dev Base interface every ERC-7579 module implements (an executor module is just this).
interface IERC7579Module {
    function onInstall(bytes calldata data) external;
    function onUninstall(bytes calldata data) external;
    function isModuleType(uint256 moduleTypeId) external view returns (bool);
}

/// @dev Execution surface.
interface IERC7579Execution {
    function execute(bytes32 mode, bytes calldata executionCalldata) external payable;
    function executeFromExecutor(bytes32 mode, bytes calldata executionCalldata)
        external
        payable
        returns (bytes[] memory returnData);
}

/// @dev Account introspection.
interface IERC7579AccountConfig {
    function accountId() external view returns (string memory accountImplementationId);
    function supportsExecutionMode(bytes32 encodedMode) external view returns (bool);
    function supportsModule(uint256 moduleTypeId) external view returns (bool);
}

/// @dev Module lifecycle.
interface IERC7579ModuleConfig {
    event ModuleInstalled(uint256 moduleTypeId, address module);
    event ModuleUninstalled(uint256 moduleTypeId, address module);

    function installModule(uint256 moduleTypeId, address module, bytes calldata initData) external;
    function uninstallModule(uint256 moduleTypeId, address module, bytes calldata deInitData) external;
    function isModuleInstalled(uint256 moduleTypeId, address module, bytes calldata additionalContext)
        external
        view
        returns (bool);
}

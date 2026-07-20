// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

// IERC7579 — Minimal modular smart-account interfaces.
// Vendored from OpenZeppelin Contracts `contracts/interfaces/draft-IERC7579.sol` (MIT, the OZ split form).
// Vendored subset — do not add an openzeppelin-contracts dependency. Lattice consumes EXECUTOR (type 2) and
// VALIDATOR (type 1) modules. Interface ids (Solidity excludes inherited fns): IERC7579Execution = 0x3f3f9537,
// IERC7579AccountConfig = 0xbe1d6cf6, IERC7579ModuleConfig = 0x232dbb4a.

import {PackedUserOperation} from "@lattice/interfaces/external/ercs/IAccount.sol";

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

/// @dev Validator module (type 1): authorizes user operations / ERC-1271 signatures on the account's behalf.
///      Selected per-op by the validator address encoded in the top 20 bytes of `userOp.nonce`.
interface IERC7579Validator is IERC7579Module {
    function validateUserOp(PackedUserOperation calldata userOp, bytes32 userOpHash) external returns (uint256);
    function isValidSignatureWithSender(address sender, bytes32 hash, bytes calldata signature)
        external
        view
        returns (bytes4);
}

/// @dev Hook module (type 4): the single global hook that wraps the account's execution surface. `preCheck`
///      runs before the batch (returning opaque context), `postCheck` after — letting it enforce arbitrary
///      pre/post-execution policy (spend guards, allowlists, invariants) and revert to block the execution.
///      The wrap is ATOMIC (`preCheck(); _execute(); postCheck();`, per the ERC-7579 reference): a reverting
///      batch, `preCheck`, or `postCheck` reverts the WHOLE call — including any `preCheck` state effects — so
///      `postCheck` runs only on an otherwise-successful execution, never after a reverted one.
interface IERC7579Hook is IERC7579Module {
    function preCheck(address msgSender, uint256 msgValue, bytes calldata msgData)
        external
        returns (bytes memory hookData);
    function postCheck(bytes calldata hookData) external;
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

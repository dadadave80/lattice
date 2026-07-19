// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

// IERC6900 — Minimal modular smart-account interfaces + packed types for ERC-6900 ("Modular Smart Contract
// Accounts and Modules", FINAL / module-based form). Vendored subset for Lattice's ERC-6900 account flavor (#74).
// Pinned against the spec text (https://eips.ethereum.org/EIPS/eip-6900) and the reference implementation
// github.com/erc6900/reference-implementation @ commit 65892c2dc9464a4ef24e39bed30f0a8140b0c5de: the packed
// ENCODINGS below are the spec (mandatory for cross-impl interop); all account/facet/storage LOGIC is written
// fresh in src/accounts (the reference impl is GPL — NOT a dependency, used for semantics only).
// Names match the finalized spec (IERC6900*), NOT the deprecated plugin/pluginManifest/FunctionReference era.

import {PackedUserOperation} from "@lattice/interfaces/external/ercs/IAccount.sol";

// ---------------------------------------------------------------------------------------------------------
// Packed value types
// ---------------------------------------------------------------------------------------------------------

/// @dev `address module (20 bytes) ‖ uint32 entityId (4 bytes)`, big-endian / left-aligned. Identifies one
///      function (a validation or a hook) inside a module — a module exposes many entities.
type ModuleEntity is bytes24;

/// @dev `ModuleEntity (24 bytes) ‖ flags (uint8, byte 24)`. Flag byte: bit0 `isUserOpValidation` (0x01),
///      bit1 `isSignatureValidation` (0x02), bit2 `isGlobal` (0x04); top 5 bits unused.
type ValidationConfig is bytes25;

/// @dev The flag byte (byte 24) of a {ValidationConfig}, surfaced on its own (e.g. by the account view).
type ValidationFlags is uint8;

/// @dev `ModuleEntity (24 bytes) ‖ flags (uint8, byte 24)`. Flag byte: bit0 hook type (0 = execution,
///      1 = validation; 0x01), bit1 `hasPost` (0x02), bit2 `hasPre` (0x04) — `hasPre`/`hasPost` apply to
///      execution hooks only; top 5 bits unused. The flag byte deliberately OVERLAPS {ValidationConfig}'s —
///      decode a flag byte only with masks for the type it came from.
type HookConfig is bytes25;

// ---------------------------------------------------------------------------------------------------------
// Constants (src/helpers/Constants.sol)
// ---------------------------------------------------------------------------------------------------------

/// @dev Index in a validation `authorization`/signature blob marking where per-validation data ends and the
///      associated hook data begins.
uint8 constant RESERVED_VALIDATION_DATA_INDEX = type(uint8).max;

/// @dev Maximum number of validation-associated hooks installable per validation function.
uint8 constant MAX_VALIDATION_ASSOC_HOOKS = type(uint8).max;

/// @dev Sentinel `entityId` selecting a module's direct-call validation path (the module calls the account
///      directly, bypassing a signature).
uint32 constant DIRECT_CALL_VALIDATION_ENTITY_ID = type(uint32).max;

// ---------------------------------------------------------------------------------------------------------
// Structs
// ---------------------------------------------------------------------------------------------------------

/// @dev A single call in an {IERC6900Account-executeBatch}.
struct Call {
    address target;
    uint256 value;
    bytes data;
}

/// @dev An execution function the module installs on the account.
struct ManifestExecutionFunction {
    bytes4 executionSelector;
    /// @dev If true the function needs no runtime validation and is callable by anyone.
    bool skipRuntimeValidation;
    /// @dev If true the function may be validated by a global validation function.
    bool allowGlobalValidation;
}

/// @dev An execution hook the module installs against a selector.
struct ManifestExecutionHook {
    bytes4 executionSelector;
    uint32 entityId;
    bool isPreHook;
    bool isPostHook;
}

/// @dev How an execution module wants to be installed; MUST stay constant over the module's lifetime.
struct ExecutionManifest {
    ManifestExecutionFunction[] executionFunctions;
    ManifestExecutionHook[] executionHooks;
    /// @dev ERC-165 interface ids to advertise on the account; MUST NOT include {IERC6900Module}'s id.
    bytes4[] interfaceIds;
}

/// @dev {IERC6900AccountView-getExecutionData} return: the install state of one execution selector.
struct ExecutionDataView {
    /// @dev Implementer; equals the account address for a native function.
    address module;
    bool skipRuntimeValidation;
    bool allowGlobalValidation;
    HookConfig[] executionHooks;
}

/// @dev {IERC6900AccountView-getValidationData} return: the install state of one validation function.
struct ValidationDataView {
    ValidationFlags validationFlags;
    HookConfig[] validationHooks;
    HookConfig[] executionHooks;
    bytes4[] selectors;
}

// ---------------------------------------------------------------------------------------------------------
// Module interfaces
// ---------------------------------------------------------------------------------------------------------

// ponytail: minimal IERC165 — no first-party interface exists in src/; inline rather than add a file only
// IERC6900Module consumes. Extract to its own vendored file if a second consumer appears.
interface IERC165 {
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}

/// @dev Base interface every ERC-6900 module implements.
interface IERC6900Module is IERC165 {
    function onInstall(bytes calldata data) external;
    function onUninstall(bytes calldata data) external;
    /// @dev Unique id in the format "vendor.module.semver"; vendor/module names MUST NOT contain a period.
    function moduleId() external view returns (string memory);
}

/// @dev Validation module: authorizes user operations, runtime calls, and ERC-1271 signatures per `entityId`.
interface IERC6900ValidationModule is IERC6900Module {
    /// @return Packed validation data: validAfter (6 bytes) ‖ validUntil (6 bytes) ‖ authorizer (20 bytes).
    function validateUserOp(uint32 entityId, PackedUserOperation calldata userOp, bytes32 userOpHash)
        external
        returns (uint256);

    /// @dev MUST revert to reject the call.
    function validateRuntime(
        address account,
        uint32 entityId,
        address sender,
        uint256 value,
        bytes calldata data,
        bytes calldata authorization
    ) external;

    /// @return ERC-1271 magic value `0x1626ba7e` if valid, or `0xffffffff` if invalid.
    function validateSignature(address account, uint32 entityId, address sender, bytes32 hash, bytes calldata signature)
        external
        view
        returns (bytes4);
}

/// @dev Validation hook module: runs before a validation function (user-op / runtime / signature paths).
interface IERC6900ValidationHookModule is IERC6900Module {
    /// @return Packed validation data; MUST NOT return an authorizer other than 0 or 1.
    function preUserOpValidationHook(uint32 entityId, PackedUserOperation calldata userOp, bytes32 userOpHash)
        external
        returns (uint256);

    /// @dev MUST revert to reject the call.
    function preRuntimeValidationHook(
        uint32 entityId,
        address sender,
        uint256 value,
        bytes calldata data,
        bytes calldata authorization
    ) external;

    /// @dev MUST revert to reject the signature.
    function preSignatureValidationHook(uint32 entityId, address sender, bytes32 hash, bytes calldata signature)
        external
        view;
}

/// @dev Execution module: contributes execution functions (+ their hooks) to the account.
interface IERC6900ExecutionModule is IERC6900Module {
    /// @dev MUST stay constant over the module's lifetime.
    function executionManifest() external pure returns (ExecutionManifest memory);
}

/// @dev Execution hook module: wraps an execution function with pre/post hooks.
interface IERC6900ExecutionHookModule is IERC6900Module {
    /// @return Context passed to the matching post-execution hook (MAY be empty); MUST revert to reject.
    function preExecutionHook(uint32 entityId, address sender, uint256 value, bytes calldata data)
        external
        returns (bytes memory);

    /// @dev MUST revert to reject; `preExecHookData` is the context from the matching pre-execution hook.
    function postExecutionHook(uint32 entityId, bytes calldata preExecHookData) external;
}

// ---------------------------------------------------------------------------------------------------------
// Account interfaces
// ---------------------------------------------------------------------------------------------------------

/// @dev The modular account surface: execution + module configuration.
interface IERC6900Account {
    event ExecutionInstalled(address indexed module, ExecutionManifest manifest);
    event ExecutionUninstalled(address indexed module, bool onUninstallSucceeded, ExecutionManifest manifest);
    event ValidationInstalled(address indexed module, uint32 indexed entityId);
    event ValidationUninstalled(address indexed module, uint32 indexed entityId, bool onUninstallSucceeded);

    function execute(address target, uint256 value, bytes calldata data) external payable returns (bytes memory);

    /// @dev If `target` is an installed module the call SHOULD revert; any sub-call reverting MUST revert all.
    function executeBatch(Call[] calldata calls) external payable returns (bytes[] memory);

    /// @dev `authorization`: first 24 bytes is the {ModuleEntity} selecting runtime validation, rest is its param.
    function executeWithRuntimeValidation(bytes calldata data, bytes calldata authorization)
        external
        payable
        returns (bytes memory);

    function installExecution(address module, ExecutionManifest calldata manifest, bytes calldata installData) external;

    function uninstallExecution(address module, ExecutionManifest calldata manifest, bytes calldata uninstallData)
        external;

    function installValidation(
        ValidationConfig validationConfig,
        bytes4[] calldata selectors,
        bytes calldata installData,
        bytes[] calldata hooks
    ) external;

    function uninstallValidation(
        ModuleEntity validationFunction,
        bytes calldata uninstallData,
        bytes[] calldata hookUninstallData
    ) external;

    /// @dev Unique id in the format "vendor.account.semver"; vendor/account names MUST NOT contain a period.
    function accountId() external view returns (string memory);
}

/// @dev Read-only introspection over installed executions and validations (the ERC-6900 "loupe").
interface IERC6900AccountView {
    /// @dev For a native function the returned `module` is the account address.
    function getExecutionData(bytes4 selector) external view returns (ExecutionDataView memory);

    function getValidationData(ModuleEntity validationFunction) external view returns (ValidationDataView memory);
}

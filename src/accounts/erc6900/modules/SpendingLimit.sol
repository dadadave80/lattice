// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC165, IERC6900ExecutionHookModule, IERC6900Module} from "@lattice/interfaces/external/ercs/IERC6900.sol";

/// @title SpendingLimit
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice A reference ERC-6900 execution-hook module: a cumulative native-value spending cap per
///         `(account, entityId)`. Installed as a PRE-execution hook on `execute` (the native call selector), it
///         decodes the call's value and reverts once the running total would exceed the configured cap — the
///         canonical "session key may spend at most X" permission, expressed as a hook.
/// @dev Standalone module invoked by the account via CALL (`msg.sender` is the account; budget is per-account).
///      The hook receives the wrapped native call's full calldata (`execute(address,uint256,bytes)`), from which
///      it reads the value argument. Reference quality: cumulative-only (no time windows / per-token limits).
contract SpendingLimit is IERC6900ExecutionHookModule {
    /// @notice The cumulative native-value cap for `(account, entityId)`.
    mapping(address account => mapping(uint32 entityId => uint256 cap)) public capOf;
    /// @notice The native value spent so far against `(account, entityId)`.
    mapping(address account => mapping(uint32 entityId => uint256 spent)) public spentOf;

    event CapSet(address indexed account, uint32 indexed entityId, uint256 cap);

    /// @notice The call would push cumulative spending past the cap.
    error SpendCapExceeded(uint256 attempted, uint256 cap);

    /// @inheritdoc IERC6900Module
    /// @dev `data = abi.encode(uint32 entityId, uint256 cap)`.
    function onInstall(bytes calldata data) external {
        (uint32 entityId, uint256 cap) = abi.decode(data, (uint32, uint256));
        capOf[msg.sender][entityId] = cap;
        emit CapSet(msg.sender, entityId, cap);
    }

    /// @inheritdoc IERC6900Module
    /// @dev `data = abi.encode(uint32 entityId)`.
    function onUninstall(bytes calldata data) external {
        uint32 entityId = abi.decode(data, (uint32));
        delete capOf[msg.sender][entityId];
        delete spentOf[msg.sender][entityId];
    }

    /// @inheritdoc IERC6900ExecutionHookModule
    /// @dev `data` is the wrapped `execute(address target, uint256 value, bytes data)` calldata; the cap applies
    ///      to the cumulative `value`.
    function preExecutionHook(uint32 entityId, address, uint256, bytes calldata data) external returns (bytes memory) {
        (, uint256 value,) = abi.decode(data[4:], (address, uint256, bytes));
        uint256 newSpent = spentOf[msg.sender][entityId] + value;
        uint256 cap = capOf[msg.sender][entityId];
        if (newSpent > cap) revert SpendCapExceeded(newSpent, cap);
        spentOf[msg.sender][entityId] = newSpent;
        return "";
    }

    /// @inheritdoc IERC6900ExecutionHookModule
    function postExecutionHook(uint32, bytes calldata) external {}

    /// @inheritdoc IERC6900Module
    function moduleId() external pure returns (string memory) {
        return "lattice.spending-limit.1.0.0";
    }

    /// @inheritdoc IERC165
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC6900Module).interfaceId
            || interfaceId == type(IERC6900ExecutionHookModule).interfaceId;
    }
}

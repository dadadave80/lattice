// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC4337ValidationLib} from "@lattice/accounts/libraries/ERC4337ValidationLib.sol";
import {
    ERC6900ModuleManagerLib,
    ERC6900ModuleManagerStorage,
    ExecutionStorage,
    ValidationStorage
} from "@lattice/accounts/libraries/ERC6900ModuleManagerLib.sol";
import {ERC6900TypesLib} from "@lattice/accounts/libraries/ERC6900TypesLib.sol";
import {IExecutor6900} from "@lattice/interfaces/IExecutor6900.sol";
import {
    Call,
    DIRECT_CALL_VALIDATION_ENTITY_ID,
    HookConfig,
    IERC6900Account,
    IERC6900ExecutionHookModule,
    IERC6900ValidationHookModule,
    IERC6900ValidationModule,
    ModuleEntity,
    ValidationFlags
} from "@lattice/interfaces/external/IERC6900.sol";
import {EnumerableSet} from "@lattice/utils/libraries/EnumerableSet.sol";

/// @dev A captured post-execution hook + the context returned by its matching pre-execution hook. `postExecHook`
///      is empty for a pre-only hook (skipped on the post pass).
struct PostExecToRun {
    bytes preExecHookReturnData;
    ModuleEntity postExecHook;
}

/// @dev Which applicability rule a validation must satisfy for a selector.
enum ValidationCheckType {
    GLOBAL,
    SELECTOR,
    EITHER
}

/// @title ERC6900ExecutorLib
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice The ERC-6900 RUNTIME executor + dispatch pipeline: the `ModularAccount6900` fallback dispatch for
///         installed execution-module selectors, the native `execute` / `executeBatch`, and the explicit-auth
///         `executeWithRuntimeValidation`, plus the runtime-validation pipeline and the execution-hook engine.
/// @dev Re-implemented FRESH from the ERC-6900 reference (erc6900/reference-implementation @ 65892c2). Reads the
///      registries owned by {ERC6900ModuleManagerLib}. Key semantics carried over: execution modules are invoked
///      by CALL (own storage context), NOT delegatecall; exec hooks come from two never-merged sources
///      (validation-associated + selector-associated); pre hooks snapshot their post set before running, post
///      hooks run LIFO and ONLY on success; runtime auth bypasses on EntryPoint / self / `skipRuntimeValidation`
///      and otherwise routes through a direct-call validation. No reentrancy mutex — self-recursion is capped at
///      one level. Lattice deviation: native validation-gated selectors are just `execute`/`executeBatch` (Lattice
///      installs/uninstalls are admin-gated in {ERC6900ModuleManagerLib}, not validation-gated).
library ERC6900ExecutorLib {
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.Bytes4Set;
    using ERC6900TypesLib for HookConfig;
    using ERC6900TypesLib for ModuleEntity;
    using ERC6900TypesLib for ValidationFlags;

    /// @notice Dispatches a call to an installed execution module: auth + pre hooks → CALL module → post hooks.
    ///         Reverts {UnrecognizedFunction} if no module owns the selector.
    function dispatch() internal returns (bytes memory) {
        ERC6900ModuleManagerStorage storage $ = ERC6900ModuleManagerLib.erc6900ModuleManagerStorage();
        address execModule = $._executions[msg.sig].module;
        if (execModule == address(0)) revert IExecutor6900.UnrecognizedFunction(msg.sig);

        (PostExecToRun[] memory postValidator, PostExecToRun[] memory postSelector) =
            _checkPermittedCallerAndAssociatedHooks(msg.data);

        // CALL (not delegatecall): the module runs in its OWN storage context. Full calldata forwarded.
        (bool ok, bytes memory ret) = execModule.call(msg.data);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(ret, 32), mload(ret))
            }
        }

        // Post hooks: selector-set first, then validator-set (the inverse of the pre order).
        _doCachedPostExecHooks(postSelector);
        _doCachedPostExecHooks(postValidator);
        return ret;
    }

    /// @notice `execute(target, value, data)` — a native execution function: validates the caller + runs the
    ///         active validation's exec hooks, then CALLs `target` with `value`.
    function execute(address target, uint256 value, bytes calldata data) internal returns (bytes memory result) {
        (PostExecToRun[] memory postValidator, PostExecToRun[] memory postSelector) =
            _checkPermittedCallerAndAssociatedHooks(msg.data);
        result = _exec(target, value, data);
        _doCachedPostExecHooks(postSelector);
        _doCachedPostExecHooks(postValidator);
    }

    /// @notice `executeBatch(calls)` — atomic; reverts the whole batch on any sub-call failure. No
    ///         `Σ value == msg.value` check — per-call value draws on the account's balance.
    function executeBatch(Call[] calldata calls) internal returns (bytes[] memory results) {
        (PostExecToRun[] memory postValidator, PostExecToRun[] memory postSelector) =
            _checkPermittedCallerAndAssociatedHooks(msg.data);
        results = new bytes[](calls.length);
        for (uint256 i; i < calls.length; ++i) {
            results[i] = _exec(calls[i].target, calls[i].value, calls[i].data);
        }
        _doCachedPostExecHooks(postSelector);
        _doCachedPostExecHooks(postValidator);
    }

    /// @notice `executeWithRuntimeValidation(data, authorization)` — runs the supplied validation (pre-validation
    ///         hooks + `validateRuntime`) + its exec hooks, then self-CALLs `data`.
    function executeWithRuntimeValidation(bytes calldata data, bytes calldata authorization)
        internal
        returns (bytes memory)
    {
        // authorization = ModuleEntity[0:24] ‖ isGlobalValidation flag[24] (==1 ⇒ global) ‖ validation data[25:].
        ModuleEntity vf = _moduleEntityOf(authorization);
        ValidationCheckType t =
            uint8(authorization[24]) == 1 ? ValidationCheckType.GLOBAL : ValidationCheckType.SELECTOR;
        ERC6900ModuleManagerStorage storage $ = ERC6900ModuleManagerLib.erc6900ModuleManagerStorage();

        _checkIfValidationAppliesCallData(data, vf, t);
        _doRuntimeValidation(vf, data, authorization[25:]);

        PostExecToRun[] memory postValidator = _doPreHooks($._validations[vf].executionHooks, data);
        // Self-CALL (no value forwarded): the inner frame sees `msg.sender == address(this)` so the inner dispatch
        // skips direct-call validation, but still runs the inner selector's own exec hooks.
        (bool ok, bytes memory ret) = address(this).call(data);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(ret, 32), mload(ret))
            }
        }
        _doCachedPostExecHooks(postValidator);
        return ret;
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  INTERNAL
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Runtime authorization for a native/module selector + collection of its pre exec hooks. Returns the
    ///      cached post hooks for the validator set and the selector set (run in reverse on the way out).
    function _checkPermittedCallerAndAssociatedHooks(bytes calldata callData)
        private
        returns (PostExecToRun[] memory postValidator, PostExecToRun[] memory postSelector)
    {
        ERC6900ModuleManagerStorage storage $ = ERC6900ModuleManagerLib.erc6900ModuleManagerStorage();
        bytes4 selector = msg.sig;
        // Privileged bypass: the EntryPoint (userOp already validated), a self-call (reentry from a validated
        // entry), or a `skipRuntimeValidation` ("public") execution function — validation is skipped; only the
        // selector's own exec hooks run.
        if (
            msg.sender != ERC4337ValidationLib.entryPoint() && msg.sender != address(this)
                && !$._executions[selector].skipRuntimeValidation
        ) {
            // Direct-call validation: the caller IS the validation module (entityId = type(uint32).max). Having
            // installed such a validation + permitted the selector IS the authorization — pre-validation hooks
            // run, but `validateRuntime` is NOT called (no signature to check).
            ModuleEntity key = ERC6900TypesLib.pack(msg.sender, DIRECT_CALL_VALIDATION_ENTITY_ID);
            _checkIfValidationAppliesCallData(callData, key, ValidationCheckType.EITHER);
            _doPreRuntimeValidationHooks(key, callData);
            postValidator = _doPreHooks($._validations[key].executionHooks, callData);
        }
        postSelector = _doPreHooks($._executions[selector].executionHooks, callData);
    }

    /// @dev Validation applicability for `callData`'s selector + the self-call recursion guard (depth 1).
    function _checkIfValidationAppliesCallData(bytes calldata callData, ModuleEntity vf, ValidationCheckType t)
        private
        view
    {
        bytes4 selector = _selectorOf(callData);
        _checkIfValidationApplies(selector, vf, t);
        if (selector == IERC6900Account.execute.selector) {
            (address target,,) = abi.decode(callData[4:], (address, uint256, bytes));
            if (target == address(this)) revert IExecutor6900.SelfCallRecursionDepthExceeded();
        } else if (selector == IERC6900Account.executeBatch.selector) {
            // Reject ANY self-targeted sub-call (mirroring the single-execute path): a validation-authorized
            // executeBatch must not reach the account's own admin-gated functions via a `msg.sender ==
            // address(this)` self-call (which would satisfy {ERC6900ModuleManagerLib}'s `_authorizeConfig`).
            Call[] memory calls = abi.decode(callData[4:], (Call[]));
            for (uint256 i; i < calls.length; ++i) {
                if (calls[i].target == address(this)) revert IExecutor6900.SelfCallRecursionDepthExceeded();
            }
        }
    }

    function _checkIfValidationApplies(bytes4 selector, ModuleEntity vf, ValidationCheckType t) private view {
        bool ok = t == ValidationCheckType.GLOBAL
            ? _globalValidationApplies(selector, vf)
            : t == ValidationCheckType.SELECTOR
                ? _selectorValidationApplies(selector, vf)
                : _globalValidationApplies(selector, vf) || _selectorValidationApplies(selector, vf);
        if (!ok) revert IExecutor6900.ValidationFunctionMissing(selector);
    }

    function _globalValidationApplies(bytes4 selector, ModuleEntity vf) private view returns (bool) {
        return _globalValidationAllowed(selector)
            && ERC6900ModuleManagerLib.erc6900ModuleManagerStorage()._validations[vf].validationFlags.isGlobal();
    }

    function _selectorValidationApplies(bytes4 selector, ModuleEntity vf) private view returns (bool) {
        return ERC6900ModuleManagerLib.erc6900ModuleManagerStorage()._validations[vf].selectors.contains(selector);
    }

    /// @dev `execute`/`executeBatch` are the native validation-gated selectors (Lattice installs/uninstalls are
    ///      admin-gated in {ERC6900ModuleManagerLib}, not validation-gated); any other selector opts into global
    ///      validation via its own `allowGlobalValidation` flag.
    function _globalValidationAllowed(bytes4 selector) private view returns (bool) {
        if (selector == IERC6900Account.execute.selector || selector == IERC6900Account.executeBatch.selector) {
            return true;
        }
        return ERC6900ModuleManagerLib.erc6900ModuleManagerStorage()._executions[selector].allowGlobalValidation;
    }

    /// @dev Runs `vf`'s pre-runtime-validation hooks then its `validateRuntime` (the explicit-auth path, unlike
    ///      the direct-call path which only runs the hooks).
    function _doRuntimeValidation(ModuleEntity vf, bytes calldata data, bytes calldata authData) private {
        _doPreRuntimeValidationHooks(vf, data);
        (address module, uint32 entityId) = vf.unpack();
        try IERC6900ValidationModule(module)
            .validateRuntime(address(this), entityId, msg.sender, msg.value, data, authData) {}
        catch (bytes memory reason) {
            revert IExecutor6900.RuntimeValidationFunctionReverted(module, entityId, reason);
        }
    }

    function _moduleEntityOf(bytes calldata auth) private pure returns (ModuleEntity me) {
        bytes24 raw;
        assembly ("memory-safe") {
            raw := and(calldataload(auth.offset), 0xffffffffffffffffffffffffffffffffffffffffffffffff0000000000000000)
        }
        me = ModuleEntity.wrap(raw);
    }

    function _doPreRuntimeValidationHooks(ModuleEntity vf, bytes calldata data) private {
        HookConfig[] storage hooks =
        ERC6900ModuleManagerLib.erc6900ModuleManagerStorage()._validations[vf].validationHooks;
        uint256 n = hooks.length;
        for (uint256 i; i < n; ++i) {
            (address module, uint32 entityId) = hooks[i].moduleEntity().unpack();
            // ponytail: per-hook authorization segmentation is deferred to the signature paths (#4/#5); runtime
            // pre-validation hooks receive empty authorization, as the reference's direct-call path does.
            try IERC6900ValidationHookModule(module)
                .preRuntimeValidationHook(entityId, msg.sender, msg.value, data, "") {}
            catch (bytes memory reason) {
                revert IExecutor6900.PreRuntimeValidationHookFailed(module, entityId, reason);
            }
        }
    }

    /// @dev Snapshot the post-hook set BEFORE running any pre hook (so a hook that mutates the set cannot change
    ///      which post hooks fire), then run pre hooks, caching each pre's return data for its matching post hook.
    function _doPreHooks(EnumerableSet.Bytes32Set storage hooks, bytes calldata data)
        private
        returns (PostExecToRun[] memory toRun)
    {
        bytes32[] memory snapshot = hooks.values();
        uint256 n = snapshot.length;
        toRun = new PostExecToRun[](n);
        for (uint256 i; i < n; ++i) {
            HookConfig hc = HookConfig.wrap(bytes25(snapshot[i]));
            bool hasPost = hc.hasPostHook();
            if (hasPost) toRun[i].postExecHook = hc.moduleEntity();
            if (hc.hasPreHook()) {
                bytes memory ret = _runPreExecHook(hc.moduleEntity(), data);
                if (hasPost) toRun[i].preExecHookReturnData = ret;
            }
        }
    }

    function _runPreExecHook(ModuleEntity hookEntity, bytes calldata data) private returns (bytes memory) {
        (address module, uint32 entityId) = hookEntity.unpack();
        try IERC6900ExecutionHookModule(module).preExecutionHook(entityId, msg.sender, msg.value, data) returns (
            bytes memory ctx
        ) {
            return ctx;
        } catch (bytes memory reason) {
            revert IExecutor6900.PreExecHookReverted(module, entityId, reason);
        }
    }

    /// @dev Run cached post hooks LIFO; pre-only entries (empty `postExecHook`) are skipped. Post hooks run only on
    ///      the success path — a reverting body bubbles before this is reached.
    function _doCachedPostExecHooks(PostExecToRun[] memory toRun) private {
        for (uint256 i = toRun.length; i > 0; --i) {
            PostExecToRun memory p = toRun[i - 1];
            if (p.postExecHook.isEmpty()) continue;
            (address module, uint32 entityId) = p.postExecHook.unpack();
            try IERC6900ExecutionHookModule(module).postExecutionHook(entityId, p.preExecHookReturnData) {}
            catch (bytes memory reason) {
                revert IExecutor6900.PostExecHookReverted(module, entityId, reason);
            }
        }
    }

    /// @dev Raw target CALL with value; bubbles the target's revert data verbatim. The executor NEVER self-calls
    ///      the account — a self-call would bridge a validation-authorized execute/executeBatch into the
    ///      admin-gated config functions (`msg.sender == address(this)` satisfies `_authorizeConfig`). This is the
    ///      backstop for the privileged bypass paths (EntryPoint / self / `skipRuntimeValidation`), which skip the
    ///      applicability guard entirely.
    function _exec(address target, uint256 value, bytes calldata data) private returns (bytes memory) {
        if (target == address(this)) revert IExecutor6900.SelfCallRecursionDepthExceeded();
        (bool ok, bytes memory ret) = target.call{value: value}(data);
        if (!ok) {
            assembly ("memory-safe") {
                revert(add(ret, 32), mload(ret))
            }
        }
        return ret;
    }

    function _selectorOf(bytes calldata data) private pure returns (bytes4 s) {
        assembly ("memory-safe") {
            s := and(calldataload(data.offset), 0xffffffff00000000000000000000000000000000000000000000000000000000)
        }
    }
}

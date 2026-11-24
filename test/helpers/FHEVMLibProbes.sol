// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FHE} from "@lattice-test/helpers/fhevm/solidity/lib/FHE.sol";
import {ebool, euint64, externalEuint64} from "@lattice/interfaces/external/fhevm/EncryptedTypes.sol";
import {IACL} from "@lattice/interfaces/external/fhevm/IACL.sol";
import {CoprocessorConfig, FHEVMLib} from "@lattice/privacy/libraries/FHEVMLib.sol";
import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

/// @notice The surface both probes expose, so one call runs either {FHEVMLib} or the `FHE.sol` oracle.
interface IFHEVMProbe {
    /// @notice `asEuint64(v)`, then `allowThis` and `allow(msg.sender)`.
    function seed64(uint64 v) external returns (bytes32);

    /// @notice `asEbool(v)`, then `allowThis` and `allow(msg.sender)`.
    function seedBool(bool v) external returns (bytes32);

    /// @notice Runs member `id` (0 to 18) over the operands. `bool` results are returned as
    ///         `bytes32(uint256(x))`; ids 17 and 18 return `keccak256(abi.encode(success, updated))`.
    function op(uint8 id, bytes32 a, bytes32 b, bytes32 c, uint64 s, bytes calldata data) external returns (bytes32);

    /// @notice The OpenZeppelin Confidential Contracts 0.5.3 `ERC7984._update` sequence for a non-zero `from`
    ///         and `to`, both `msg.sender`, with the recipient balance uninitialized.
    function update(uint64 balance, uint64 amount, bool fromZero) external returns (bytes32 next, bytes32 moved);
}

/// @notice {IFHEVMProbe} over {FHEVMLib}, the code under test. {FHEVMLib} has no `ebool` grant member, so
///         {seedBool} grants through the access control list (ACL) directly; only {RefProbe} seeds in the gate.
contract ThinProbe is IFHEVMProbe {
    function seed64(uint64 v) external returns (bytes32) {
        euint64 x = FHEVMLib.asEuint64(v);
        FHEVMLib.allowThis(x);
        FHEVMLib.allow(x, msg.sender);
        return euint64.unwrap(x);
    }

    function seedBool(bool v) external returns (bytes32) {
        bytes32 x = ebool.unwrap(FHEVMLib.asEbool(v));
        IACL(FHEVMLib.config().acl).allow(x, address(this));
        IACL(FHEVMLib.config().acl).allow(x, msg.sender);
        return x;
    }

    function op(uint8 id, bytes32 a, bytes32 b, bytes32 c, uint64 s, bytes calldata data) external returns (bytes32) {
        euint64 ea = euint64.wrap(a);
        euint64 eb = euint64.wrap(b);
        if (id == 0) return _b(FHEVMLib.isInitialized(ea));
        if (id == 1) return _b(FHEVMLib.isInitialized(ebool.wrap(a)));
        if (id == 2) return euint64.unwrap(FHEVMLib.asEuint64(s));
        if (id == 3) return ebool.unwrap(FHEVMLib.asEbool(s % 2 == 1));
        if (id == 4) return euint64.unwrap(FHEVMLib.fromExternal(externalEuint64.wrap(a), data));
        if (id == 5) return euint64.unwrap(FHEVMLib.add(ea, eb));
        if (id == 6) return euint64.unwrap(FHEVMLib.sub(ea, eb));
        if (id == 7) return ebool.unwrap(FHEVMLib.ge(ea, eb));
        if (id == 8) return ebool.unwrap(FHEVMLib.eq(ea, s));
        if (id == 9) return euint64.unwrap(FHEVMLib.select(ebool.wrap(a), eb, euint64.wrap(c)));
        if (id == 10) return _b(FHEVMLib.isAllowed(ea, msg.sender));
        if (id == 11) return _b(FHEVMLib.isAllowed(ebool.wrap(a), msg.sender));
        if (id == 12) return euint64.unwrap(FHEVMLib.allow(ea, msg.sender));
        if (id == 13) return euint64.unwrap(FHEVMLib.allowThis(ea));
        if (id == 14) return euint64.unwrap(FHEVMLib.allowTransient(ea, msg.sender));
        if (id == 15) return euint64.unwrap(FHEVMLib.makePubliclyDecryptable(ea));
        if (id == 16) {
            FHEVMLib.checkSignatures(_one(a), abi.encode(uint256(s)), data);
            return 0;
        }
        (ebool success, euint64 updated) = id == 17 ? FHEVMLib.tryIncrease(ea, eb) : FHEVMLib.tryDecrease(ea, eb);
        return keccak256(abi.encode(success, updated));
    }

    function update(uint64 balance, uint64 amount, bool fromZero) external returns (bytes32 next, bytes32 moved) {
        euint64 value = FHEVMLib.asEuint64(amount);
        euint64 fromBalance = fromZero ? euint64.wrap(0) : FHEVMLib.asEuint64(balance);
        euint64 toBalance;
        (ebool success, euint64 ptr) = FHEVMLib.tryDecrease(fromBalance, value);
        FHEVMLib.allowThis(ptr);
        FHEVMLib.allow(ptr, msg.sender);
        next = euint64.unwrap(ptr);
        euint64 transferred = FHEVMLib.select(success, value, FHEVMLib.asEuint64(0));
        ptr = FHEVMLib.add(toBalance, transferred);
        FHEVMLib.allowThis(ptr);
        FHEVMLib.allow(ptr, msg.sender);
        FHEVMLib.allow(transferred, msg.sender);
        FHEVMLib.allowThis(transferred);
        moved = euint64.unwrap(transferred);
    }

    function _b(bool x) private pure returns (bytes32) {
        return bytes32(uint256(x ? 1 : 0));
    }

    function _one(bytes32 x) private pure returns (bytes32[] memory l) {
        l = new bytes32[](1);
        l[0] = x;
    }
}

/// @notice {IFHEVMProbe} over Zama's `FHE.sol` 0.13.4, the oracle. Ids 17 and 18 and {update} run the
///         OpenZeppelin Confidential Contracts 0.5.3 `FHESafeMath.sol:20-43` lines over `FHE`.
contract RefProbe is IFHEVMProbe {
    function seed64(uint64 v) external returns (bytes32) {
        euint64 x = FHE.asEuint64(v);
        FHE.allowThis(x);
        FHE.allow(x, msg.sender);
        return euint64.unwrap(x);
    }

    function seedBool(bool v) external returns (bytes32) {
        ebool x = FHE.asEbool(v);
        FHE.allowThis(x);
        FHE.allow(x, msg.sender);
        return ebool.unwrap(x);
    }

    function op(uint8 id, bytes32 a, bytes32 b, bytes32 c, uint64 s, bytes calldata data) external returns (bytes32) {
        euint64 ea = euint64.wrap(a);
        euint64 eb = euint64.wrap(b);
        if (id == 0) return _b(FHE.isInitialized(ea));
        if (id == 1) return _b(FHE.isInitialized(ebool.wrap(a)));
        if (id == 2) return euint64.unwrap(FHE.asEuint64(s));
        if (id == 3) return ebool.unwrap(FHE.asEbool(s % 2 == 1));
        if (id == 4) return euint64.unwrap(FHE.fromExternal(externalEuint64.wrap(a), data));
        if (id == 5) return euint64.unwrap(FHE.add(ea, eb));
        if (id == 6) return euint64.unwrap(FHE.sub(ea, eb));
        if (id == 7) return ebool.unwrap(FHE.ge(ea, eb));
        if (id == 8) return ebool.unwrap(FHE.eq(ea, s));
        if (id == 9) return euint64.unwrap(FHE.select(ebool.wrap(a), eb, euint64.wrap(c)));
        if (id == 10) return _b(FHE.isAllowed(ea, msg.sender));
        if (id == 11) return _b(FHE.isAllowed(ebool.wrap(a), msg.sender));
        if (id == 12) return euint64.unwrap(FHE.allow(ea, msg.sender));
        if (id == 13) return euint64.unwrap(FHE.allowThis(ea));
        if (id == 14) return euint64.unwrap(FHE.allowTransient(ea, msg.sender));
        if (id == 15) return euint64.unwrap(FHE.makePubliclyDecryptable(ea));
        if (id == 16) {
            FHE.checkSignatures(_one(a), abi.encode(uint256(s)), data);
            return 0;
        }
        (ebool success, euint64 updated) = id == 17 ? _tryIncrease(ea, eb) : _tryDecrease(ea, eb);
        return keccak256(abi.encode(success, updated));
    }

    function update(uint64 balance, uint64 amount, bool fromZero) external returns (bytes32 next, bytes32 moved) {
        euint64 value = FHE.asEuint64(amount);
        euint64 fromBalance = fromZero ? euint64.wrap(0) : FHE.asEuint64(balance);
        euint64 toBalance;
        (ebool success, euint64 ptr) = _tryDecrease(fromBalance, value);
        FHE.allowThis(ptr);
        FHE.allow(ptr, msg.sender);
        next = euint64.unwrap(ptr);
        euint64 transferred = FHE.select(success, value, FHE.asEuint64(0));
        ptr = FHE.add(toBalance, transferred);
        FHE.allowThis(ptr);
        FHE.allow(ptr, msg.sender);
        FHE.allow(transferred, msg.sender);
        FHE.allowThis(transferred);
        moved = euint64.unwrap(transferred);
    }

    /// @dev OpenZeppelin Confidential Contracts 0.5.3 `FHESafeMath.tryIncrease` (FHESafeMath.sol:20-27).
    function _tryIncrease(euint64 oldValue, euint64 delta) private returns (ebool success, euint64 updated) {
        if (!FHE.isInitialized(oldValue)) {
            return (FHE.asEbool(true), delta);
        }
        euint64 newValue = FHE.add(oldValue, delta);
        success = FHE.ge(newValue, oldValue);
        updated = FHE.select(success, newValue, oldValue);
    }

    /// @dev OpenZeppelin Confidential Contracts 0.5.3 `FHESafeMath.tryDecrease` (FHESafeMath.sol:34-43).
    function _tryDecrease(euint64 oldValue, euint64 delta) private returns (ebool success, euint64 updated) {
        if (!FHE.isInitialized(oldValue)) {
            if (!FHE.isInitialized(delta)) {
                return (FHE.asEbool(true), oldValue);
            }
            return (FHE.eq(delta, 0), FHE.asEuint64(0));
        }
        success = FHE.ge(oldValue, delta);
        updated = FHE.select(success, FHE.sub(oldValue, delta), oldValue);
    }

    function _b(bool x) private pure returns (bytes32) {
        return bytes32(uint256(x ? 1 : 0));
    }

    function _one(bytes32 x) private pure returns (bytes32[] memory l) {
        l = new bytes32[](1);
        l[0] = x;
    }
}

/// @notice Seeds a foreign operand: a nonce-bearing input handle allowed to this contract and not to any probe.
contract Seeder {
    constructor() {
        FHEVMLib.setCoprocessorForChain();
    }

    function seedFromInput(externalEuint64 x, bytes calldata proof) external returns (bytes32) {
        euint64 v = FHEVMLib.fromExternal(x, proof);
        FHEVMLib.allowThis(v);
        return euint64.unwrap(v);
    }
}

/// @notice Runs one call against {RefProbe} and then {ThinProbe} at the same address from the same state, and
///         asserts both produce the same success flag, return or revert data, account and storage accesses
///         and logs.
abstract contract FHEVMLibDiff is Test {
    address internal constant PROBE_AT = address(0xD1FF);

    /// @dev Places the chosen probe's runtime code at {PROBE_AT} and writes `cfg` into its configuration slot.
    function _install(bool thin, CoprocessorConfig memory cfg) internal {
        deployCodeTo(thin ? "FHEVMLibProbes.sol:ThinProbe" : "FHEVMLibProbes.sol:RefProbe", PROBE_AT);
        bytes32 slot = FHEVMLib.CONFIG_SLOT;
        vm.store(PROBE_AT, slot, bytes32(uint256(uint160(cfg.acl))));
        vm.store(PROBE_AT, bytes32(uint256(slot) + 1), bytes32(uint256(uint160(cfg.executor))));
        vm.store(PROBE_AT, bytes32(uint256(slot) + 2), bytes32(uint256(uint160(cfg.kmsVerifier))));
    }

    /// @dev Runs `callData` from `caller` through both probes from one snapshot and asserts the traces match.
    ///      Returns the reference run's success flag, return or revert data and account access count.
    function _diff(address caller, bytes memory callData)
        internal
        returns (bool ok, bytes memory ret, uint256 accessCount)
    {
        CoprocessorConfig memory cfg = FHEVMLib.hostsFor(block.chainid);
        uint256 snap = vm.snapshotState();
        _install(false, cfg);
        (bool okRef, bytes memory retRef, Vm.AccountAccess[] memory accRef, Vm.Log[] memory logsRef) =
            _run(caller, callData);
        vm.revertToState(snap);
        _install(true, cfg);
        (bool okThin, bytes memory retThin, Vm.AccountAccess[] memory accThin, Vm.Log[] memory logsThin) =
            _run(caller, callData);
        vm.revertToStateAndDelete(snap);

        assertEq(okRef, okThin, "call success");
        assertEq(retRef, retThin, "return or revert data");
        assertEq(accRef.length, accThin.length, "account access count");
        for (uint256 i; i < accRef.length; ++i) {
            _assertAccess(accRef[i], accThin[i]);
        }
        assertEq(logsRef.length, logsThin.length, "log count");
        for (uint256 i; i < logsRef.length; ++i) {
            assertEq(logsRef[i].emitter, logsThin[i].emitter, "log emitter");
            assertEq(logsRef[i].topics, logsThin[i].topics, "log topics");
            assertEq(logsRef[i].data, logsThin[i].data, "log data");
        }
        return (okRef, retRef, accRef.length);
    }

    /// @dev A one-element handle list.
    function _one(bytes32 h) internal pure returns (bytes32[] memory l) {
        l = new bytes32[](1);
        l[0] = h;
    }

    function _run(address caller, bytes memory callData)
        private
        returns (bool ok, bytes memory ret, Vm.AccountAccess[] memory accesses, Vm.Log[] memory logs)
    {
        vm.recordLogs();
        vm.startStateDiffRecording();
        vm.prank(caller);
        (ok, ret) = PROBE_AT.call(callData);
        accesses = vm.stopAndReturnStateDiff();
        logs = vm.getRecordedLogs();
    }

    function _assertAccess(Vm.AccountAccess memory r, Vm.AccountAccess memory t) private pure {
        assertEq(uint256(r.kind), uint256(t.kind), "access kind");
        assertEq(r.account, t.account, "access account");
        assertEq(r.accessor, t.accessor, "access accessor");
        assertEq(r.data, t.data, "access data");
        assertEq(r.reverted, t.reverted, "access reverted");
        assertEq(r.storageAccesses.length, t.storageAccesses.length, "storage access count");
        for (uint256 j; j < r.storageAccesses.length; ++j) {
            assertEq(r.storageAccesses[j].slot, t.storageAccesses[j].slot, "storage slot");
            assertEq(r.storageAccesses[j].isWrite, t.storageAccesses[j].isWrite, "storage isWrite");
            assertEq(r.storageAccesses[j].newValue, t.storageAccesses[j].newValue, "storage newValue");
        }
    }
}

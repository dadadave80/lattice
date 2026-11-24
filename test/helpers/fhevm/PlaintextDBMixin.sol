// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {FHEEvents} from "./fhevm-host/contracts/FHEEvents.sol";
import {fhevmExecutorAdd} from "./fhevm-host/addresses/FHEVMHostAddresses.sol";
import {FheType} from "./fhevm-host/contracts/shared/FheType.sol";
import {CleartextArithmetic} from "./cleartext/CleartextArithmetic.sol";
import {FheTypeBitWidth} from "./cleartext/FheTypeBitWidth.sol";

abstract contract PlaintextDBMixin is Test, FHEEvents {
    mapping(bytes32 => uint256) internal _plaintexts;

    function _processNewLogs() internal {
        Vm.Log[] memory logs = vm.getRecordedLogs();
        _processNewLogs(logs);
    }

    function _processNewLogs(Vm.Log[] memory logs) internal {
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].emitter != fhevmExecutorAdd) {
                continue;
            }
            _dispatchFheEvent(logs[i]);
        }
    }

    function _dispatchFheEvent(Vm.Log memory logEntry) internal {
        bytes32 selector = logEntry.topics[0];

        if (selector == FheAdd.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.fheAdd);
        } else if (selector == FheSub.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.fheSub);
        } else if (selector == FheMul.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.fheMul);
        } else if (selector == FheDiv.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.fheDiv);
        } else if (selector == FheRem.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.fheRem);
        } else if (selector == FheBitAnd.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.fheBitAnd);
        } else if (selector == FheBitOr.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.fheBitOr);
        } else if (selector == FheBitXor.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.fheBitXor);
        } else if (selector == FheShl.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.fheShl);
        } else if (selector == FheShr.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.fheShr);
        } else if (selector == FheRotl.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.fheRotl);
        } else if (selector == FheRotr.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.fheRotr);
        } else if (selector == FheEq.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.fheEq);
        } else if (selector == FheNe.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.fheNe);
        } else if (selector == FheGe.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.fheGe);
        } else if (selector == FheGt.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.fheGt);
        } else if (selector == FheLe.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.fheLe);
        } else if (selector == FheLt.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.fheLt);
        } else if (selector == FheMin.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.fheMin);
        } else if (selector == FheMax.selector) {
            _handleBinaryOp(logEntry.data, CleartextArithmetic.fheMax);
        } else if (selector == FheNeg.selector) {
            _handleUnaryOp(logEntry.data, CleartextArithmetic.fheNeg);
        } else if (selector == FheNot.selector) {
            _handleUnaryOp(logEntry.data, CleartextArithmetic.fheNot);
        } else if (selector == TrivialEncrypt.selector) {
            _handleTrivialEncrypt(logEntry.data);
        } else if (selector == Cast.selector) {
            _handleCast(logEntry.data);
        } else if (selector == FheIfThenElse.selector) {
            _handleIfThenElse(logEntry.data);
        } else if (selector == FheRand.selector) {
            _handleRand(logEntry.data);
        } else if (selector == FheRandBounded.selector) {
            _handleRandBounded(logEntry.data);
        } else if (selector == VerifyInput.selector) {
            _handleVerifyInput(logEntry.data);
        } else if (selector == FheSum.selector) {
            _handleSum(logEntry.data);
        } else if (selector == FheIsIn.selector) {
            _handleIsIn(logEntry.data);
        }
    }

    // --- Binary ops (lhs, rhs, scalarByte, result) ---

    function _handleBinaryOp(bytes memory data, function(uint256, uint256, uint8, bytes1) pure returns (uint256) op)
        private
    {
        (bytes32 lhs, bytes32 rhs, bytes1 scalarByte, bytes32 result) =
            abi.decode(data, (bytes32, bytes32, bytes1, bytes32));
        uint256 rhsRaw = (scalarByte == 0x01) ? uint256(rhs) : _plaintexts[rhs];
        _plaintexts[result] = op(_plaintexts[lhs], rhsRaw, uint8(_typeOf(lhs)), scalarByte);
    }

    // --- Unary ops (ct, result) ---

    function _handleUnaryOp(bytes memory data, function(uint256, uint8) pure returns (uint256) op) private {
        (bytes32 ct, bytes32 result) = abi.decode(data, (bytes32, bytes32));
        _plaintexts[result] = op(_plaintexts[ct], uint8(_typeOf(ct)));
    }

    // --- Special ops ---

    function _handleTrivialEncrypt(bytes memory data) private {
        (uint256 pt, uint8 toTypeRaw, bytes32 result) = abi.decode(data, (uint256, uint8, bytes32));
        _plaintexts[result] = CleartextArithmetic.normalizePlaintextToType(pt, toTypeRaw);
    }

    function _handleCast(bytes memory data) private {
        (bytes32 ct, uint8 toTypeRaw, bytes32 result) = abi.decode(data, (bytes32, uint8, bytes32));
        _plaintexts[result] = CleartextArithmetic.fheCast(_plaintexts[ct], toTypeRaw);
    }

    function _handleIfThenElse(bytes memory data) private {
        (bytes32 control, bytes32 ifTrue, bytes32 ifFalse, bytes32 result) =
            abi.decode(data, (bytes32, bytes32, bytes32, bytes32));
        _plaintexts[result] =
            CleartextArithmetic.fheIfThenElse(_plaintexts[control], _plaintexts[ifTrue], _plaintexts[ifFalse]);
    }

    function _handleRand(bytes memory data) private {
        (uint8 randTypeRaw, bytes16 seed, bytes32 result) = abi.decode(data, (uint8, bytes16, bytes32));
        _plaintexts[result] = CleartextArithmetic.rand(seed, FheTypeBitWidth.bitWidthForType(randTypeRaw));
    }

    function _handleRandBounded(bytes memory data) private {
        (uint256 upperBound,, bytes16 seed, bytes32 result) = abi.decode(data, (uint256, uint8, bytes16, bytes32));
        _plaintexts[result] = CleartextArithmetic.randBounded(seed, upperBound);
    }

    function _handleVerifyInput(bytes memory data) private pure {
        (bytes32 inputHandle,,,, bytes32 result) = abi.decode(data, (bytes32, address, bytes, uint8, bytes32));
        assert(inputHandle == result);
    }

    function _handleSum(bytes memory data) private {
        (bytes32[] memory values, bytes32 result) = abi.decode(data, (bytes32[], bytes32));
        uint8 resultType = uint8(_typeOf(result));
        uint256 acc;
        for (uint256 i = 0; i < values.length; i++) {
            acc = CleartextArithmetic.fheAdd(acc, _plaintexts[values[i]], resultType, 0x00);
        }
        _plaintexts[result] = acc;
    }

    function _handleIsIn(bytes memory data) private {
        (bytes32 value, bytes32[] memory values, bytes32 result) = abi.decode(data, (bytes32, bytes32[], bytes32));
        uint256 found;
        for (uint256 i = 0; i < values.length; i++) {
            if (_plaintexts[values[i]] == _plaintexts[value]) {
                found = 1;
                break;
            }
        }
        _plaintexts[result] = found;
    }

    // --- Shared helpers ---

    function _typeOf(bytes32 handle) internal pure returns (FheType) {
        return FheType(uint8(handle[30]));
    }

    function _seedPlaintext(bytes32 handle, uint256 value) internal {
        _plaintexts[handle] = value;
    }

    function _readPlaintext(bytes32 handle) internal returns (uint256) {
        _processNewLogs();
        return _plaintexts[handle];
    }
}

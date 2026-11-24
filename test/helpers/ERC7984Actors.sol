// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {aclAdd, fhevmExecutorAdd} from "@lattice-test/helpers/fhevm/fhevm-host/addresses/FHEVMHostAddresses.sol";
import {ebool, euint64} from "@lattice/interfaces/external/fhevm/EncryptedTypes.sol";
import {IACL} from "@lattice/interfaces/external/fhevm/IACL.sol";
import {IFHEVMExecutor} from "@lattice/interfaces/external/fhevm/IFHEVMExecutor.sol";
import {IERC7984, IERC7984Receiver} from "@lattice/interfaces/tokens/IERC7984.sol";

/// @dev Executor type ordinal of an encrypted boolean.
uint8 constant TYPE_BOOL = 0;

/// @title HandleMaker
/// @notice Test-only: makes a trivially encrypted handle of any type and persistently allows it to a chosen set of
///         accounts, in one call.
contract HandleMaker {
    function make(uint256 value, uint8 fheType, address[] calldata allowed) external returns (bytes32 handle) {
        handle = IFHEVMExecutor(fhevmExecutorAdd).trivialEncrypt(value, fheType);
        for (uint256 i; i < allowed.length; ++i) {
            IACL(aclAdd).allow(handle, allowed[i]);
        }
    }
}

/// @dev Returns an encrypted boolean the token may use for this transaction, as OpenZeppelin's receiver mock does.
abstract contract BoolReceiver is IERC7984Receiver {
    function _reply(bool value) internal returns (ebool result) {
        bytes32 handle = IFHEVMExecutor(fhevmExecutorAdd).trivialEncrypt(value ? 1 : 0, TYPE_BOOL);
        IACL(aclAdd).allowTransient(handle, msg.sender);
        result = ebool.wrap(handle);
    }
}

/// @notice Accepts every transfer.
contract AcceptReceiver is BoolReceiver {
    function onConfidentialTransferReceived(address, address, euint64, bytes calldata) external returns (ebool) {
        return _reply(true);
    }
}

/// @notice Rejects every transfer, so the token refunds it.
contract RejectReceiver is BoolReceiver {
    function onConfidentialTransferReceived(address, address, euint64, bytes calldata) external returns (ebool) {
        return _reply(false);
    }
}

/// @notice Forwards the received amount to `bob`, then rejects: the refund finds an empty balance.
contract SpendThenRejectReceiver is BoolReceiver {
    IERC7984 internal immutable token;
    address internal immutable bob;

    constructor(IERC7984 token_, address bob_) {
        token = token_;
        bob = bob_;
    }

    function onConfidentialTransferReceived(address, address, euint64 amount, bytes calldata) external returns (ebool) {
        token.confidentialTransfer(bob, amount);
        return _reply(false);
    }
}

/// @notice Returns the uninitialized (zero) handle.
contract UninitializedReceiver is IERC7984Receiver {
    function onConfidentialTransferReceived(address, address, euint64, bytes calldata) external pure returns (ebool) {
        return ebool.wrap(0);
    }
}

/// @notice Returns an encrypted boolean allowed only to the {HandleMaker}, which the receiver itself may not use.
contract ForeignBoolReceiver is IERC7984Receiver {
    bytes32 public handle;

    constructor(HandleMaker maker) {
        address[] memory allowed = new address[](1);
        allowed[0] = address(maker);
        handle = maker.make(1, TYPE_BOOL, allowed);
    }

    function onConfidentialTransferReceived(address, address, euint64, bytes calldata) external view returns (ebool) {
        return ebool.wrap(handle);
    }
}

/// @notice Returns the received `euint64` amount, which it may use, typed as an `ebool`.
contract Euint64AsBoolReceiver is IERC7984Receiver {
    function onConfidentialTransferReceived(address, address, euint64 amount, bytes calldata)
        external
        pure
        returns (ebool)
    {
        return ebool.wrap(euint64.unwrap(amount));
    }
}

/// @notice Reverts with no data.
contract EmptyRevertReceiver is IERC7984Receiver {
    function onConfidentialTransferReceived(address, address, euint64, bytes calldata) external pure returns (ebool) {
        revert();
    }
}

/// @notice Reverts with `Error(reason)`.
contract StringRevertReceiver is IERC7984Receiver {
    string internal reason;

    constructor(string memory reason_) {
        reason = reason_;
    }

    function onConfidentialTransferReceived(address, address, euint64, bytes calldata) external view returns (ebool) {
        revert(reason);
    }
}

/// @notice Records the operator the token reports, then accepts.
contract OperatorRecordingReceiver is BoolReceiver {
    address public lastOperator;

    function onConfidentialTransferReceived(address operator, address, euint64, bytes calldata)
        external
        returns (ebool)
    {
        lastOperator = operator;
        return _reply(true);
    }
}

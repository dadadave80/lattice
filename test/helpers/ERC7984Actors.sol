// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {aclAdd, fhevmExecutorAdd} from "@lattice-test/helpers/fhevm/fhevm-host/addresses/FHEVMHostAddresses.sol";
import {IACL as IHostACL} from "@lattice-test/helpers/fhevm/generated/interfaces/IACL.sol";
import {ebool, euint64, externalEuint64} from "@lattice/interfaces/external/fhevm/EncryptedTypes.sol";
import {IACL} from "@lattice/interfaces/external/fhevm/IACL.sol";
import {IFHEVMExecutor} from "@lattice/interfaces/external/fhevm/IFHEVMExecutor.sol";
import {IERC7984, IERC7984Disclosure, IERC7984Receiver} from "@lattice/interfaces/tokens/IERC7984.sol";
import {IERC7984Mintable} from "@lattice/interfaces/tokens/IERC7984Mintable.sol";
import {FHEVMLib} from "@lattice/privacy/libraries/FHEVMLib.sol";

/// @dev Executor type ordinal of an encrypted boolean.
uint8 constant TYPE_BOOL = 0;

/// @dev An empty contract, so a cut can route a selector to an address that has code.
contract SelectorStub {}

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

/// @notice An operator that pulls a proven amount from `holder` and requests its disclosure in one call, using the
///         transient grant on `transferred` (spec E9: the proof-free overload needs a handle allowed to the operator).
contract OperatorDiscloser {
    function pullAndDisclose(IERC7984 token, address holder, address to, externalEuint64 amount, bytes calldata proof)
        external
        returns (bytes32)
    {
        euint64 transferred = token.confidentialTransferFrom(holder, to, amount, proof);
        IERC7984Disclosure(address(token)).requestDiscloseEncryptedAmount(transferred);
        return euint64.unwrap(transferred);
    }
}

/// @notice Makes the received `sent` handle publicly decryptable during the callback, records it, then accepts.
contract PublishSentReceiver is BoolReceiver {
    bytes32 public lastSent;

    function onConfidentialTransferReceived(address, address, euint64 amount, bytes calldata) external returns (ebool) {
        lastSent = euint64.unwrap(amount);
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = lastSent;
        IACL(aclAdd).allowForDecryption(handles);
        return _reply(true);
    }
}

/// @notice Wipes every transient grant of the transaction, then accepts with a freshly allowed encrypted true.
contract CleanTransientReceiver is BoolReceiver {
    function onConfidentialTransferReceived(address, address, euint64, bytes calldata) external returns (ebool) {
        IHostACL(aclAdd).cleanTransientStorage();
        return _reply(true);
    }
}

/// @notice Re-enters the token with the received amount, sending it to `to`, then accepts. Mode 0 re-enters
///         `confidentialTransfer`; mode 1 re-enters `confidentialTransferAndCall`.
contract ReentrantReceiver is BoolReceiver {
    IERC7984 internal immutable token;
    address internal immutable to;
    uint8 internal immutable mode;

    constructor(IERC7984 token_, address to_, uint8 mode_) {
        token = token_;
        to = to_;
        mode = mode_;
    }

    function onConfidentialTransferReceived(address, address, euint64 amount, bytes calldata) external returns (ebool) {
        if (mode == 0) token.confidentialTransfer(to, amount);
        else token.confidentialTransferAndCall(to, amount, "");
        return _reply(true);
    }
}

/// @notice A minter contract that recomputes the token's deterministic handles in the same transaction as its own
///         mint and persists grants on them: the first-mint supply, each later supply its own mints produce, and a
///         never-credited recipient's first balance (spec H-34, E12).
contract RecomputingMinter {
    euint64 public trackedSupply;

    constructor() {
        FHEVMLib.setCoprocessorForChain();
    }

    function firstMintAndTrack(IERC7984Mintable t, address to, externalEuint64 x, bytes calldata p)
        external
        returns (bytes32)
    {
        t.confidentialMint(to, x, p);
        euint64 s = FHEVMLib.add(FHEVMLib.asEuint64(0), euint64.wrap(externalEuint64.unwrap(x)));
        FHEVMLib.allow(s, address(this));
        trackedSupply = s;
        return euint64.unwrap(s);
    }

    function nextMintAndTrack(IERC7984Mintable t, address to, externalEuint64 x, bytes calldata p)
        external
        returns (bytes32)
    {
        t.confidentialMint(to, x, p);
        (, euint64 s) = FHEVMLib.tryIncrease(trackedSupply, euint64.wrap(externalEuint64.unwrap(x)));
        FHEVMLib.allow(s, address(this));
        trackedSupply = s;
        return euint64.unwrap(s);
    }

    function mintAndGrabFreshBalance(IERC7984Mintable t, address to, externalEuint64 x, bytes calldata p)
        external
        returns (bytes32)
    {
        euint64 b = FHEVMLib.add(FHEVMLib.asEuint64(0), t.confidentialMint(to, x, p));
        FHEVMLib.allow(b, address(this));
        return euint64.unwrap(b);
    }

    function disclose(IERC7984Disclosure t, bytes32 h) external {
        t.requestDiscloseEncryptedAmount(euint64.wrap(h));
    }
}

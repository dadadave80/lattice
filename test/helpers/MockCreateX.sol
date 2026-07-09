// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title MockCreateX
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @author Modified from CreateX (https://github.com/pcaversaccio/createx)
/// @notice Faithful mock of CreateX's CREATE3 and CREATE2 paths: implements the SAME `_guard` transform and
///         the SAME `computeCreate3Address(guardedSalt)` / `computeCreate2Address(salt, initCodeHash)`
///         derivations as the canonical contract, so an etched instance at the canonical address
///         `0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed` lets tests exercise `CreateXDeployer` (both the
///         sender-guarded CREATE3 path and the raw-salt CREATE2 release path) deterministically without a
///         mainnet fork. Mirrors `CreateX.deployCreate3` / `deployCreate2` / `_guard` /
///         `computeCreate3Address` / `computeCreate2Address`.
contract MockCreateX {
    error FailedContractCreation();
    error InvalidSalt();

    // CREATE3 proxy child bytecode (identical to CreateX).
    bytes internal constant PROXY_CHILD_BYTECODE = hex"67363d3d37363d34f03d5260086018f3";

    function _efficientHash(bytes32 a, bytes32 b) internal pure returns (bytes32 hash) {
        assembly ("memory-safe") {
            mstore(0x00, a)
            mstore(0x20, b)
            hash := keccak256(0x00, 0x40)
        }
    }

    /// @dev Reproduces CreateX `_guard` for the cases the helper produces (sender-guarded variants).
    function _guard(bytes32 salt) internal view returns (bytes32 guardedSalt) {
        bool senderIsMsgSender = address(bytes20(salt)) == msg.sender;
        bool senderIsZero = address(bytes20(salt)) == address(0);
        bytes1 flag = bytes1(salt[20]);
        if (senderIsMsgSender && flag == hex"01") {
            guardedSalt = keccak256(abi.encode(msg.sender, block.chainid, salt));
        } else if (senderIsMsgSender && flag == hex"00") {
            guardedSalt = _efficientHash(bytes32(uint256(uint160(msg.sender))), salt);
        } else if (senderIsMsgSender) {
            revert InvalidSalt();
        } else if (senderIsZero && flag == hex"01") {
            guardedSalt = _efficientHash(bytes32(block.chainid), salt);
        } else if (senderIsZero && flag != hex"00") {
            // ZeroAddress + Unspecified flag — upstream rejects; ZeroAddress + 0x00 falls through to the
            // raw-salt branch below, exactly like upstream's final else.
            revert InvalidSalt();
        } else {
            guardedSalt = keccak256(abi.encode(salt));
        }
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CREATE2
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Canonical CREATE2 address derivation: `keccak256(0xff ++ deployer ++ salt ++ initCodeHash)[12:]`.
    ///      NO guard is applied to `salt` (matches the real CreateX `computeCreate2Address`) — pass the
    ///      already-guarded salt to predict a guarded {deployCreate2}.
    function computeCreate2Address(bytes32 salt, bytes32 initCodeHash, address deployer)
        public
        pure
        returns (address computedAddress)
    {
        computedAddress = address(uint160(uint256(keccak256(abi.encodePacked(hex"ff", deployer, salt, initCodeHash)))));
    }

    /// @dev CREATE2 address as deployed by this CreateX instance (see the guard note above).
    function computeCreate2Address(bytes32 salt, bytes32 initCodeHash) external view returns (address) {
        return computeCreate2Address(salt, initCodeHash, address(this));
    }

    /// @dev Guards `salt` (a raw salt whose first 20 bytes are neither `msg.sender` nor zero hashes to
    ///      `keccak256(abi.encode(salt))`), then plain CREATE2-deploys `initCode` with the guarded salt.
    function deployCreate2(bytes32 salt, bytes memory initCode) public payable returns (address newContract) {
        bytes32 guardedSalt = _guard(salt);
        assembly ("memory-safe") {
            newContract := create2(callvalue(), add(initCode, 32), mload(initCode), guardedSalt)
        }
        if (newContract == address(0) || newContract.code.length == 0) revert FailedContractCreation();
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                                  CREATE3
    //////////////////////////////////////////////////////////////////////////*//

    function computeCreate3Address(bytes32 salt, address deployer) public pure returns (address) {
        // Address of the CREATE2-deployed proxy, then the CREATE1 (nonce 1) child it deploys.
        bytes32 proxyInitHash = keccak256(PROXY_CHILD_BYTECODE);
        address proxy = address(uint160(uint256(keccak256(abi.encodePacked(hex"ff", deployer, salt, proxyInitHash)))));
        // RLP( [proxy, 0x01] ) = 0xd6 0x94 ++ proxy ++ 0x01
        return address(uint160(uint256(keccak256(abi.encodePacked(hex"d694", proxy, hex"01")))));
    }

    function computeCreate3Address(bytes32 salt) external view returns (address) {
        return computeCreate3Address(salt, address(this));
    }

    function deployCreate3(bytes32 salt, bytes memory initCode) public payable returns (address newContract) {
        bytes32 guardedSalt = _guard(salt);
        bytes memory proxyChildBytecode = PROXY_CHILD_BYTECODE;
        address proxy;
        assembly ("memory-safe") {
            proxy := create2(0, add(proxyChildBytecode, 32), mload(proxyChildBytecode), guardedSalt)
        }
        if (proxy == address(0)) revert FailedContractCreation();
        newContract = computeCreate3Address(guardedSalt, address(this));
        (bool success,) = proxy.call{value: msg.value}(initCode);
        if (!success || newContract.code.length == 0) revert FailedContractCreation();
    }

    function deployCreate3(bytes memory initCode) external payable returns (address newContract) {
        newContract = deployCreate3(keccak256(abi.encode(block.number, msg.sender)), initCode);
    }
}

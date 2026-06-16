// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CreateXDeployer} from "@lattice-script/lib/CreateXDeployer.sol";
import {ICreateX} from "@lattice/interfaces/external/ICreateX.sol";
import {Test} from "forge-std/Test.sol";

/// @notice A trivial contract deployed through CreateX to prove the helper end-to-end.
contract Pinged {
    uint256 public immutable value;

    constructor(uint256 v) {
        value = v;
    }

    function ping() external view returns (uint256) {
        return value;
    }
}

/// @notice Faithful mock of CreateX's CREATE3 path: implements the SAME `_guard` transform and the
///         SAME `computeCreate3Address(guardedSalt)` derivation as the canonical contract, so an
///         etched instance at the canonical address lets us test `CreateXDeployer` deterministically
///         without a mainnet fork. Mirrors `CreateX.deployCreate3` / `_guard` / `computeCreate3Address`.
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
        } else if (senderIsZero) {
            revert InvalidSalt();
        } else {
            guardedSalt = keccak256(abi.encode(salt));
        }
    }

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

contract CreateXDeployerTest is Test {
    address internal constant CANONICAL = 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed;

    function setUp() public {
        // Etch the faithful CreateX mock at the canonical singleton address so CreateXDeployer.CREATEX
        // resolves to live code under Foundry (no fork needed).
        MockCreateX impl = new MockCreateX();
        vm.etch(CANONICAL, address(impl).code);
    }

    /// @notice The helper's canonical address constant equals the published CreateX singleton.
    function test_CanonicalAddress() public pure {
        assertEq(address(CreateXDeployer.CREATEX), CANONICAL, "canonical CreateX address mismatch");
    }

    /// @notice predict(salt) equals the address CreateX actually deploys to (the core invariant).
    function test_PredictMatchesDeploy() public {
        bytes11 entropy = bytes11(uint88(0xABCDEF1234567890ABCDEF));
        bytes32 salt = CreateXDeployer._guardedSalt(address(this), entropy);
        bytes memory initCode = abi.encodePacked(type(Pinged).creationCode, abi.encode(uint256(42)));

        address predicted = CreateXDeployer.predict(salt);
        address deployed = CreateXDeployer.deploy(salt, initCode);

        assertEq(deployed, predicted, "predicted != deployed");
        assertEq(Pinged(deployed).ping(), 42, "deployed contract not functional");
        assertGt(deployed.code.length, 0, "no code at deployed address");
    }

    /// @notice The guarded salt is sender-pinned (first 20 bytes) + cross-chain-protected (21st byte).
    function test_GuardedSaltLayout() public view {
        bytes11 entropy = bytes11(uint88(0x0102030405060708090A0B));
        bytes32 salt = CreateXDeployer._guardedSalt(address(this), entropy);
        assertEq(address(bytes20(salt)), address(this), "first 20 bytes must be the deployer");
        assertEq(salt[20], bytes1(0x01), "21st byte must be 0x01 (cross-chain redeploy protection)");
    }
}

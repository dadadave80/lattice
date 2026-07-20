// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CreateXDeployer} from "@lattice-script/lib/CreateXDeployer.sol";
import {MockCreateX} from "@lattice-test/helpers/MockCreateX.sol";
import {ICreateX} from "@lattice/interfaces/external/createx/ICreateX.sol";
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

    /// @notice Mock-fidelity pin for the salt class real CreateX ACCEPTS but a naive guard rejects: first 20
    ///         bytes zero + protection byte 0x00 falls through to the raw-salt branch upstream
    ///         (`guardedSalt = keccak256(abi.encode(salt))`) and deploys — the mock must do the same.
    function test_MockGuard_ZeroPrefixUnprotectedSaltDeploysLikeUpstream() public {
        bytes32 salt = bytes32(uint256(0xABCDEF)); // bytes[0..19] zero, byte[20] 0x00, low-byte entropy
        bytes memory initCode = abi.encodePacked(type(Pinged).creationCode, abi.encode(uint256(7)));

        address predicted =
            MockCreateX(CANONICAL).computeCreate2Address(keccak256(abi.encode(salt)), keccak256(initCode));
        address deployed = MockCreateX(CANONICAL).deployCreate2(salt, initCode);

        assertEq(deployed, predicted, "zero-prefix unprotected salt must take the raw-salt guard branch");
        assertEq(Pinged(deployed).ping(), 7, "deployed contract not functional");
    }
}

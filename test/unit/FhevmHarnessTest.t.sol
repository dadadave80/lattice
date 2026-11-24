// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FhevmTestBase} from "@lattice-test/base/FhevmTestBase.sol";
import {
    aclAdd,
    fhevmExecutorAdd,
    hcuLimitAdd,
    inputVerifierAdd,
    kmsVerifierAdd
} from "@lattice-test/helpers/fhevm/fhevm-host/addresses/FHEVMHostAddresses.sol";
import {FheType} from "@lattice-test/helpers/fhevm/fhevm-host/contracts/shared/FheType.sol";
import {
    ACL_CREATION_CODE,
    FHEVM_EXECUTOR_CREATION_CODE,
    HCU_LIMIT_CREATION_CODE,
    INPUT_VERIFIER_CREATION_CODE,
    KMS_VERIFIER_CREATION_CODE,
    PROTOCOL_CONFIG_CREATION_CODE
} from "@lattice-test/helpers/fhevm/generated/HostBytecode.sol";
import {IHCULimit} from "@lattice-test/helpers/fhevm/generated/interfaces/IHCULimit.sol";
import {IInputVerifier} from "@lattice-test/helpers/fhevm/generated/interfaces/IInputVerifier.sol";
import {IKMSVerifier} from "@lattice-test/helpers/fhevm/generated/interfaces/IKMSVerifier.sol";
import {FHE} from "@lattice-test/helpers/fhevm/solidity/lib/FHE.sol";
import {CoprocessorConfig as ZamaCoprocessorConfig} from "@lattice-test/helpers/fhevm/solidity/lib/Impl.sol";
import {euint64, externalEuint64} from "@lattice/interfaces/external/fhevm/EncryptedTypes.sol";

contract UpstreamAdder {
    constructor() {
        FHE.setCoprocessor(ZamaCoprocessorConfig(aclAdd, fhevmExecutorAdd, kmsVerifierAdd));
    }

    function add(externalEuint64 a, bytes calldata pa, externalEuint64 b, bytes calldata pb)
        external
        returns (euint64 s)
    {
        s = FHE.add(FHE.fromExternal(a, pa), FHE.fromExternal(b, pb));
        FHE.allowThis(s);
        FHE.allow(s, msg.sender);
    }
}

contract FhevmHarnessTest is FhevmTestBase {
    function test_HostLine_IsV0139() public view {
        assertEq(_acl.getVersion(), "ACL v0.4.0");
        assertEq(_executor.getVersion(), "FHEVMExecutor v0.5.0");
        assertEq(IKMSVerifier(kmsVerifierAdd).getVersion(), "KMSVerifier v0.3.0");
        assertEq(IHCULimit(hcuLimitAdd).getVersion(), "HCULimit v0.3.0");
        assertEq(IInputVerifier(inputVerifierAdd).getVersion(), "InputVerifier v0.2.0");
        assertEq(IHCULimit(hcuLimitAdd).getMaxHCUPerTx(), 20_000_000);
        assertEq(IHCULimit(hcuLimitAdd).getMaxHCUDepthPerTx(), 5_000_000);
        assertEq(IHCULimit(hcuLimitAdd).getGlobalHCUCapPerBlock(), type(uint48).max);
    }

    function test_HostBlobsPinned() public pure {
        assertEq(
            keccak256(
                abi.encodePacked(
                    ACL_CREATION_CODE,
                    HCU_LIMIT_CREATION_CODE,
                    FHEVM_EXECUTOR_CREATION_CODE,
                    INPUT_VERIFIER_CREATION_CODE,
                    KMS_VERIFIER_CREATION_CODE,
                    PROTOCOL_CONFIG_CREATION_CODE
                )
            ),
            0x58fc6cad58fca754736af22f946856516fdbcaeca42d228449a5dd7cd2d9b12f
        );
    }

    function test_Isolation_TransientGrantDoesNotSurviveTopLevelCall() public {
        bytes32 h = _executor.trivialEncrypt(7, FheType.Uint64);
        assertFalse(_acl.isAllowed(h, address(this)));
    }

    function test_Decrypt_SkipsAclCheck() public {
        bytes32 h = _executor.trivialEncrypt(7, FheType.Uint64);
        assertFalse(_acl.persistAllowed(h, address(this)));
        assertEq(decrypt(h), 7);
        assertEq(decrypt(bytes32(uint256(0xdead))), 0);
    }

    function test_UpstreamLibraryRoundTrip() public {
        UpstreamAdder adder = new UpstreamAdder();
        (externalEuint64 a, bytes memory pa) = encryptUint64(7, address(this), address(adder));
        (externalEuint64 b, bytes memory pb) = encryptUint64(35, address(this), address(adder));
        euint64 s = adder.add(a, pa, b, pb);
        assertTrue(_acl.persistAllowed(euint64.unwrap(s), address(this)));
        assertEq(decrypt(s), 42);
    }
}

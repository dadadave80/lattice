// SPDX-License-Identifier: BSD-3-Clause-Clear
pragma solidity ^0.8.27;

import {Vm} from "forge-std/Vm.sol";
import {IConfidentialERC20Wrapper} from "./interfaces/IConfidentialWrapper.sol";
import {IERC20Minimal} from "./interfaces/IERC20.sol";
import {IACL} from "./generated/interfaces/IACL.sol";
import {IFHEVMExecutor} from "./generated/interfaces/IFHEVMExecutor.sol";
import {IHCULimit} from "./generated/interfaces/IHCULimit.sol";
import {IInputVerifier} from "./generated/interfaces/IInputVerifier.sol";
import {IKMSVerifier} from "./generated/interfaces/IKMSVerifier.sol";
import {IProtocolConfig, IProtocolConfigHost} from "./generated/interfaces/IProtocolConfigHost.sol";
import {IEmptyUUPSProxy} from "./generated/interfaces/IEmptyUUPSProxy.sol";
import {IEmptyUUPSProxyACL} from "./generated/interfaces/IEmptyUUPSProxyACL.sol";
import {
    ACL_CREATION_CODE,
    HCU_LIMIT_CREATION_CODE,
    FHEVM_EXECUTOR_CREATION_CODE,
    INPUT_VERIFIER_CREATION_CODE,
    KMS_VERIFIER_CREATION_CODE,
    PROTOCOL_CONFIG_CREATION_CODE,
    EMPTY_UUPS_PROXY_CREATION_CODE,
    EMPTY_UUPS_PROXY_ACL_CREATION_CODE,
    HCU_LIMIT_NO_DEPTH_CAP_CREATION_CODE,
    PAUSER_SET_RUNTIME_CODE,
    DEPLOYABLE_ERC1967_PROXY_RUNTIME_CODE
} from "./generated/HostBytecode.sol";
import {
    aclAdd,
    fhevmExecutorAdd,
    hcuLimitAdd,
    inputVerifierAdd,
    kmsVerifierAdd,
    pauserSetAdd,
    protocolConfigAdd
} from "./fhevm-host/addresses/FHEVMHostAddresses.sol";
import {FheType} from "./fhevm-host/contracts/shared/FheType.sol";
import {PlaintextDBMixin} from "./PlaintextDBMixin.sol";
import {InputProofHelper} from "./InputProofHelper.sol";
import {KMSDecryptionProofHelper} from "./KMSDecryptionProofHelper.sol";
import {UserDecryptHelper} from "./UserDecryptHelper.sol";
import {CleartextArithmetic} from "./cleartext/CleartextArithmetic.sol";
import {SafeERC20} from "./utils/SafeERC20.sol";

import {
    ebool,
    euint8,
    euint16,
    euint32,
    euint64,
    euint128,
    euint256,
    eaddress,
    externalEbool,
    externalEuint8,
    externalEuint16,
    externalEuint32,
    externalEuint64,
    externalEuint128,
    externalEuint256,
    externalEaddress
} from "@lattice/interfaces/external/fhevm/EncryptedTypes.sol";

abstract contract FhevmTest is PlaintextDBMixin {
    error HandleNotAllowedForPublicDecryption(bytes32 handle);
    error UserAddressEqualsContractAddress();
    error UserNotAuthorizedForDecrypt(bytes32 handle, address userAddress);
    error ContractNotAuthorizedForDecrypt(bytes32 handle, address contractAddress);
    error InvalidUserDecryptSignature();
    error EncryptInputLengthMismatch(uint256 valuesLength, uint256 fheTypesLength);
    error EncryptInputTooLong();

    uint256 internal constant MOCK_INPUT_SIGNER_PK = 0x7ec8ada6642fc4ccfb7729bc29c17cf8d21b61abd5642d1db992c0b8672ab901;
    uint256 internal constant MOCK_KMS_SIGNER_PK = 0x388b7680e4e1afa06efbfd45cdd1fe39f3c6af381df6555a19661f283b97de91;

    bytes internal constant EMPTY_EXTRA_DATA = hex"00";
    uint256 internal constant DEFAULT_USER_DECRYPT_DURATION_DAYS = 1;
    address internal constant PROXY_OWNER = address(0xBEEF);
    /// @dev ERC-1967 implementation slot: `keccak256("eip1967.proxy.implementation") - 1`.
    bytes32 private constant _ERC1967_IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    IFHEVMExecutor internal _executor;
    IACL internal _acl;
    IInputVerifier internal _inputVerifier;
    IKMSVerifier internal _kmsVerifier;

    address internal mockInputSigner;
    address internal mockKmsSigner;

    uint256 private _encryptNonce;

    function setUp() public virtual {
        vm.chainId(31337);
        mockInputSigner = vm.addr(MOCK_INPUT_SIGNER_PK);
        mockKmsSigner = vm.addr(MOCK_KMS_SIGNER_PK);
        _deployAllContracts();

        vm.recordLogs();
        vm.getRecordedLogs();
    }

    /// @notice Funds `user` with wrapper underlying and wraps `amount` into confidential tokens.
    /// @dev This is the confidential-token equivalent of Foundry's `deal`.
    function dealConfidential(address wrapper, address user, uint256 amount) internal {
        IERC20Minimal underlyingToken = IERC20Minimal(IConfidentialERC20Wrapper(wrapper).underlying());
        deal(address(underlyingToken), user, underlyingToken.balanceOf(user) + amount);

        vm.startPrank(user);
        // `forceApprove` rather than a plain `approve`: non-standard underlyings may return no value
        // or require the allowance to be reset to zero first (sush as USDT).
        SafeERC20.forceApprove(underlyingToken, wrapper, type(uint256).max);
        IConfidentialERC20Wrapper(wrapper).wrap(user, amount);
        vm.stopPrank();
    }

    /// @notice Relaxes only the sequential HCU depth cap for subsequent FHE operations.
    /// @dev Keeps the host contract's total per-transaction HCU accounting enabled, but swaps
    /// the HCULimit implementation behind the test proxy for a variant that no longer reverts
    /// on deep handle chains. This is useful for end-to-end tests whose orchestration is heavier
    /// than the individual production calls they are trying to validate.
    function disableHCUDepthLimit() internal {
        address relaxedHcuLimit = _deployBlob(HCU_LIMIT_NO_DEPTH_CAP_CREATION_CODE);
        vm.prank(PROXY_OWNER);
        IEmptyUUPSProxy(hcuLimitAdd).upgradeToAndCall(relaxedHcuLimit, "");
    }

    /// @notice Encrypts a boolean for the given target contract.
    /// @param value The clear boolean value to encrypt.
    /// @param target The contract expected to call `FHE.fromExternal`.
    /// @return handle External encrypted boolean handle and input proof.
    function encryptBool(bool value, address target) internal returns (externalEbool, bytes memory) {
        return encryptBool(value, address(this), target);
    }

    /// @notice Encrypts a boolean for an explicit user/target pair.
    /// @param value The clear boolean value to encrypt.
    /// @param user The user embedded in the input proof authorization.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptBool(bool value, address user, address target) internal returns (externalEbool, bytes memory) {
        (bytes32 handle, bytes memory inputProof) = _encrypt(value ? 1 : 0, FheType.Bool, user, target);
        return (externalEbool.wrap(handle), inputProof);
    }

    /// @notice Encrypts an 8-bit unsigned integer for the given target contract.
    /// @param value The clear uint8 value to encrypt.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptUint8(uint8 value, address target) internal returns (externalEuint8, bytes memory) {
        return encryptUint8(value, address(this), target);
    }

    /// @notice Encrypts an 8-bit unsigned integer for an explicit user/target pair.
    /// @param value The clear uint8 value to encrypt.
    /// @param user The user embedded in the input proof authorization.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptUint8(uint8 value, address user, address target) internal returns (externalEuint8, bytes memory) {
        (bytes32 handle, bytes memory inputProof) = _encrypt(value, FheType.Uint8, user, target);
        return (externalEuint8.wrap(handle), inputProof);
    }

    /// @notice Encrypts a 16-bit unsigned integer for the given target contract.
    /// @param value The clear uint16 value to encrypt.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptUint16(uint16 value, address target) internal returns (externalEuint16, bytes memory) {
        return encryptUint16(value, address(this), target);
    }

    /// @notice Encrypts a 16-bit unsigned integer for an explicit user/target pair.
    /// @param value The clear uint16 value to encrypt.
    /// @param user The user embedded in the input proof authorization.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptUint16(uint16 value, address user, address target)
        internal
        returns (externalEuint16, bytes memory)
    {
        (bytes32 handle, bytes memory inputProof) = _encrypt(value, FheType.Uint16, user, target);
        return (externalEuint16.wrap(handle), inputProof);
    }

    /// @notice Encrypts a 32-bit unsigned integer for the given target contract.
    /// @param value The clear uint32 value to encrypt.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptUint32(uint32 value, address target) internal returns (externalEuint32, bytes memory) {
        return encryptUint32(value, address(this), target);
    }

    /// @notice Encrypts a 32-bit unsigned integer for an explicit user/target pair.
    /// @param value The clear uint32 value to encrypt.
    /// @param user The user embedded in the input proof authorization.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptUint32(uint32 value, address user, address target)
        internal
        returns (externalEuint32, bytes memory)
    {
        (bytes32 handle, bytes memory inputProof) = _encrypt(value, FheType.Uint32, user, target);
        return (externalEuint32.wrap(handle), inputProof);
    }

    /// @notice Encrypts a 64-bit unsigned integer for the given target contract.
    /// @param value The clear uint64 value to encrypt.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptUint64(uint64 value, address target) internal returns (externalEuint64, bytes memory) {
        return encryptUint64(value, address(this), target);
    }

    /// @notice Encrypts a 64-bit unsigned integer for an explicit user/target pair.
    /// @param value The clear uint64 value to encrypt.
    /// @param user The user embedded in the input proof authorization.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptUint64(uint64 value, address user, address target)
        internal
        returns (externalEuint64, bytes memory)
    {
        (bytes32 handle, bytes memory inputProof) = _encrypt(value, FheType.Uint64, user, target);
        return (externalEuint64.wrap(handle), inputProof);
    }

    /// @notice Encrypts a 128-bit unsigned integer for the given target contract.
    /// @param value The clear uint128 value to encrypt.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptUint128(uint128 value, address target) internal returns (externalEuint128, bytes memory) {
        return encryptUint128(value, address(this), target);
    }

    /// @notice Encrypts a 128-bit unsigned integer for an explicit user/target pair.
    /// @param value The clear uint128 value to encrypt.
    /// @param user The user embedded in the input proof authorization.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptUint128(uint128 value, address user, address target)
        internal
        returns (externalEuint128, bytes memory)
    {
        (bytes32 handle, bytes memory inputProof) = _encrypt(value, FheType.Uint128, user, target);
        return (externalEuint128.wrap(handle), inputProof);
    }

    /// @notice Encrypts a 256-bit unsigned integer for the given target contract.
    /// @param value The clear uint256 value to encrypt.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptUint256(uint256 value, address target) internal returns (externalEuint256, bytes memory) {
        return encryptUint256(value, address(this), target);
    }

    /// @notice Encrypts a 256-bit unsigned integer for an explicit user/target pair.
    /// @param value The clear uint256 value to encrypt.
    /// @param user The user embedded in the input proof authorization.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptUint256(uint256 value, address user, address target)
        internal
        returns (externalEuint256, bytes memory)
    {
        (bytes32 handle, bytes memory inputProof) = _encrypt(value, FheType.Uint256, user, target);
        return (externalEuint256.wrap(handle), inputProof);
    }

    /// @notice Encrypts an address value for the given target contract.
    /// @param value The clear address value to encrypt.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptAddress(address value, address target) internal returns (externalEaddress, bytes memory) {
        return encryptAddress(value, address(this), target);
    }

    /// @notice Encrypts an address value for an explicit user/target pair.
    /// @param value The clear address value to encrypt.
    /// @param user The user embedded in the input proof authorization.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encryptAddress(address value, address user, address target)
        internal
        returns (externalEaddress, bytes memory)
    {
        (bytes32 handle, bytes memory inputProof) = _encrypt(uint256(uint160(value)), FheType.Uint160, user, target);
        return (externalEaddress.wrap(handle), inputProof);
    }

    /// @notice Encrypts a list of values with corresponding FHE types for the given target contract.
    /// @param values The clear values to encrypt as uint256, normalized according to their corresponding FHE types.
    /// @param fheTypes The FHE types corresponding to each value.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encrypt(uint256[] memory values, FheType[] memory fheTypes, address target)
        internal
        returns (bytes32[] memory handles, bytes memory inputProof)
    {
        return encrypt(values, fheTypes, address(this), target);
    }

    /// @notice Encrypts a list of values with corresponding FHE types for an explicit user/target pair.
    /// @param values The clear values to encrypt as uint256, normalized according to their corresponding FHE types.
    /// @param fheTypes The FHE types corresponding to each value.
    /// @param user The user embedded in the input proof authorization.
    /// @param target The contract expected to call `FHE.fromExternal`.
    function encrypt(uint256[] memory values, FheType[] memory fheTypes, address user, address target)
        internal
        returns (bytes32[] memory handles, bytes memory inputProof)
    {
        return _encrypt(values, fheTypes, user, target);
    }

    /// @notice Decrypts handles that were marked as publicly decryptable and returns a KMS-style proof.
    /// @param handles The encrypted handles to decrypt.
    /// @return cleartexts The cleartext values in the same order as `handles`.
    /// @return decryptionProof Encoded decryption proof signed by the configured mock KMS signer.
    function publicDecrypt(bytes32[] memory handles)
        internal
        returns (uint256[] memory cleartexts, bytes memory decryptionProof)
    {
        _processNewLogs();
        cleartexts = new uint256[](handles.length);
        for (uint256 i = 0; i < handles.length; i++) {
            if (!_acl.isAllowedForDecryption(handles[i])) {
                revert HandleNotAllowedForPublicDecryption(handles[i]);
            }
            cleartexts[i] = _plaintexts[handles[i]];
        }

        bytes memory abiEncodedCleartexts = abi.encodePacked(cleartexts);
        decryptionProof = buildDecryptionProof(handles, abiEncodedCleartexts);
    }

    /// @notice Decrypts a single handle for a user after persistent ACL checks and user signature verification.
    /// @param handle The encrypted handle to decrypt.
    /// @param userAddress The user authorizing this decrypt request.
    /// @param contractAddress The contract context included in the signed request.
    /// @param userSignature EIP-712 signature produced by `signUserDecrypt`.
    /// @return The decrypted cleartext value from the mock executor.
    function userDecrypt(bytes32 handle, address userAddress, address contractAddress, bytes memory userSignature)
        internal
        returns (uint256)
    {
        _processNewLogs();

        if (userAddress == contractAddress) {
            revert UserAddressEqualsContractAddress();
        }

        if (!_acl.persistAllowed(handle, userAddress)) {
            revert UserNotAuthorizedForDecrypt(handle, userAddress);
        }

        if (!_acl.persistAllowed(handle, contractAddress)) {
            revert ContractNotAuthorizedForDecrypt(handle, contractAddress);
        }

        address[] memory contractAddresses = new address[](1);
        contractAddresses[0] = contractAddress;
        bytes32 domainSeparator = UserDecryptHelper.computeUserDecryptDomainSeparator(block.chainid, kmsVerifierAdd);
        bytes32 digest = UserDecryptHelper.computeUserDecryptDigest(
            abi.encodePacked(userAddress),
            contractAddresses,
            block.timestamp,
            DEFAULT_USER_DECRYPT_DURATION_DAYS,
            EMPTY_EXTRA_DATA,
            domainSeparator
        );

        (uint8 v, bytes32 r, bytes32 s) = _decodeSignature(userSignature);
        address recoveredSigner = ecrecover(digest, v, r, s);
        if (recoveredSigner == address(0) || recoveredSigner != userAddress) {
            revert InvalidUserDecryptSignature();
        }

        return _plaintexts[handle];
    }

    /// @notice Reads a cleartext value by handle from the local plaintext database.
    function decrypt(bytes32 handle) internal returns (uint256) {
        _processNewLogs();
        return _plaintexts[handle];
    }

    /// @notice Decrypts an encrypted boolean.
    /// @param value The encrypted boolean handle.
    /// @return The decrypted boolean.
    function decrypt(ebool value) internal returns (bool) {
        return decrypt(ebool.unwrap(value)) != 0;
    }

    /// @notice Decrypts an encrypted 8-bit unsigned integer.
    /// @param value The encrypted uint8 handle.
    /// @return The decrypted uint8 value.
    function decrypt(euint8 value) internal returns (uint8) {
        return uint8(decrypt(euint8.unwrap(value)));
    }

    /// @notice Decrypts an encrypted 16-bit unsigned integer.
    /// @param value The encrypted uint16 handle.
    /// @return The decrypted uint16 value.
    function decrypt(euint16 value) internal returns (uint16) {
        return uint16(decrypt(euint16.unwrap(value)));
    }

    /// @notice Decrypts an encrypted 32-bit unsigned integer.
    /// @param value The encrypted uint32 handle.
    /// @return The decrypted uint32 value.
    function decrypt(euint32 value) internal returns (uint32) {
        return uint32(decrypt(euint32.unwrap(value)));
    }

    /// @notice Decrypts an encrypted 64-bit unsigned integer.
    /// @param value The encrypted uint64 handle.
    /// @return The decrypted uint64 value.
    function decrypt(euint64 value) internal returns (uint64) {
        return uint64(decrypt(euint64.unwrap(value)));
    }

    /// @notice Decrypts an encrypted 128-bit unsigned integer.
    /// @param value The encrypted uint128 handle.
    /// @return The decrypted uint128 value.
    function decrypt(euint128 value) internal returns (uint128) {
        return uint128(decrypt(euint128.unwrap(value)));
    }

    /// @notice Decrypts an encrypted 256-bit unsigned integer.
    /// @param value The encrypted uint256 handle.
    /// @return The decrypted uint256 value.
    function decrypt(euint256 value) internal returns (uint256) {
        return decrypt(euint256.unwrap(value));
    }

    /// @notice Decrypts an encrypted address.
    /// @param value The encrypted address handle.
    /// @return The decrypted address.
    function decrypt(eaddress value) internal returns (address) {
        return address(uint160(decrypt(eaddress.unwrap(value))));
    }

    /// @notice Builds a KMS-signed decryption proof for callback-style decryption flows.
    /// @dev Unlike `publicDecrypt`, this does NOT check ACL permissions. Use it when the contract
    ///      under test expects `(cleartext, proof)` callback arguments rather than on-chain decryption.
    /// @param handles The encrypted handles being decrypted.
    /// @param abiEncodedCleartexts ABI-encoded cleartext values matching the on-chain verification encoding.
    /// @return proof The assembled decryption proof bytes.
    function buildDecryptionProof(bytes32[] memory handles, bytes memory abiEncodedCleartexts)
        internal
        view
        returns (bytes memory proof)
    {
        (, string memory name, string memory version, uint256 chainId, address verifyingContract,,) =
            _kmsVerifier.eip712Domain();
        bytes32 domainSeparator =
            KMSDecryptionProofHelper.computeKMSDecryptionDomainSeparator(name, version, chainId, verifyingContract);
        bytes32 digest = KMSDecryptionProofHelper.computeDecryptionDigest(
            handles, abiEncodedCleartexts, EMPTY_EXTRA_DATA, domainSeparator
        );

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _signDigest(MOCK_KMS_SIGNER_PK, digest);
        proof = KMSDecryptionProofHelper.assembleDecryptionProof(signatures, EMPTY_EXTRA_DATA);
    }

    /// @notice Builds a KMS-signed decryption proof for a single handle.
    /// @param handle The encrypted handle being decrypted.
    /// @param abiEncodedCleartext ABI-encoded cleartext value matching the on-chain verification encoding.
    /// @return proof The assembled decryption proof bytes.
    function buildDecryptionProof(bytes32 handle, bytes memory abiEncodedCleartext)
        internal
        view
        returns (bytes memory proof)
    {
        bytes32[] memory handles = new bytes32[](1);
        handles[0] = handle;
        proof = buildDecryptionProof(handles, abiEncodedCleartext);
    }

    /// @notice Signs a default user decrypt request for a single contract using current block timestamp.
    /// @param userPk Private key used for EIP-712 signing.
    /// @param contractAddress The single contract allowed by the signed request.
    /// @return signature `r || s || v` encoded signature bytes.
    function signUserDecrypt(uint256 userPk, address contractAddress) internal view returns (bytes memory signature) {
        address[] memory contractAddresses = new address[](1);
        contractAddresses[0] = contractAddress;
        return signUserDecrypt(userPk, contractAddresses, block.timestamp, DEFAULT_USER_DECRYPT_DURATION_DAYS);
    }

    /// @notice Signs a custom user decrypt request.
    /// @param userPk Private key used for EIP-712 signing.
    /// @param contractAddresses Allowlisted contracts embedded in the request digest.
    /// @param startTimestamp Start time embedded in the request digest.
    /// @param durationDays Duration (in days) embedded in the request digest.
    /// @return signature `r || s || v` encoded signature bytes.
    function signUserDecrypt(
        uint256 userPk,
        address[] memory contractAddresses,
        uint256 startTimestamp,
        uint256 durationDays
    ) internal view returns (bytes memory signature) {
        address userAddress = vm.addr(userPk);
        bytes32 domainSeparator = UserDecryptHelper.computeUserDecryptDomainSeparator(block.chainid, kmsVerifierAdd);
        bytes32 digest = UserDecryptHelper.computeUserDecryptDigest(
            abi.encodePacked(userAddress),
            contractAddresses,
            startTimestamp,
            durationDays,
            EMPTY_EXTRA_DATA,
            domainSeparator
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPk, digest);
        signature = abi.encodePacked(r, s, v);
    }

    /// @notice Retrieves the recorded logs and processes FHE events.
    /// @dev `vm.getRecordedLogs()` consumes recorded logs. Calling the Vm cheatcode directly in tests that
    /// inspect events bypasses FHEVM log processing. Use this helper instead so logs are returned and FHEVM
    /// effects are applied during event testing.
    /// @return logs The recorded logs.
    function getRecordedLogs() internal returns (Vm.Log[] memory logs) {
        logs = vm.getRecordedLogs();
        _processNewLogs(logs);
    }

    function _deployAllContracts() internal {
        _deployPauserSet();
        _deployACL();
        _deployHCULimit();
        _deployRealExecutor();
        _deployInputVerifier();
        _deployProtocolConfig();
        _deployKMSVerifier();

        _executor = IFHEVMExecutor(fhevmExecutorAdd);
        _acl = IACL(aclAdd);
        _inputVerifier = IInputVerifier(inputVerifierAdd);
        _kmsVerifier = IKMSVerifier(kmsVerifierAdd);
    }

    /// @dev Must run the constructor: etching runtime code instead leaves the UUPS `__self`
    /// immutable zeroed, which breaks every later upgrade.
    function _deployBlob(bytes memory creationCode) private returns (address addr) {
        assembly {
            addr := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        require(addr != address(0), "forge-fhevm: host contract deployment failed");
    }

    /// @dev Writing the implementation slot by hand is complete: it is the only state an ERC-1967
    /// proxy constructor sets, and `vm.etch` cannot run one. The proxy is left uninitialized —
    /// callers must still initialize it before upgrading.
    function _installProxy(address target, address impl) private {
        vm.etch(target, DEPLOYABLE_ERC1967_PROXY_RUNTIME_CODE);
        vm.store(target, _ERC1967_IMPL_SLOT, bytes32(uint256(uint160(impl))));
    }

    function _installEmptyProxy(address target) private {
        _installProxy(target, _deployBlob(EMPTY_UUPS_PROXY_CREATION_CODE));
        IEmptyUUPSProxy(target).initialize();
    }

    function _deployPauserSet() internal {
        // No constructor and no immutables, so etching the runtime blob is exact.
        vm.etch(pauserSetAdd, PAUSER_SET_RUNTIME_CODE);
    }

    function _deployACL() internal {
        // Must run first: every other empty proxy authorizes upgrades through `ACLOwnable`,
        // which reads the owner from the ACL contract at its canonical address.
        _installProxy(aclAdd, _deployBlob(EMPTY_UUPS_PROXY_ACL_CREATION_CODE));
        IEmptyUUPSProxyACL(aclAdd).initialize(PROXY_OWNER);

        address aclImpl = _deployBlob(ACL_CREATION_CODE);
        vm.prank(PROXY_OWNER);
        IEmptyUUPSProxyACL(aclAdd).upgradeToAndCall(aclImpl, abi.encodeCall(IACL.initializeFromEmptyProxy, ()));
    }

    function _deployHCULimit() internal {
        _installEmptyProxy(hcuLimitAdd);

        address hcuLimitImpl = _deployBlob(HCU_LIMIT_CREATION_CODE);
        vm.prank(PROXY_OWNER);
        IEmptyUUPSProxy(hcuLimitAdd)
            .upgradeToAndCall(
                hcuLimitImpl, abi.encodeCall(IHCULimit.initializeFromEmptyProxy, (20_000_000, 5_000_000, 20_000_000))
            );
    }

    function _deployRealExecutor() internal {
        _installEmptyProxy(fhevmExecutorAdd);

        address executorImpl = _deployBlob(FHEVM_EXECUTOR_CREATION_CODE);
        vm.prank(PROXY_OWNER);
        IEmptyUUPSProxy(fhevmExecutorAdd)
            .upgradeToAndCall(executorImpl, abi.encodeCall(IFHEVMExecutor.initializeFromEmptyProxy, ()));
    }

    function _deployInputVerifier() internal {
        _installEmptyProxy(inputVerifierAdd);

        address inputVerifierImpl = _deployBlob(INPUT_VERIFIER_CREATION_CODE);
        address[] memory signers = new address[](1);
        signers[0] = mockInputSigner;

        vm.prank(PROXY_OWNER);
        IEmptyUUPSProxy(inputVerifierAdd)
            .upgradeToAndCall(
                inputVerifierImpl,
                abi.encodeCall(
                    IInputVerifier.initializeFromEmptyProxy, (inputVerifierAdd, uint64(block.chainid), signers, 1)
                )
            );
    }

    function _deployProtocolConfig() internal {
        _installEmptyProxy(protocolConfigAdd);

        address protocolConfigImpl = _deployBlob(PROTOCOL_CONFIG_CREATION_CODE);
        IProtocolConfigHost.KmsNode[] memory nodes = new IProtocolConfigHost.KmsNode[](1);
        nodes[0] = IProtocolConfigHost.KmsNode({
            txSenderAddress: mockKmsSigner, signerAddress: mockKmsSigner, ipAddress: "127.0.0.1", storageUrl: ""
        });
        IProtocolConfig.KmsThresholds memory thresholds =
            IProtocolConfig.KmsThresholds({publicDecryption: 1, userDecryption: 1, kmsGen: 1, mpc: 1});

        vm.prank(PROXY_OWNER);
        IEmptyUUPSProxy(protocolConfigAdd)
            .upgradeToAndCall(
                protocolConfigImpl, abi.encodeCall(IProtocolConfigHost.initializeFromEmptyProxy, (nodes, thresholds))
            );
    }

    function _deployKMSVerifier() internal {
        _installEmptyProxy(kmsVerifierAdd);

        address kmsVerifierImpl = _deployBlob(KMS_VERIFIER_CREATION_CODE);

        vm.prank(PROXY_OWNER);
        IEmptyUUPSProxy(kmsVerifierAdd)
            .upgradeToAndCall(
                kmsVerifierImpl,
                abi.encodeCall(IKMSVerifier.initializeFromEmptyProxy, (kmsVerifierAdd, uint64(block.chainid)))
            );
    }

    function _encrypt(uint256 value, FheType fheType, address user, address target)
        internal
        returns (bytes32 handle, bytes memory inputProof)
    {
        uint256[] memory values = new uint256[](1);
        values[0] = value;
        FheType[] memory fheTypes = new FheType[](1);
        fheTypes[0] = fheType;

        (bytes32[] memory handles, bytes memory proof) = _encrypt(values, fheTypes, user, target);
        handle = handles[0];
        inputProof = proof;
    }

    function _encrypt(uint256[] memory values, FheType[] memory fheTypes, address user, address target)
        internal
        returns (bytes32[] memory handles, bytes memory inputProof)
    {
        uint256 valuesLength = values.length;
        if (valuesLength != fheTypes.length) {
            revert EncryptInputLengthMismatch(valuesLength, fheTypes.length);
        }
        if (valuesLength > type(uint8).max) {
            revert EncryptInputTooLong();
        }

        handles = new bytes32[](valuesLength);
        for (uint256 i; i < valuesLength; ++i) {
            uint256 value = values[i];
            FheType fheType = fheTypes[i];

            _encryptNonce += 1;

            bytes memory ciphertext =
                abi.encodePacked(keccak256(abi.encodePacked(value, uint8(fheType), _encryptNonce)));
            bytes32 handle =
                InputProofHelper.computeInputHandle(ciphertext, uint8(i), fheType, aclAdd, uint64(block.chainid));

            _plaintexts[handle] = CleartextArithmetic.normalizePlaintextToType(value, uint8(fheType));

            handles[i] = handle;
        }

        bytes32 domainSeparator = InputProofHelper.computeInputVerifierDomainSeparator(inputVerifierAdd, block.chainid);
        bytes32 digest = InputProofHelper.computeInputVerificationDigest(
            handles, user, target, block.chainid, EMPTY_EXTRA_DATA, domainSeparator
        );

        bytes[] memory signatures = new bytes[](1);
        signatures[0] = _signDigest(MOCK_INPUT_SIGNER_PK, digest);
        inputProof = InputProofHelper.assembleInputProof(handles, signatures, EMPTY_EXTRA_DATA);
    }

    function _decodeSignature(bytes memory signature) internal pure returns (uint8 v, bytes32 r, bytes32 s) {
        if (signature.length != 65) {
            revert InvalidUserDecryptSignature();
        }

        assembly {
            r := mload(add(signature, 0x20))
            s := mload(add(signature, 0x40))
            v := byte(0, mload(add(signature, 0x60)))
        }

        if (v < 27) {
            v += 27;
        }
        if (v != 27 && v != 28) {
            revert InvalidUserDecryptSignature();
        }
    }

    function _signDigest(uint256 signerPk, bytes32 digest) internal pure returns (bytes memory signature) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, digest);
        signature = abi.encodePacked(r, s, v);
    }
}

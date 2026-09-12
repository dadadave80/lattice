// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseDeploy} from "@lattice-script/base/BaseDeploy.s.sol";
import {CreateXDeployer} from "@lattice-script/lib/CreateXDeployer.sol";
import {ArachnidProxy} from "@lattice-test/helpers/ArachnidProxy.sol";
import {MockCreateX} from "@lattice-test/helpers/MockCreateX.sol";
import {LatticeVersion} from "@lattice/LatticeVersion.sol";
import {ICreateX} from "@lattice/interfaces/external/createx/ICreateX.sol";
import {Test} from "forge-std/Test.sol";

/// @dev The plain EIP-1014 address the {ArachnidProxy} produces for a RAW, UNGUARDED salt — spelled out
///      longhand so the tests pin the derivation instead of replaying the library's own math.
function arachnidAddress(bytes32 salt, bytes32 initCodeHash) pure returns (address) {
    return address(uint160(uint256(keccak256(abi.encodePacked(hex"ff", ArachnidProxy.PROXY, salt, initCodeHash)))));
}

/// @notice Minimal {BaseDeploy} driver exposing the internal released-facet resolver under test.
contract FacetHarness is BaseDeploy {
    function facet(string memory name) external returns (address) {
        return _facet(name);
    }
}

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

    //*//////////////////////////////////////////////////////////////////////////
    //                          ARACHNID PROXY FALLBACK
    //////////////////////////////////////////////////////////////////////////*//

    /// @dev Turns this run into an Arachnid-only chain — the Hedera shape: CreateX has no code anywhere, the
    ///      deterministic-deployment proxy carries its real 69-byte runtime.
    function _arachnidOnlyChain() internal {
        vm.etch(CANONICAL, "");
        vm.etch(ArachnidProxy.PROXY, ArachnidProxy.RUNTIME);
        assertEq(address(CreateXDeployer.CREATEX).code.length, 0, "CreateX must be absent on an Arachnid chain");
        assertEq(ArachnidProxy.PROXY.code.length, 69, "vendored proxy runtime is not the fetched 69 bytes");
    }

    /// @notice Pins the vendored bytecode against a source nobody here typed: Foundry's test EVM ships the
    ///         SAME proxy at that address as its default CREATE2 deployer, so the two must be byte-identical
    ///         before any etch of ours runs.
    function test_Arachnid_VendoredRuntimeMatchesTheLivePreDeploy() public view {
        assertEq(ArachnidProxy.RUNTIME.length, 69, "vendored proxy runtime is not the fetched 69 bytes");
        assertEq(ArachnidProxy.PROXY.code, ArachnidProxy.RUNTIME, "vendored runtime != the proxy Foundry ships");
    }

    /// @notice Without CreateX but with the proxy, deployRaw lands EXACTLY at predictRaw — and both equal the
    ///         unguarded EIP-1014 derivation with the PROXY as deployer.
    function test_Arachnid_DeployRawLandsAtPredictRaw() public {
        _arachnidOnlyChain();
        assertTrue(CreateXDeployer.hasRawDeployer(), "the proxy alone must count as a deterministic deployer");

        bytes32 salt = keccak256("lattice.test.arachnid");
        bytes memory initCode = abi.encodePacked(type(Pinged).creationCode, abi.encode(uint256(42)));
        bytes32 initCodeHash = keccak256(initCode);

        address predicted = CreateXDeployer.predictRaw(salt, initCodeHash);
        assertEq(predicted, arachnidAddress(salt, initCodeHash), "predictRaw is not the unguarded proxy derivation");

        address deployed = CreateXDeployer.deployRaw(salt, initCode);
        assertEq(deployed, predicted, "predicted != deployed");
        assertEq(Pinged(deployed).ping(), 42, "deployed contract not functional");
    }

    /// @notice The documented consequence: the proxy guards nothing while CreateX applies
    ///         `keccak256(abi.encode(salt))`, so one salt + initcode is deterministic on both chains at two
    ///         DIFFERENT addresses.
    function test_Arachnid_AddressDiffersFromTheCreateXAddress() public {
        bytes32 salt = keccak256("lattice.test.arachnid-vs-createx");
        bytes32 initCodeHash = keccak256(abi.encodePacked(type(Pinged).creationCode, abi.encode(uint256(1))));
        address onCreateX = CreateXDeployer.predictRaw(salt, initCodeHash);

        _arachnidOnlyChain();
        address onArachnid = CreateXDeployer.predictRaw(salt, initCodeHash);

        assertEq(onArachnid, arachnidAddress(salt, initCodeHash), "Arachnid prediction drifted");
        assertTrue(onArachnid != onCreateX, "the two deployers cannot derive the same address");
    }

    /// @notice `_facet` prefers the proxy over plain CREATE: the facet lands at THIS chain's release address,
    ///         and a second resolution adopts the code already sitting there.
    function test_Arachnid_FacetUsesTheProxyNotPlainCreate() public {
        _arachnidOnlyChain();
        FacetHarness harness = new FacetHarness();

        bytes32 salt = keccak256(abi.encodePacked("lattice.ERC20.", LatticeVersion.VERSION));
        address released = arachnidAddress(salt, keccak256(vm.getCode("src/tokens/ERC20/ERC20.sol:ERC20")));

        address facet = harness.facet("ERC20");
        assertEq(facet, released, "_facet did not take the Arachnid release address");
        assertGt(facet.code.length, 0, "no code at the released address");
        assertEq(harness.facet("ERC20"), facet, "_facet redeployed instead of reusing the released facet");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                         NO DETERMINISTIC DEPLOYER
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice With NEITHER deployer on the chain, `_facet` still works through the plain-CREATE fallback:
    ///         the facet lands at the harness's next CREATE address, not at any deterministic one.
    /// @dev Foundry's test EVM PRE-DEPLOYS the Arachnid proxy (it is also Foundry's default CREATE2
    ///      deployer), so reaching a genuinely deployer-less chain means etching that address empty too.
    function test_NoDeployer_FacetFallsBackToPlainCreate() public {
        vm.etch(CANONICAL, "");
        vm.etch(ArachnidProxy.PROXY, "");
        assertFalse(CreateXDeployer.hasRawDeployer(), "a deterministic deployer has code on a bare chain");

        FacetHarness harness = new FacetHarness();
        address expected = vm.computeCreateAddress(address(harness), vm.getNonce(address(harness)));
        address facet = harness.facet("ERC20");

        assertEq(facet, expected, "_facet did not plain-CREATE the facet");
        assertGt(facet.code.length, 0, "no code at the plain-CREATE address");
    }

    //*//////////////////////////////////////////////////////////////////////////
    //                            DEPLOYER PRECEDENCE
    //////////////////////////////////////////////////////////////////////////*//

    /// @notice CreateX wins wherever it has code: etching the proxy ALONGSIDE it must not move a single
    ///         release address — predictRaw stays the CreateX-guarded derivation and deployRaw lands there.
    function test_CreateXTakesPrecedenceOverTheArachnidProxy() public {
        vm.etch(ArachnidProxy.PROXY, ArachnidProxy.RUNTIME);

        bytes32 salt = keccak256("lattice.test.precedence");
        bytes memory initCode = abi.encodePacked(type(Pinged).creationCode, abi.encode(uint256(7)));
        bytes32 initCodeHash = keccak256(initCode);

        address predicted = CreateXDeployer.predictRaw(salt, initCodeHash);
        assertEq(
            predicted,
            MockCreateX(CANONICAL).computeCreate2Address(keccak256(abi.encode(salt)), initCodeHash),
            "predictRaw left the CreateX guard while CreateX has code"
        );
        assertTrue(predicted != arachnidAddress(salt, initCodeHash), "the proxy derivation leaked in");
        assertEq(CreateXDeployer.deployRaw(salt, initCode), predicted, "deployRaw did not go through CreateX");
    }
}

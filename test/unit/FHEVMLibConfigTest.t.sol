// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ZamaConfig} from "@lattice-test/helpers/fhevm/solidity/config/ZamaConfig.sol";
import {FHE} from "@lattice-test/helpers/fhevm/solidity/lib/FHE.sol";
import {CoprocessorConfig as ZamaCoprocessorConfig} from "@lattice-test/helpers/fhevm/solidity/lib/Impl.sol";
import {CoprocessorConfig, FHEVMLib} from "@lattice/privacy/libraries/FHEVMLib.sol";
import {Test} from "forge-std/Test.sol";

/// @dev Exposes the internal {FHEVMLib} configuration members so tests can call and inspect them externally.
contract ConfigHarness {
    function hostsFor(uint256 chainId) external pure returns (CoprocessorConfig memory) {
        return FHEVMLib.hostsFor(chainId);
    }

    function setCoprocessorForChain() external {
        FHEVMLib.setCoprocessorForChain();
    }

    function config() external pure returns (CoprocessorConfig memory c) {
        c = FHEVMLib.config();
    }
}

/// @dev Reads Zama's own per-chain configuration for the current `block.chainid`.
contract ZamaConfigReader {
    function read() external view returns (ZamaCoprocessorConfig memory) {
        return ZamaConfig.getCoprocessorConfig();
    }
}

/// @dev Writes Zama's configuration through the upstream `FHE.setCoprocessor`, to compare storage layouts.
contract UpstreamSetter {
    function set() external {
        FHE.setCoprocessor(ZamaConfig.getCoprocessorConfig());
    }
}

/// @title FHEVMLibConfigTest
/// @notice Pins the chain table, conflict handling and storage layout of {FHEVMLib}'s coprocessor configuration.
contract FHEVMLibConfigTest is Test {
    ConfigHarness internal h;
    ZamaConfigReader internal zc;
    UpstreamSetter internal up;

    function setUp() public {
        h = new ConfigHarness();
        zc = new ZamaConfigReader();
        up = new UpstreamSetter();
    }

    function test_HostsFor_PinnedRows() public view {
        CoprocessorConfig memory c = h.hostsFor(1);
        assertEq(c.acl, 0xcA2E8f1F656CD25C01F05d0b243Ab1ecd4a8ffb6);
        assertEq(c.executor, 0xD82385dADa1ae3E969447f20A3164F6213100e75);
        assertEq(c.kmsVerifier, 0x77627828a55156b04Ac0DC0eb30467f1a552BB03);
        c = h.hostsFor(11155111);
        assertEq(c.acl, 0xf0Ffdc93b7E186bC2f8CB3dAA75D86d1930A433D);
        assertEq(c.executor, 0x92C920834Ec8941d2C77D188936E1f7A6f49c127);
        assertEq(c.kmsVerifier, 0xbE0E383937d564D7FF0BC3b46c51f0bF8d5C311A);
        c = h.hostsFor(31337);
        assertEq(c.acl, 0x50157CFfD6bBFA2DECe204a89ec419c23ef5755D);
        assertEq(c.executor, 0xe3a9105a3a932253A70F126eb1E3b589C643dD24);
        assertEq(c.kmsVerifier, 0x901F8942346f7AB3a01F6D7613119Bca447Bb030);
    }

    function test_ChainTableMatchesZamaConfig() public {
        uint256[3] memory ids = [uint256(1), 11155111, 31337];
        for (uint256 i; i < 3; ++i) {
            vm.chainId(ids[i]);
            ZamaCoprocessorConfig memory z = zc.read();
            CoprocessorConfig memory c = h.hostsFor(ids[i]);
            assertEq(c.acl, z.ACLAddress);
            assertEq(c.executor, z.CoprocessorAddress);
            assertEq(c.kmsVerifier, z.KMSVerifierAddress);
        }
    }

    function testFuzz_HostsFor_RevertWhen_UnsupportedChain(uint256 id) public {
        vm.assume(id != 1 && id != 11155111 && id != 31337);
        vm.expectRevert(abi.encodeWithSelector(FHEVMLib.FHEVMUnsupportedChain.selector, id));
        h.hostsFor(id);
    }

    /// @dev Zama's config routes these chains; Lattice defers them.
    function test_HostsFor_RevertWhen_PolygonChains() public {
        vm.expectRevert(abi.encodeWithSelector(FHEVMLib.FHEVMUnsupportedChain.selector, 137));
        h.hostsFor(137);
        vm.expectRevert(abi.encodeWithSelector(FHEVMLib.FHEVMUnsupportedChain.selector, 80002));
        h.hostsFor(80002);
    }

    /// @dev Runs on the default chain id 31337.
    function test_SetCoprocessorForChain_WritesEmptySlot() public {
        h.setCoprocessorForChain();
        assertEq(
            vm.load(address(h), FHEVMLib.CONFIG_SLOT),
            bytes32(uint256(uint160(0x50157CFfD6bBFA2DECe204a89ec419c23ef5755D)))
        );
        assertEq(
            vm.load(address(h), bytes32(uint256(FHEVMLib.CONFIG_SLOT) + 1)),
            bytes32(uint256(uint160(0xe3a9105a3a932253A70F126eb1E3b589C643dD24)))
        );
        assertEq(
            vm.load(address(h), bytes32(uint256(FHEVMLib.CONFIG_SLOT) + 2)),
            bytes32(uint256(uint160(0x901F8942346f7AB3a01F6D7613119Bca447Bb030)))
        );
    }

    function test_SetCoprocessorForChain_IdenticalRepeatIsNoOp() public {
        h.setCoprocessorForChain();
        vm.record();
        h.setCoprocessorForChain();
        (, bytes32[] memory writes) = vm.accesses(address(h));
        assertEq(writes.length, 0);
    }

    function test_SetCoprocessorForChain_RevertWhen_Conflicting() public {
        vm.store(address(h), FHEVMLib.CONFIG_SLOT, bytes32(uint256(0xdead)));
        vm.expectRevert(
            abi.encodeWithSelector(
                FHEVMLib.FHEVMConflictingCoprocessor.selector, address(0xdead), address(0), address(0)
            )
        );
        h.setCoprocessorForChain();
    }

    function test_SetCoprocessorForChain_RevertWhen_Partial() public {
        vm.store(
            address(h), FHEVMLib.CONFIG_SLOT, bytes32(uint256(uint160(0x50157CFfD6bBFA2DECe204a89ec419c23ef5755D)))
        );
        vm.expectRevert(
            abi.encodeWithSelector(
                FHEVMLib.FHEVMConflictingCoprocessor.selector,
                address(0x50157CFfD6bBFA2DECe204a89ec419c23ef5755D),
                address(0),
                address(0)
            )
        );
        h.setCoprocessorForChain();
    }

    function test_ConfigSlot_IsErc7201OfConfidentialStorageConfig() public pure {
        assertEq(
            FHEVMLib.CONFIG_SLOT,
            keccak256(abi.encode(uint256(keccak256("confidential.storage.config")) - 1)) & ~bytes32(uint256(0xff))
        );
    }

    function test_ConfigLayoutMatchesUpstream() public {
        h.setCoprocessorForChain();
        up.set();
        for (uint256 i; i < 3; ++i) {
            assertEq(
                vm.load(address(h), bytes32(uint256(FHEVMLib.CONFIG_SLOT) + i)),
                vm.load(address(up), bytes32(uint256(FHEVMLib.CONFIG_SLOT) + i))
            );
        }
    }

    /// @dev Specification H-33: the local row is local-only, the CREATE addresses of Zama's published example key.
    function test_Chain31337RowIsTheExampleDeployerCreateAddresses() public view {
        // Key published in the fhevm host-contracts `.env.example`.
        address zamaExampleDeployer = 0x8B8f5091f8b9817EF69cFC1E8B2f721BafF60DF4;
        CoprocessorConfig memory c = h.hostsFor(31337);
        assertEq(c.acl, vm.computeCreateAddress(zamaExampleDeployer, 1));
        assertEq(c.executor, vm.computeCreateAddress(zamaExampleDeployer, 3));
        assertEq(c.kmsVerifier, vm.computeCreateAddress(zamaExampleDeployer, 4));
    }
}

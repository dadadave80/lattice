// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {FacetCut, FacetCutAction} from "@diamond/libraries/DiamondLib.sol";
import {DeployERC7984} from "@lattice-script/base/tokens/DeployERC7984.s.sol";
import {ArchiveFork} from "@lattice-test/helpers/ArchiveFork.sol";
import {ERC7984TestFacet} from "@lattice-test/helpers/ERC7984TestFacet.sol";
import {FHEVMLibDiff, IFHEVMProbe} from "@lattice-test/helpers/FHEVMLibProbes.sol";
import {Lattice} from "@lattice/Lattice.sol";
import {euint64} from "@lattice/interfaces/external/fhevm/EncryptedTypes.sol";
import {IACL} from "@lattice/interfaces/external/fhevm/IACL.sol";
import {IERC7984} from "@lattice/interfaces/tokens/IERC7984.sol";
import {CoprocessorConfig, FHEVMLib} from "@lattice/privacy/libraries/FHEVMLib.sol";

/// @title IVersioned
/// @author ABI-equivalent interface authored fresh from Zama FHEVM's public ABI (https://github.com/zama-ai/fhevm).
///         Upstream license: BSD-3-Clause-Clear.
/// @notice The version getter every Zama FHEVM (fully homomorphic encryption virtual machine) host contract exposes.
interface IVersioned {
    function getVersion() external view returns (string memory);
}

/// @title IFHEVMExecutorHcu
/// @author ABI-equivalent interface authored fresh from Zama FHEVM's public ABI (https://github.com/zama-ai/fhevm).
///         Upstream license: BSD-3-Clause-Clear.
/// @notice The executor's getter for its HCU (homomorphic complexity unit) limit contract.
interface IFHEVMExecutorHcu {
    function getHCULimitAddress() external view returns (address);
}

/// @title IHCUAllowlist
/// @author ABI-equivalent interface authored fresh from Zama FHEVM's public ABI (https://github.com/zama-ai/fhevm).
///         Upstream license: BSD-3-Clause-Clear.
/// @notice The HCU limit contract's allowlist switch.
interface IHCUAllowlist {
    function isAllowlistActivated() external view returns (bool);
}

contract ERC7984ForkBatcher {
    IERC7984 private immutable token;
    euint64 public immutable amount;

    constructor(IERC7984 token_) {
        token = token_;
        FHEVMLib.setCoprocessorForChain();
        amount = FHEVMLib.asEuint64(1);
        FHEVMLib.allowThis(amount);
        FHEVMLib.allow(amount, address(token_));
    }

    function transfersOf(euint64 amount_, uint256 k, address to) external {
        for (uint256 i; i < k; ++i) {
            token.confidentialTransfer(to, amount_);
        }
    }
}

/// @notice Shared ERC-7984 (confidential fungible token) tests against live fully homomorphic encryption virtual
///         machine (FHEVM) hosts.
abstract contract ERC7984ForkBase is FHEVMLibDiff {
    CoprocessorConfig internal cfg;
    ERC7984ForkBatcher private batcher;

    function _selectFork(string memory envVar, string memory rpcAlias, uint256 blockNumber) internal {
        if (bytes(vm.envOr(envVar, string(""))).length == 0) {
            vm.skip(true);
            return;
        }
        if (!ArchiveFork.select(rpcAlias, blockNumber)) return;
        cfg = FHEVMLib.hostsFor(block.chainid);
    }

    /// @dev The homomorphic complexity unit (HCU) test gets its own committed setup transaction.
    function beforeTestSetup(bytes4 testSelector) public pure returns (bytes[] memory calls) {
        if (testSelector == this.test_Fork_Hcu_SameSenderTransfersFit22Revert23.selector) {
            calls = new bytes[](1);
            calls[0] = abi.encodeCall(ERC7984ForkBase.prepareBatcher, ());
        }
    }

    function prepareBatcher() external {
        // Persist the amount grants in an earlier transaction so the batch measures only transfer costs.
        IERC7984 token = _deployToken();
        batcher = new ERC7984ForkBatcher(token);
        ERC7984TestFacet(address(token)).mint(address(batcher), 1_000_000);
    }

    function test_Fork_ChainTableHasLiveCode() public view {
        // Pin the access control list (ACL), executor, and Key Management Service (KMS) verifier.
        assertGt(cfg.acl.code.length, 0);
        assertGt(cfg.executor.code.length, 0);
        assertGt(cfg.kmsVerifier.code.length, 0);
    }

    function test_Fork_ProofFreeMembersMatchFHE() public {
        address user = makeAddr("probe user");
        _install(false, cfg);
        // Class 3 requires a signed input proof. The local differential harness covers it.
        bytes32[3] memory classes;
        vm.startPrank(user);
        classes[1] = IFHEVMProbe(PROBE_AT).seed64(7);
        classes[2] = IFHEVMProbe(PROBE_AT).seedBool(true);
        vm.stopPrank();

        for (uint8 id; id <= 18; ++id) {
            if (id != 4 && id != 16) _checkOperands(user, id, classes);
        }
    }

    function test_Fork_DeployAndProofFreeTransfer() public {
        IERC7984 token = _deployToken();
        address holder = makeAddr("holder");
        address alice = makeAddr("alice");
        ERC7984TestFacet(address(token)).mint(holder, 1_000_000);

        euint64 balance = token.confidentialBalanceOf(holder);
        vm.prank(holder);
        token.confidentialTransfer(alice, balance);

        bytes32 aliceBalance = euint64.unwrap(token.confidentialBalanceOf(alice));
        assertTrue(IACL(cfg.acl).isAllowed(aliceBalance, alice));
        assertTrue(IACL(cfg.acl).isAllowed(aliceBalance, address(token)));
    }

    function test_Fork_Hcu_SameSenderTransfersFit22Revert23() public {
        euint64 amount = batcher.amount();
        address bob = makeAddr("bob");
        uint256 snapshot = vm.snapshotState();
        batcher.transfersOf(amount, 22, bob);
        assertTrue(vm.revertToState(snapshot));

        vm.expectRevert(bytes4(0xfc344870));
        batcher.transfersOf(amount, 23, bob);
    }

    function _deployToken() private returns (IERC7984) {
        (FacetCut[] memory base, address init, bytes memory initCalldata) =
            new DeployERC7984().buildCuts("Confidential Token", "cTKN", "");
        FacetCut[] memory cuts = new FacetCut[](base.length + 1);
        for (uint256 i; i < base.length; ++i) {
            cuts[i] = base[i];
        }
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = ERC7984TestFacet.mint.selector;
        cuts[base.length] = FacetCut(address(new ERC7984TestFacet()), FacetCutAction.Add, selectors);

        Lattice diamond = new Lattice();
        diamond.initialize(cuts, init, initCalldata);
        return IERC7984(address(diamond));
    }

    function _checkOperands(address user, uint8 id, bytes32[3] memory classes) private {
        uint64[3] memory scalars = [uint64(0), 1, type(uint64).max];
        if (id == 2 || id == 3) {
            for (uint256 i; i < scalars.length; ++i) {
                _check(user, id, 0, 0, 0, scalars[i], true);
            }
            return;
        }
        for (uint256 i; i < classes.length; ++i) {
            if (id == 8) {
                for (uint256 j; j < scalars.length; ++j) {
                    _check(user, id, classes[i], 0, 0, scalars[j], i == 1);
                }
            } else if (id == 9) {
                for (uint256 j; j < classes.length; ++j) {
                    for (uint256 k; k < classes.length; ++k) {
                        _check(user, id, classes[i], classes[j], classes[k], 0, i == 2 && j == 1 && k == 1);
                    }
                }
            } else if ((id >= 5 && id <= 7) || id >= 17) {
                for (uint256 j; j < classes.length; ++j) {
                    _check(user, id, classes[i], classes[j], 0, 0, i == 1 && j == 1);
                }
            } else {
                _check(user, id, classes[i], 0, 0, 0, id <= 1 || i == (id == 11 ? 2 : 1));
            }
        }
    }

    function _check(address user, uint8 id, bytes32 a, bytes32 b, bytes32 c, uint64 scalar, bool mustSucceed) private {
        (bool ok,,) = _diff(user, abi.encodeCall(IFHEVMProbe.op, (id, a, b, c, scalar, "")));
        if (mustSucceed) assertTrue(ok, "well-typed proof-free operation reverted");
    }
}

contract ERC7984SepoliaFork is ERC7984ForkBase {
    function setUp() public {
        _selectFork("SEPOLIA_RPC_URL", "sepolia", 12186333);
    }

    function test_Fork_HostVersionsPinned() public view {
        assertEq(IVersioned(cfg.acl).getVersion(), "ACL v0.5.0");
        assertEq(IVersioned(cfg.executor).getVersion(), "FHEVMExecutor v0.6.0");
    }

    function test_Fork_HcuAllowlistInactive() public view {
        // Once Zama activates its HCU allowlist, unadmitted diamonds stop working.
        address hcu = IFHEVMExecutorHcu(cfg.executor).getHCULimitAddress();
        assertEq(hcu, 0xa10998783c8CF88D886Bc30307e631D6686F0A22);
        assertEq(IHCUAllowlist(hcu).isAllowlistActivated(), false, "HCU allowlist is active");
    }
}

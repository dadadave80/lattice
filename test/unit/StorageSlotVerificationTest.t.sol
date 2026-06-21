// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

// ---------------------------------------------------------------------------
// ERC-7201 storage-slot constants + ERC-165 map-slot constants under test
// ---------------------------------------------------------------------------

// access
import {
    ACCESS_CONTROL_ENUMERABLE_STORAGE_SLOT,
    ERC165_MAP_IACCESSCONTROLENUMERABLE_SLOT
} from "@lattice/access/libraries/AccessControlEnumerableLib.sol";
import {
    ACCESS_CONTROL_STORAGE_SLOT,
    ERC165_MAP_IACCESSCONTROL_SLOT,
    ERC165_STORAGE_LOCATION
} from "@lattice/access/libraries/AccessControlLib.sol";
import {
    ACCESS_CONTROL_TIMED_STORAGE_SLOT,
    ERC165_MAP_IACCESSCONTROLTIMED_SLOT
} from "@lattice/access/libraries/AccessControlTimedLib.sol";
import {
    ACCESS_MANAGED_STORAGE_SLOT,
    ERC165_MAP_IACCESSMANAGED_SLOT
} from "@lattice/access/libraries/AccessManagedLib.sol";
import {
    ACCESS_MANAGER_STORAGE_SLOT,
    ERC165_MAP_IACCESSMANAGER_SLOT
} from "@lattice/access/libraries/AccessManagerLib.sol";

// tokens
import {
    ERC1155_STORAGE_SLOT,
    ERC165_MAP_IERC1155METADATAURI_SLOT,
    ERC165_MAP_IERC1155_SLOT
} from "@lattice/tokens/libraries/ERC1155Lib.sol";
import {ERC165_MAP_IERC20CAPPED_SLOT, ERC20CAPPED_STORAGE_SLOT} from "@lattice/tokens/libraries/ERC20CappedLib.sol";
import {ERC165_MAP_IERC20_SLOT, ERC20_STORAGE_SLOT} from "@lattice/tokens/libraries/ERC20Lib.sol";
import {ERC165_MAP_IERC2981_SLOT, ERC2981_STORAGE_SLOT} from "@lattice/tokens/libraries/ERC2981Lib.sol";
import {ERC165_MAP_IERC4626_SLOT, ERC4626_STORAGE_SLOT} from "@lattice/tokens/libraries/ERC4626Lib.sol";
import {
    ERC165_MAP_IERC721METADATA_SLOT,
    ERC165_MAP_IERC721_SLOT,
    ERC721_STORAGE_SLOT
} from "@lattice/tokens/libraries/ERC721Lib.sol";
import {
    ERC165_MAP_ERC4906_SLOT,
    ERC721URISTORAGE_STORAGE_SLOT
} from "@lattice/tokens/libraries/ERC721URIStorageLib.sol";

// governance
import {GOVERNED_DIAMOND_CUT_STORAGE_SLOT} from "@lattice/governance/libraries/GovernedDiamondCutLib.sol";
import {
    ERC165_MAP_IGOVERNEDSAFEDIAMONDCUT_SLOT,
    GOVERNED_SAFE_DIAMOND_CUT_STORAGE_SLOT
} from "@lattice/governance/libraries/GovernedSafeDiamondCutLib.sol";
import {ERC165_MAP_IGOVERNOR_SLOT, GOVERNOR_STORAGE_SLOT} from "@lattice/governance/libraries/GovernorLib.sol";
import {SAFE_DIAMOND_CUT_STORAGE_SLOT} from "@lattice/governance/libraries/SafeDiamondCutLib.sol";
import {
    ERC165_MAP_ISAFEHARBORADOPTER_SLOT,
    SAFE_HARBOR_ADOPTER_STORAGE_SLOT
} from "@lattice/governance/libraries/SafeHarborAdopterLib.sol";
import {
    ERC165_MAP_ITIMELOCKCONTROLLER_SLOT,
    TIMELOCK_CONTROLLER_STORAGE_SLOT
} from "@lattice/governance/libraries/TimelockControllerLib.sol";
import {ERC165_MAP_IVOTES_SLOT, VOTES_STORAGE_SLOT} from "@lattice/governance/libraries/VotesLib.sol";

// defi
import {
    AAVE_V3_ADAPTER_STORAGE_SLOT,
    ERC165_MAP_IAAVEV3ADAPTER_SLOT,
    ERC165_MAP_IPROTOCOLADAPTER_SLOT
} from "@lattice/defi/libraries/AaveV3AdapterLib.sol";
import {
    COMPOUND_V3_ADAPTER_STORAGE_SLOT,
    ERC165_MAP_ICOMPOUNDV3ADAPTER_SLOT
} from "@lattice/defi/libraries/CompoundV3AdapterLib.sol";
import {
    CURVE_STABLE_SWAP_ADAPTER_STORAGE_SLOT,
    ERC165_MAP_ICURVESTABLESWAPADAPTER_SLOT
} from "@lattice/defi/libraries/CurveStableSwapAdapterLib.sol";
import {
    ERC165_MAP_IERC4626ADAPTER_SLOT,
    ERC4626_ADAPTER_STORAGE_SLOT
} from "@lattice/defi/libraries/ERC4626AdapterLib.sol";
import {ERC165_MAP_ILIDOADAPTER_SLOT, LIDO_ADAPTER_STORAGE_SLOT} from "@lattice/defi/libraries/LidoAdapterLib.sol";
import {
    ERC165_MAP_ISTRATEGYMANAGER_SLOT,
    STRATEGY_MANAGER_STORAGE_SLOT
} from "@lattice/defi/libraries/StrategyManagerLib.sol";
import {
    ERC165_MAP_IUNISWAPV3ADAPTER_SLOT,
    UNISWAP_V3_ADAPTER_STORAGE_SLOT
} from "@lattice/defi/libraries/UniswapV3AdapterLib.sol";
import {ERC165_MAP_IVAULTCORE_SLOT, VAULT_CORE_STORAGE_SLOT} from "@lattice/defi/libraries/VaultCoreLib.sol";

// amm
import {
    CONSTANT_PRODUCT_STORAGE_SLOT,
    ERC165_MAP_ICONSTANTPRODUCT_SLOT
} from "@lattice/amm/libraries/ConstantProductLib.sol";

// oracles
import {
    CHAINLINK_ADAPTER_STORAGE_SLOT,
    ERC165_MAP_ICHAINLINKADAPTER_SLOT
} from "@lattice/oracles/libraries/ChainlinkAdapterLib.sol";
import {
    CHAINLINK_VRF_STORAGE_SLOT,
    ERC165_MAP_ICHAINLINKVRF_SLOT
} from "@lattice/oracles/libraries/ChainlinkVRFLib.sol";
import {ERC165_MAP_ITWAPORACLE_SLOT, TWAP_ORACLE_STORAGE_SLOT} from "@lattice/oracles/libraries/TWAPOracleLib.sol";

// security
import {
    CIRCUIT_BREAKER_STORAGE_SLOT,
    ERC165_MAP_ICIRCUITBREAKER_SLOT
} from "@lattice/security/libraries/CircuitBreakerLib.sol";
import {
    EMERGENCY_STOP_STORAGE_SLOT,
    ERC165_MAP_IEMERGENCYSTOP_SLOT
} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {
    ERC165_MAP_IINVARIANTCHECKER_SLOT,
    INVARIANT_CHECKER_STORAGE_SLOT
} from "@lattice/security/libraries/InvariantCheckerLib.sol";
import {ERC165_MAP_IPAUSABLE_SLOT, PAUSABLE_STORAGE_SLOT} from "@lattice/security/libraries/PausableLib.sol";
import {ERC165_MAP_IRATELIMITER_SLOT, RATE_LIMITER_STORAGE_SLOT} from "@lattice/security/libraries/RateLimiterLib.sol";
import {
    ERC165_MAP_IREENTRANCYGUARD_SLOT,
    REENTRANCY_GUARD_STORAGE_SLOT
} from "@lattice/security/libraries/ReentrancyGuardLib.sol";

// utils
import {EIP712_STORAGE_SLOT, ERC165_MAP_IEIP712_SLOT} from "@lattice/utils/libraries/EIP712Lib.sol";
import {ERC165_MAP_INONCES_SLOT, NONCES_STORAGE_SLOT} from "@lattice/utils/libraries/NoncesLib.sol";
import {
    ERC165_MAP_IVESTINGWALLET_SLOT,
    VESTING_WALLET_STORAGE_SLOT
} from "@lattice/utils/libraries/VestingWalletLib.sol";

// privacy
import {
    COMMIT_REVEAL_STORAGE_SLOT,
    ERC165_MAP_ICOMMITREVEAL_SLOT
} from "@lattice/privacy/libraries/CommitRevealLib.sol";
import {ERC165_MAP_IERC5564ANNOUNCER_SLOT} from "@lattice/privacy/libraries/ERC5564AnnouncerLib.sol";
import {
    ERC165_MAP_IERC6538REGISTRY_SLOT,
    ERC6538REGISTRY_STORAGE_SLOT
} from "@lattice/privacy/libraries/ERC6538RegistryLib.sol";
import {ERC165_MAP_IGROTH16VERIFIER_SLOT} from "@lattice/privacy/libraries/Groth16VerifierLib.sol";
import {ERC165_MAP_IPLONKVERIFIER_SLOT} from "@lattice/privacy/libraries/PlonkVerifierLib.sol";
import {ERC165_MAP_ISEMAPHORE_SLOT, SEMAPHORE_STORAGE_SLOT} from "@lattice/privacy/libraries/SemaphoreLib.sol";

// ens
import {ENS_RESOLVER_STORAGE_SLOT, ERC165_MAP_IENSRESOLVER_SLOT} from "@lattice/ens/libraries/ENSResolverLib.sol";
import {
    ENS_REVERSE_CLAIMER_STORAGE_SLOT,
    ERC165_MAP_IENSREVERSECLAIMER_SLOT
} from "@lattice/ens/libraries/ENSReverseClaimerLib.sol";
import {
    ENS_SUBNAME_ISSUER_STORAGE_SLOT,
    ERC165_MAP_IENSSUBNAMEISSUER_SLOT
} from "@lattice/ens/libraries/ENSSubnameIssuerLib.sol";

// ---------------------------------------------------------------------------
// Interfaces (for type(...).interfaceId)
// ---------------------------------------------------------------------------

import {IAaveV3Adapter} from "@lattice/interfaces/IAaveV3Adapter.sol";
import {IAccessControl} from "@lattice/interfaces/IAccessControl.sol";
import {IAccessControlEnumerable} from "@lattice/interfaces/IAccessControlEnumerable.sol";
import {IAccessControlTimed} from "@lattice/interfaces/IAccessControlTimed.sol";
import {IAccessManaged} from "@lattice/interfaces/IAccessManaged.sol";
import {IAccessManager} from "@lattice/interfaces/IAccessManager.sol";
import {IChainlinkAdapter} from "@lattice/interfaces/IChainlinkAdapter.sol";
import {IChainlinkVRF} from "@lattice/interfaces/IChainlinkVRF.sol";
import {ICircuitBreaker} from "@lattice/interfaces/ICircuitBreaker.sol";
import {ICommitReveal} from "@lattice/interfaces/ICommitReveal.sol";
import {ICompoundV3Adapter} from "@lattice/interfaces/ICompoundV3Adapter.sol";
import {IConstantProduct} from "@lattice/interfaces/IConstantProduct.sol";
import {ICurveStableSwapAdapter} from "@lattice/interfaces/ICurveStableSwapAdapter.sol";
import {IEIP712} from "@lattice/interfaces/IEIP712.sol";
import {IENSResolver} from "@lattice/interfaces/IENSResolver.sol";
import {IENSReverseClaimer} from "@lattice/interfaces/IENSReverseClaimer.sol";
import {IENSSubnameIssuer} from "@lattice/interfaces/IENSSubnameIssuer.sol";
import {IERC20} from "@lattice/interfaces/IERC20.sol";
import {IERC20Capped} from "@lattice/interfaces/IERC20Capped.sol";
import {IERC2981} from "@lattice/interfaces/IERC2981.sol";
import {IERC4626} from "@lattice/interfaces/IERC4626.sol";
import {IERC4626Adapter} from "@lattice/interfaces/IERC4626Adapter.sol";
import {IERC5564Announcer} from "@lattice/interfaces/IERC5564Announcer.sol";
import {IERC6538Registry} from "@lattice/interfaces/IERC6538Registry.sol";
import {IEmergencyStop} from "@lattice/interfaces/IEmergencyStop.sol";
import {IGovernedSafeDiamondCut} from "@lattice/interfaces/IGovernedSafeDiamondCut.sol";
import {IGovernor} from "@lattice/interfaces/IGovernor.sol";
import {IGroth16Verifier} from "@lattice/interfaces/IGroth16Verifier.sol";
import {IInvariantChecker} from "@lattice/interfaces/IInvariantChecker.sol";
import {ILidoAdapter} from "@lattice/interfaces/ILidoAdapter.sol";
import {INonces} from "@lattice/interfaces/INonces.sol";
import {IPausable} from "@lattice/interfaces/IPausable.sol";
import {IPlonkVerifier} from "@lattice/interfaces/IPlonkVerifier.sol";
import {IProtocolAdapter} from "@lattice/interfaces/IProtocolAdapter.sol";
import {IRateLimiter} from "@lattice/interfaces/IRateLimiter.sol";
import {IReentrancyGuard} from "@lattice/interfaces/IReentrancyGuard.sol";
import {ISafeHarborAdopter} from "@lattice/interfaces/ISafeHarborAdopter.sol";
import {ISemaphore} from "@lattice/interfaces/ISemaphore.sol";
import {IStrategyManager} from "@lattice/interfaces/IStrategyManager.sol";
import {ITWAPOracle} from "@lattice/interfaces/ITWAPOracle.sol";
import {ITimelockController} from "@lattice/interfaces/ITimelockController.sol";
import {IUniswapV3Adapter} from "@lattice/interfaces/IUniswapV3Adapter.sol";
import {IVaultCore} from "@lattice/interfaces/IVaultCore.sol";
import {IVestingWallet} from "@lattice/interfaces/IVestingWallet.sol";
import {IVotes} from "@lattice/interfaces/IVotes.sol";

/// @title StorageSlotVerificationTest
/// @notice Re-derives every ERC-7201 storage slot and ERC-165 map slot from first principles
///         and asserts equality against the declared constants. A mismatch here means a module's
///         storage slot constant is wrong and would collide with another module's storage, or that
///         an ERC-165 interface would be registered at the wrong slot. (L-4)
/// @dev This test is the executable counterpart of `STORAGE_REGISTRY.md`. Every storage-bearing
///      module must have (a) a `test_<Module>StorageSlot` derivation check, (b) a
///      `test_Erc165Map<Module>Slot` derivation check if it registers an interface, and (c) an entry
///      in both the global uniqueness arrays below. CI runs this contract on every change.
contract StorageSlotVerificationTest is Test {
    // Canonical EIP interface IDs registered by the token modules. These are intentionally NOT
    // `type(I...).interfaceId` of the Lattice interfaces: the Lattice `IERC721`/`IERC1155` interfaces
    // bundle metadata + receiver selectors, so their computed `type().interfaceId` (0xdbf24b52 /
    // 0xd73f4e3a) differs from the standard. External ERC-165 callers query the canonical standard
    // IDs below, so the libraries correctly register those literal IDs. The metadata-extension and
    // ERC-4906 interfaces likewise have no standalone importable type in this repo. Every literal
    // here matches the value asserted in the corresponding library's derivation comment.
    bytes4 internal constant IERC721_ID = 0x80ac58cd;
    bytes4 internal constant IERC721_METADATA_ID = 0x5b5e139f;
    bytes4 internal constant IERC1155_ID = 0xd9b67a26;
    bytes4 internal constant IERC1155_METADATA_URI_ID = 0x0e89341c;
    bytes4 internal constant ERC4906_ID = 0x49064906;

    // ---- ERC-7201 slot derivation helper ----

    function _erc7201Slot(string memory id) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(keccak256(bytes(id))) - 1)) & ~bytes32(uint256(0xff));
    }

    // ---- ERC-165 map slot derivation helper ----

    function _erc165MapSlot(bytes4 interfaceId, bytes32 erc165Storage) internal pure returns (bytes32) {
        return keccak256(abi.encode(interfaceId, erc165Storage));
    }

    // ======================== ERC-7201 Storage Slots ========================

    // ---- access ----

    function test_AccessControlStorageSlot() public pure {
        assertEq(
            ACCESS_CONTROL_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.AccessControl"),
            "AccessControl storage slot mismatch"
        );
    }

    function test_AccessControlEnumerableStorageSlot() public pure {
        assertEq(
            ACCESS_CONTROL_ENUMERABLE_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.AccessControlEnumerable"),
            "AccessControlEnumerable storage slot mismatch"
        );
    }

    function test_AccessControlTimedStorageSlot() public pure {
        assertEq(
            ACCESS_CONTROL_TIMED_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.AccessControlTimed"),
            "AccessControlTimed storage slot mismatch"
        );
    }

    function test_AccessManagerStorageSlot() public pure {
        assertEq(
            ACCESS_MANAGER_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.AccessManager"),
            "AccessManager storage slot mismatch"
        );
    }

    function test_AccessManagedStorageSlot() public pure {
        assertEq(
            ACCESS_MANAGED_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.AccessManaged"),
            "AccessManaged storage slot mismatch"
        );
    }

    // ---- tokens ----

    function test_ERC20StorageSlot() public pure {
        assertEq(ERC20_STORAGE_SLOT, _erc7201Slot("lattice.storage.ERC20"), "ERC20 storage slot mismatch");
    }

    function test_ERC20CappedStorageSlot() public pure {
        assertEq(
            ERC20CAPPED_STORAGE_SLOT, _erc7201Slot("lattice.storage.ERC20Capped"), "ERC20Capped storage slot mismatch"
        );
    }

    function test_ERC721StorageSlot() public pure {
        assertEq(ERC721_STORAGE_SLOT, _erc7201Slot("lattice.storage.ERC721"), "ERC721 storage slot mismatch");
    }

    function test_ERC721URIStorageStorageSlot() public pure {
        assertEq(
            ERC721URISTORAGE_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.ERC721URIStorage"),
            "ERC721URIStorage storage slot mismatch"
        );
    }

    function test_ERC1155StorageSlot() public pure {
        assertEq(ERC1155_STORAGE_SLOT, _erc7201Slot("lattice.storage.ERC1155"), "ERC1155 storage slot mismatch");
    }

    function test_ERC2981StorageSlot() public pure {
        assertEq(ERC2981_STORAGE_SLOT, _erc7201Slot("lattice.storage.ERC2981"), "ERC2981 storage slot mismatch");
    }

    function test_ERC4626StorageSlot() public pure {
        assertEq(ERC4626_STORAGE_SLOT, _erc7201Slot("lattice.storage.ERC4626"), "ERC4626 storage slot mismatch");
    }

    // ---- governance ----

    function test_VotesStorageSlot() public pure {
        assertEq(VOTES_STORAGE_SLOT, _erc7201Slot("lattice.storage.Votes"), "Votes storage slot mismatch");
    }

    function test_GovernorStorageSlot() public pure {
        assertEq(GOVERNOR_STORAGE_SLOT, _erc7201Slot("lattice.storage.Governor"), "Governor storage slot mismatch");
    }

    function test_TimelockControllerStorageSlot() public pure {
        assertEq(
            TIMELOCK_CONTROLLER_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.TimelockController"),
            "TimelockController storage slot mismatch"
        );
    }

    function test_GovernedDiamondCutStorageSlot() public pure {
        assertEq(
            GOVERNED_DIAMOND_CUT_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.GovernedDiamondCut"),
            "GovernedDiamondCut storage slot mismatch"
        );
    }

    function test_SafeDiamondCutStorageSlot() public pure {
        assertEq(
            SAFE_DIAMOND_CUT_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.SafeDiamondCut"),
            "SafeDiamondCut storage slot mismatch"
        );
    }

    function test_GovernedSafeDiamondCutStorageSlot() public pure {
        assertEq(
            GOVERNED_SAFE_DIAMOND_CUT_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.GovernedSafeDiamondCut"),
            "GovernedSafeDiamondCut storage slot mismatch"
        );
    }

    function test_SafeHarborAdopterStorageSlot() public pure {
        assertEq(
            SAFE_HARBOR_ADOPTER_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.SafeHarborAdopter"),
            "SafeHarborAdopter storage slot mismatch"
        );
    }

    // ---- defi ----

    function test_VaultCoreStorageSlot() public pure {
        assertEq(VAULT_CORE_STORAGE_SLOT, _erc7201Slot("lattice.storage.VaultCore"), "VaultCore storage slot mismatch");
    }

    function test_StrategyManagerStorageSlot() public pure {
        assertEq(
            STRATEGY_MANAGER_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.StrategyManager"),
            "StrategyManager storage slot mismatch"
        );
    }

    function test_AaveV3AdapterStorageSlot() public pure {
        assertEq(
            AAVE_V3_ADAPTER_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.AaveV3Adapter"),
            "AaveV3Adapter storage slot mismatch"
        );
    }

    function test_CompoundV3AdapterStorageSlot() public pure {
        assertEq(
            COMPOUND_V3_ADAPTER_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.CompoundV3Adapter"),
            "CompoundV3Adapter storage slot mismatch"
        );
    }

    function test_ERC4626AdapterStorageSlot() public pure {
        assertEq(
            ERC4626_ADAPTER_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.ERC4626Adapter"),
            "ERC4626Adapter storage slot mismatch"
        );
    }

    function test_CurveStableSwapAdapterStorageSlot() public pure {
        assertEq(
            CURVE_STABLE_SWAP_ADAPTER_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.CurveStableSwapAdapter"),
            "CurveStableSwapAdapter storage slot mismatch"
        );
    }

    function test_LidoAdapterStorageSlot() public pure {
        assertEq(
            LIDO_ADAPTER_STORAGE_SLOT, _erc7201Slot("lattice.storage.LidoAdapter"), "LidoAdapter storage slot mismatch"
        );
    }

    function test_UniswapV3AdapterStorageSlot() public pure {
        assertEq(
            UNISWAP_V3_ADAPTER_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.UniswapV3Adapter"),
            "UniswapV3Adapter storage slot mismatch"
        );
    }

    // ---- amm ----

    function test_ConstantProductStorageSlot() public pure {
        assertEq(
            CONSTANT_PRODUCT_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.ConstantProduct"),
            "ConstantProduct storage slot mismatch"
        );
    }

    // ---- oracles ----

    function test_ChainlinkAdapterStorageSlot() public pure {
        assertEq(
            CHAINLINK_ADAPTER_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.ChainlinkAdapter"),
            "ChainlinkAdapter storage slot mismatch"
        );
    }

    function test_ChainlinkVRFStorageSlot() public pure {
        assertEq(
            CHAINLINK_VRF_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.ChainlinkVRF"),
            "ChainlinkVRF storage slot mismatch"
        );
    }

    function test_TWAPOracleStorageSlot() public pure {
        assertEq(
            TWAP_ORACLE_STORAGE_SLOT, _erc7201Slot("lattice.storage.TWAPOracle"), "TWAPOracle storage slot mismatch"
        );
    }

    // ---- security ----

    function test_PausableStorageSlot() public pure {
        assertEq(PAUSABLE_STORAGE_SLOT, _erc7201Slot("lattice.storage.Pausable"), "Pausable storage slot mismatch");
    }

    function test_ReentrancyGuardStorageSlot() public pure {
        assertEq(
            REENTRANCY_GUARD_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.ReentrancyGuard"),
            "ReentrancyGuard storage slot mismatch"
        );
    }

    function test_RateLimiterStorageSlot() public pure {
        assertEq(
            RATE_LIMITER_STORAGE_SLOT, _erc7201Slot("lattice.storage.RateLimiter"), "RateLimiter storage slot mismatch"
        );
    }

    function test_CircuitBreakerStorageSlot() public pure {
        assertEq(
            CIRCUIT_BREAKER_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.CircuitBreaker"),
            "CircuitBreaker storage slot mismatch"
        );
    }

    function test_EmergencyStopStorageSlot() public pure {
        assertEq(
            EMERGENCY_STOP_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.EmergencyStop"),
            "EmergencyStop storage slot mismatch"
        );
    }

    function test_InvariantCheckerStorageSlot() public pure {
        assertEq(
            INVARIANT_CHECKER_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.InvariantChecker"),
            "InvariantChecker storage slot mismatch"
        );
    }

    // ---- utils ----

    function test_EIP712StorageSlot() public pure {
        assertEq(EIP712_STORAGE_SLOT, _erc7201Slot("lattice.storage.EIP712"), "EIP712 storage slot mismatch");
    }

    function test_NoncesStorageSlot() public pure {
        assertEq(NONCES_STORAGE_SLOT, _erc7201Slot("lattice.storage.Nonces"), "Nonces storage slot mismatch");
    }

    function test_VestingWalletStorageSlot() public pure {
        assertEq(
            VESTING_WALLET_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.VestingWallet"),
            "VestingWallet storage slot mismatch"
        );
    }

    // ---- privacy ----

    function test_ERC6538RegistryStorageSlot() public pure {
        assertEq(
            ERC6538REGISTRY_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.ERC6538Registry"),
            "ERC6538Registry storage slot mismatch"
        );
    }

    function test_CommitRevealStorageSlot() public pure {
        assertEq(
            COMMIT_REVEAL_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.CommitReveal"),
            "CommitReveal storage slot mismatch"
        );
    }

    function test_SemaphoreStorageSlot() public pure {
        assertEq(SEMAPHORE_STORAGE_SLOT, _erc7201Slot("lattice.storage.Semaphore"), "Semaphore storage slot mismatch");
    }

    // ---- ens ----

    function test_ENSResolverStorageSlot() public pure {
        assertEq(
            ENS_RESOLVER_STORAGE_SLOT, _erc7201Slot("lattice.storage.ENSResolver"), "ENSResolver storage slot mismatch"
        );
    }

    function test_ENSSubnameIssuerStorageSlot() public pure {
        assertEq(
            ENS_SUBNAME_ISSUER_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.ENSSubnameIssuer"),
            "ENSSubnameIssuer storage slot mismatch"
        );
    }

    function test_ENSReverseClaimerStorageSlot() public pure {
        assertEq(
            ENS_REVERSE_CLAIMER_STORAGE_SLOT,
            _erc7201Slot("lattice.storage.ENSReverseClaimer"),
            "ENSReverseClaimer storage slot mismatch"
        );
    }

    // ======================== ERC-165 Map Slots ========================

    function test_Erc165StorageLocation() public pure {
        assertEq(
            ERC165_STORAGE_LOCATION, _erc7201Slot("diamond.lib.storage.ERC165"), "ERC165 storage location mismatch"
        );
    }

    // ---- access ----

    function test_Erc165MapIAccessControlSlot() public pure {
        assertEq(
            ERC165_MAP_IACCESSCONTROL_SLOT,
            _erc165MapSlot(type(IAccessControl).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IAccessControl map slot mismatch"
        );
    }

    function test_Erc165MapIAccessControlEnumerableSlot() public pure {
        bytes4 interfaceId = type(IAccessControlEnumerable).interfaceId;
        assertEq(interfaceId, bytes4(0xf92172dc), "IAccessControlEnumerable interfaceId comment is stale");
        assertEq(
            ERC165_MAP_IACCESSCONTROLENUMERABLE_SLOT,
            _erc165MapSlot(interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IAccessControlEnumerable map slot mismatch"
        );
    }

    function test_Erc165MapIAccessControlTimedSlot() public pure {
        assertEq(
            ERC165_MAP_IACCESSCONTROLTIMED_SLOT,
            _erc165MapSlot(type(IAccessControlTimed).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IAccessControlTimed map slot mismatch"
        );
    }

    function test_Erc165MapIAccessManagerSlot() public pure {
        assertEq(
            ERC165_MAP_IACCESSMANAGER_SLOT,
            _erc165MapSlot(type(IAccessManager).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IAccessManager map slot mismatch"
        );
    }

    function test_Erc165MapIAccessManagedSlot() public pure {
        assertEq(
            ERC165_MAP_IACCESSMANAGED_SLOT,
            _erc165MapSlot(type(IAccessManaged).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IAccessManaged map slot mismatch"
        );
    }

    // ---- tokens ----

    function test_Erc165MapIERC20Slot() public pure {
        assertEq(
            ERC165_MAP_IERC20_SLOT,
            _erc165MapSlot(type(IERC20).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IERC20 map slot mismatch"
        );
    }

    function test_Erc165MapIERC20CappedSlot() public pure {
        assertEq(
            ERC165_MAP_IERC20CAPPED_SLOT,
            _erc165MapSlot(type(IERC20Capped).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IERC20Capped map slot mismatch"
        );
    }

    function test_Erc165MapIERC721Slot() public pure {
        // Registered under the canonical EIP-721 id (0x80ac58cd), not the bundled Lattice interface id.
        assertEq(
            ERC165_MAP_IERC721_SLOT,
            _erc165MapSlot(IERC721_ID, ERC165_STORAGE_LOCATION),
            "ERC165 IERC721 map slot mismatch"
        );
    }

    function test_Erc165MapIERC721MetadataSlot() public pure {
        assertEq(
            ERC165_MAP_IERC721METADATA_SLOT,
            _erc165MapSlot(IERC721_METADATA_ID, ERC165_STORAGE_LOCATION),
            "ERC165 IERC721Metadata map slot mismatch"
        );
    }

    function test_Erc165MapErc4906Slot() public pure {
        assertEq(
            ERC165_MAP_ERC4906_SLOT,
            _erc165MapSlot(ERC4906_ID, ERC165_STORAGE_LOCATION),
            "ERC165 ERC-4906 map slot mismatch"
        );
    }

    function test_Erc165MapIERC1155Slot() public pure {
        // Registered under the canonical EIP-1155 id (0xd9b67a26), not the bundled Lattice interface id.
        assertEq(
            ERC165_MAP_IERC1155_SLOT,
            _erc165MapSlot(IERC1155_ID, ERC165_STORAGE_LOCATION),
            "ERC165 IERC1155 map slot mismatch"
        );
    }

    function test_Erc165MapIERC1155MetadataURISlot() public pure {
        assertEq(
            ERC165_MAP_IERC1155METADATAURI_SLOT,
            _erc165MapSlot(IERC1155_METADATA_URI_ID, ERC165_STORAGE_LOCATION),
            "ERC165 IERC1155MetadataURI map slot mismatch"
        );
    }

    function test_Erc165MapIERC2981Slot() public pure {
        assertEq(
            ERC165_MAP_IERC2981_SLOT,
            _erc165MapSlot(type(IERC2981).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IERC2981 map slot mismatch"
        );
    }

    function test_Erc165MapIERC4626Slot() public pure {
        assertEq(
            ERC165_MAP_IERC4626_SLOT,
            _erc165MapSlot(type(IERC4626).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IERC4626 map slot mismatch"
        );
    }

    // ---- governance ----

    function test_Erc165MapIVotesSlot() public pure {
        assertEq(
            ERC165_MAP_IVOTES_SLOT,
            _erc165MapSlot(type(IVotes).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IVotes map slot mismatch"
        );
    }

    function test_Erc165MapIGovernorSlot() public pure {
        assertEq(
            ERC165_MAP_IGOVERNOR_SLOT,
            _erc165MapSlot(type(IGovernor).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IGovernor map slot mismatch"
        );
    }

    function test_Erc165MapITimelockControllerSlot() public pure {
        assertEq(
            ERC165_MAP_ITIMELOCKCONTROLLER_SLOT,
            _erc165MapSlot(type(ITimelockController).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 ITimelockController map slot mismatch"
        );
    }

    function test_Erc165MapIGovernedSafeDiamondCutSlot() public pure {
        // GovernedSafeDiamondCut does NOT serve the canonical cut selector (every cut is delayed), so
        // its scheduling surface is a genuinely new interface minting its own ERC-165 map slot.
        bytes4 interfaceId = type(IGovernedSafeDiamondCut).interfaceId;
        assertEq(interfaceId, bytes4(0xacb1aeb6), "IGovernedSafeDiamondCut interfaceId comment is stale");
        assertEq(
            ERC165_MAP_IGOVERNEDSAFEDIAMONDCUT_SLOT,
            _erc165MapSlot(interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IGovernedSafeDiamondCut map slot mismatch"
        );
    }

    function test_Erc165MapISafeHarborAdopterSlot() public pure {
        bytes4 interfaceId = type(ISafeHarborAdopter).interfaceId;
        assertEq(interfaceId, bytes4(0x2a3e8e12), "ISafeHarborAdopter interfaceId comment is stale");
        assertEq(
            ERC165_MAP_ISAFEHARBORADOPTER_SLOT,
            _erc165MapSlot(interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 ISafeHarborAdopter map slot mismatch"
        );
    }

    // ---- defi ----

    function test_Erc165MapIVaultCoreSlot() public pure {
        assertEq(
            ERC165_MAP_IVAULTCORE_SLOT,
            _erc165MapSlot(type(IVaultCore).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IVaultCore map slot mismatch"
        );
    }

    function test_Erc165MapIStrategyManagerSlot() public pure {
        assertEq(
            ERC165_MAP_ISTRATEGYMANAGER_SLOT,
            _erc165MapSlot(type(IStrategyManager).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IStrategyManager map slot mismatch"
        );
    }

    function test_Erc165MapIProtocolAdapterSlot() public pure {
        // Pin the interfaceId: the operator surface (setOperator/operator) is deliberately in the
        // separate IAdapterOperator interface so this id stays 0x8f7783e6 and the shared map slot
        // below is unaffected. (Errors/events added to IProtocolAdapter do not change the id.)
        assertEq(type(IProtocolAdapter).interfaceId, bytes4(0x8f7783e6), "IProtocolAdapter interfaceId moved");
        assertEq(
            ERC165_MAP_IPROTOCOLADAPTER_SLOT,
            _erc165MapSlot(type(IProtocolAdapter).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IProtocolAdapter map slot mismatch"
        );
    }

    function test_Erc165MapIAaveV3AdapterSlot() public pure {
        assertEq(
            ERC165_MAP_IAAVEV3ADAPTER_SLOT,
            _erc165MapSlot(type(IAaveV3Adapter).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IAaveV3Adapter map slot mismatch"
        );
    }

    function test_Erc165MapICompoundV3AdapterSlot() public pure {
        assertEq(
            ERC165_MAP_ICOMPOUNDV3ADAPTER_SLOT,
            _erc165MapSlot(type(ICompoundV3Adapter).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 ICompoundV3Adapter map slot mismatch"
        );
    }

    function test_Erc165MapIERC4626AdapterSlot() public pure {
        bytes4 interfaceId = type(IERC4626Adapter).interfaceId;
        assertEq(interfaceId, bytes4(0x6189942b), "IERC4626Adapter interfaceId comment is stale");
        assertEq(
            ERC165_MAP_IERC4626ADAPTER_SLOT,
            _erc165MapSlot(interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IERC4626Adapter map slot mismatch"
        );
    }

    function test_Erc165MapICurveStableSwapAdapterSlot() public pure {
        bytes4 interfaceId = type(ICurveStableSwapAdapter).interfaceId;
        assertEq(interfaceId, bytes4(0xfa38ccb7), "ICurveStableSwapAdapter interfaceId comment is stale");
        assertEq(
            ERC165_MAP_ICURVESTABLESWAPADAPTER_SLOT,
            _erc165MapSlot(interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 ICurveStableSwapAdapter map slot mismatch"
        );
    }

    function test_Erc165MapILidoAdapterSlot() public pure {
        bytes4 interfaceId = type(ILidoAdapter).interfaceId;
        assertEq(interfaceId, bytes4(0x83d0afd2), "ILidoAdapter interfaceId comment is stale");
        assertEq(
            ERC165_MAP_ILIDOADAPTER_SLOT,
            _erc165MapSlot(interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 ILidoAdapter map slot mismatch"
        );
    }

    function test_Erc165MapIUniswapV3AdapterSlot() public pure {
        bytes4 interfaceId = type(IUniswapV3Adapter).interfaceId;
        assertEq(interfaceId, bytes4(0xf723aa17), "IUniswapV3Adapter interfaceId comment is stale");
        assertEq(
            ERC165_MAP_IUNISWAPV3ADAPTER_SLOT,
            _erc165MapSlot(interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IUniswapV3Adapter map slot mismatch"
        );
    }

    // ---- amm ----

    function test_Erc165MapIConstantProductSlot() public pure {
        assertEq(
            ERC165_MAP_ICONSTANTPRODUCT_SLOT,
            _erc165MapSlot(type(IConstantProduct).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IConstantProduct map slot mismatch"
        );
    }

    // ---- oracles ----

    function test_Erc165MapIChainlinkAdapterSlot() public pure {
        assertEq(
            ERC165_MAP_ICHAINLINKADAPTER_SLOT,
            _erc165MapSlot(type(IChainlinkAdapter).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IChainlinkAdapter map slot mismatch"
        );
    }

    function test_Erc165MapIChainlinkVRFSlot() public pure {
        assertEq(
            ERC165_MAP_ICHAINLINKVRF_SLOT,
            _erc165MapSlot(type(IChainlinkVRF).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IChainlinkVRF map slot mismatch"
        );
    }

    function test_Erc165MapITWAPOracleSlot() public pure {
        assertEq(
            ERC165_MAP_ITWAPORACLE_SLOT,
            _erc165MapSlot(type(ITWAPOracle).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 ITWAPOracle map slot mismatch"
        );
    }

    // ---- security ----

    function test_Erc165MapIPausableSlot() public pure {
        assertEq(
            ERC165_MAP_IPAUSABLE_SLOT,
            _erc165MapSlot(type(IPausable).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IPausable map slot mismatch"
        );
    }

    function test_Erc165MapIReentrancyGuardSlot() public pure {
        // IReentrancyGuard has no functions (only an error), so its interfaceId is 0x00000000.
        bytes4 interfaceId = type(IReentrancyGuard).interfaceId;
        assertEq(interfaceId, bytes4(0x00000000), "IReentrancyGuard interfaceId comment is stale");
        assertEq(
            ERC165_MAP_IREENTRANCYGUARD_SLOT,
            _erc165MapSlot(interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IReentrancyGuard map slot mismatch"
        );
    }

    function test_Erc165MapIRateLimiterSlot() public pure {
        assertEq(
            ERC165_MAP_IRATELIMITER_SLOT,
            _erc165MapSlot(type(IRateLimiter).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IRateLimiter map slot mismatch"
        );
    }

    function test_Erc165MapICircuitBreakerSlot() public pure {
        assertEq(
            ERC165_MAP_ICIRCUITBREAKER_SLOT,
            _erc165MapSlot(type(ICircuitBreaker).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 ICircuitBreaker map slot mismatch"
        );
    }

    function test_Erc165MapIEmergencyStopSlot() public pure {
        assertEq(
            ERC165_MAP_IEMERGENCYSTOP_SLOT,
            _erc165MapSlot(type(IEmergencyStop).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IEmergencyStop map slot mismatch"
        );
    }

    function test_Erc165MapIInvariantCheckerSlot() public pure {
        assertEq(
            ERC165_MAP_IINVARIANTCHECKER_SLOT,
            _erc165MapSlot(type(IInvariantChecker).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IInvariantChecker map slot mismatch"
        );
    }

    // ---- utils ----

    function test_Erc165MapIEIP712Slot() public pure {
        assertEq(
            ERC165_MAP_IEIP712_SLOT,
            _erc165MapSlot(type(IEIP712).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IEIP712 map slot mismatch"
        );
    }

    function test_Erc165MapINoncesSlot() public pure {
        assertEq(
            ERC165_MAP_INONCES_SLOT,
            _erc165MapSlot(type(INonces).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 INonces map slot mismatch"
        );
    }

    function test_Erc165MapIVestingWalletSlot() public pure {
        assertEq(
            ERC165_MAP_IVESTINGWALLET_SLOT,
            _erc165MapSlot(type(IVestingWallet).interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IVestingWallet map slot mismatch"
        );
    }

    // ---- privacy ----

    function test_Erc165MapIERC5564AnnouncerSlot() public pure {
        bytes4 interfaceId = type(IERC5564Announcer).interfaceId;
        assertEq(interfaceId, bytes4(0x4d1f9583), "IERC5564Announcer interfaceId comment is stale");
        assertEq(
            ERC165_MAP_IERC5564ANNOUNCER_SLOT,
            _erc165MapSlot(interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IERC5564Announcer map slot mismatch"
        );
    }

    function test_Erc165MapIERC6538RegistrySlot() public pure {
        bytes4 interfaceId = type(IERC6538Registry).interfaceId;
        assertEq(interfaceId, bytes4(0x7b1f57cb), "IERC6538Registry interfaceId comment is stale");
        assertEq(
            ERC165_MAP_IERC6538REGISTRY_SLOT,
            _erc165MapSlot(interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IERC6538Registry map slot mismatch"
        );
    }

    function test_Erc165MapICommitRevealSlot() public pure {
        bytes4 interfaceId = type(ICommitReveal).interfaceId;
        assertEq(interfaceId, bytes4(0xe371e8b7), "ICommitReveal interfaceId comment is stale");
        assertEq(
            ERC165_MAP_ICOMMITREVEAL_SLOT,
            _erc165MapSlot(interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 ICommitReveal map slot mismatch"
        );
    }

    function test_Erc165MapIGroth16VerifierSlot() public pure {
        bytes4 interfaceId = type(IGroth16Verifier).interfaceId;
        assertEq(interfaceId, bytes4(0x6d832d8e), "IGroth16Verifier interfaceId comment is stale");
        assertEq(
            ERC165_MAP_IGROTH16VERIFIER_SLOT,
            _erc165MapSlot(interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IGroth16Verifier map slot mismatch"
        );
    }

    function test_Erc165MapIPlonkVerifierSlot() public pure {
        bytes4 interfaceId = type(IPlonkVerifier).interfaceId;
        assertEq(interfaceId, bytes4(0x5d484314), "IPlonkVerifier interfaceId comment is stale");
        assertEq(
            ERC165_MAP_IPLONKVERIFIER_SLOT,
            _erc165MapSlot(interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IPlonkVerifier map slot mismatch"
        );
    }

    function test_Erc165MapISemaphoreSlot() public pure {
        bytes4 interfaceId = type(ISemaphore).interfaceId;
        assertEq(interfaceId, bytes4(0xf497879d), "ISemaphore interfaceId comment is stale");
        assertEq(
            ERC165_MAP_ISEMAPHORE_SLOT,
            _erc165MapSlot(interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 ISemaphore map slot mismatch"
        );
    }

    function test_Erc165MapIENSResolverSlot() public pure {
        bytes4 interfaceId = type(IENSResolver).interfaceId;
        assertEq(interfaceId, bytes4(0x566ec67d), "IENSResolver interfaceId comment is stale");
        assertEq(
            ERC165_MAP_IENSRESOLVER_SLOT,
            _erc165MapSlot(interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IENSResolver map slot mismatch"
        );
    }

    function test_Erc165MapIENSSubnameIssuerSlot() public pure {
        bytes4 interfaceId = type(IENSSubnameIssuer).interfaceId;
        assertEq(interfaceId, bytes4(0x6ead39e3), "IENSSubnameIssuer interfaceId comment is stale");
        assertEq(
            ERC165_MAP_IENSSUBNAMEISSUER_SLOT,
            _erc165MapSlot(interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IENSSubnameIssuer map slot mismatch"
        );
    }

    function test_Erc165MapIENSReverseClaimerSlot() public pure {
        bytes4 interfaceId = type(IENSReverseClaimer).interfaceId;
        assertEq(interfaceId, bytes4(0x84019dd8), "IENSReverseClaimer interfaceId comment is stale");
        assertEq(
            ERC165_MAP_IENSREVERSECLAIMER_SLOT,
            _erc165MapSlot(interfaceId, ERC165_STORAGE_LOCATION),
            "ERC165 IENSReverseClaimer map slot mismatch"
        );
    }

    // ======================== Uniqueness Checks ========================

    /// @notice Every module's ERC-7201 storage slot must be globally unique so modules can be
    ///         composed into one Diamond proxy without storage collisions.
    function test_AllErc7201SlotsAreUnique() public pure {
        bytes32[] memory slots = _allStorageSlots();
        for (uint256 i; i < slots.length; ++i) {
            for (uint256 j = i + 1; j < slots.length; ++j) {
                assertTrue(slots[i] != slots[j], "Duplicate ERC-7201 storage slot detected");
            }
        }
    }

    /// @notice Every ERC-165 map slot must be globally unique so registering one interface never
    ///         clobbers another interface's support flag.
    function test_AllErc165MapSlotsAreUnique() public pure {
        bytes32[] memory slots = _allErc165MapSlots();
        for (uint256 i; i < slots.length; ++i) {
            for (uint256 j = i + 1; j < slots.length; ++j) {
                assertTrue(slots[i] != slots[j], "Duplicate ERC-165 map slot detected");
            }
        }
    }

    // ======================== Slot inventories ========================

    function _allStorageSlots() internal pure returns (bytes32[] memory slots) {
        slots = new bytes32[](46);
        uint256 i;
        // access
        slots[i++] = ACCESS_CONTROL_STORAGE_SLOT;
        slots[i++] = ACCESS_CONTROL_ENUMERABLE_STORAGE_SLOT;
        slots[i++] = ACCESS_CONTROL_TIMED_STORAGE_SLOT;
        slots[i++] = ACCESS_MANAGER_STORAGE_SLOT;
        slots[i++] = ACCESS_MANAGED_STORAGE_SLOT;
        // tokens
        slots[i++] = ERC20_STORAGE_SLOT;
        slots[i++] = ERC20CAPPED_STORAGE_SLOT;
        slots[i++] = ERC721_STORAGE_SLOT;
        slots[i++] = ERC721URISTORAGE_STORAGE_SLOT;
        slots[i++] = ERC1155_STORAGE_SLOT;
        slots[i++] = ERC2981_STORAGE_SLOT;
        slots[i++] = ERC4626_STORAGE_SLOT;
        // governance
        slots[i++] = VOTES_STORAGE_SLOT;
        slots[i++] = GOVERNOR_STORAGE_SLOT;
        slots[i++] = TIMELOCK_CONTROLLER_STORAGE_SLOT;
        slots[i++] = GOVERNED_DIAMOND_CUT_STORAGE_SLOT;
        slots[i++] = SAFE_DIAMOND_CUT_STORAGE_SLOT;
        slots[i++] = GOVERNED_SAFE_DIAMOND_CUT_STORAGE_SLOT;
        slots[i++] = SAFE_HARBOR_ADOPTER_STORAGE_SLOT;
        // defi
        slots[i++] = VAULT_CORE_STORAGE_SLOT;
        slots[i++] = STRATEGY_MANAGER_STORAGE_SLOT;
        slots[i++] = AAVE_V3_ADAPTER_STORAGE_SLOT;
        slots[i++] = COMPOUND_V3_ADAPTER_STORAGE_SLOT;
        slots[i++] = ERC4626_ADAPTER_STORAGE_SLOT;
        slots[i++] = CURVE_STABLE_SWAP_ADAPTER_STORAGE_SLOT;
        slots[i++] = LIDO_ADAPTER_STORAGE_SLOT;
        slots[i++] = UNISWAP_V3_ADAPTER_STORAGE_SLOT;
        // amm
        slots[i++] = CONSTANT_PRODUCT_STORAGE_SLOT;
        // oracles
        slots[i++] = CHAINLINK_ADAPTER_STORAGE_SLOT;
        slots[i++] = CHAINLINK_VRF_STORAGE_SLOT;
        slots[i++] = TWAP_ORACLE_STORAGE_SLOT;
        // security
        slots[i++] = PAUSABLE_STORAGE_SLOT;
        slots[i++] = REENTRANCY_GUARD_STORAGE_SLOT;
        slots[i++] = RATE_LIMITER_STORAGE_SLOT;
        slots[i++] = CIRCUIT_BREAKER_STORAGE_SLOT;
        slots[i++] = EMERGENCY_STOP_STORAGE_SLOT;
        slots[i++] = INVARIANT_CHECKER_STORAGE_SLOT;
        // utils
        slots[i++] = EIP712_STORAGE_SLOT;
        slots[i++] = NONCES_STORAGE_SLOT;
        slots[i++] = VESTING_WALLET_STORAGE_SLOT;
        // privacy (ERC5564Announcer is stateless — no ERC-7201 storage slot)
        slots[i++] = ERC6538REGISTRY_STORAGE_SLOT;
        slots[i++] = COMMIT_REVEAL_STORAGE_SLOT;
        slots[i++] = SEMAPHORE_STORAGE_SLOT;
        // ens
        slots[i++] = ENS_REVERSE_CLAIMER_STORAGE_SLOT;
        slots[i++] = ENS_RESOLVER_STORAGE_SLOT;
        slots[i++] = ENS_SUBNAME_ISSUER_STORAGE_SLOT;
    }

    function _allErc165MapSlots() internal pure returns (bytes32[] memory slots) {
        slots = new bytes32[](50);
        uint256 i;
        // access
        slots[i++] = ERC165_MAP_IACCESSCONTROL_SLOT;
        slots[i++] = ERC165_MAP_IACCESSCONTROLENUMERABLE_SLOT;
        slots[i++] = ERC165_MAP_IACCESSCONTROLTIMED_SLOT;
        slots[i++] = ERC165_MAP_IACCESSMANAGER_SLOT;
        slots[i++] = ERC165_MAP_IACCESSMANAGED_SLOT;
        // tokens
        slots[i++] = ERC165_MAP_IERC20_SLOT;
        slots[i++] = ERC165_MAP_IERC20CAPPED_SLOT;
        slots[i++] = ERC165_MAP_IERC721_SLOT;
        slots[i++] = ERC165_MAP_IERC721METADATA_SLOT;
        slots[i++] = ERC165_MAP_ERC4906_SLOT;
        slots[i++] = ERC165_MAP_IERC1155_SLOT;
        slots[i++] = ERC165_MAP_IERC1155METADATAURI_SLOT;
        slots[i++] = ERC165_MAP_IERC2981_SLOT;
        slots[i++] = ERC165_MAP_IERC4626_SLOT;
        // governance
        slots[i++] = ERC165_MAP_IVOTES_SLOT;
        slots[i++] = ERC165_MAP_IGOVERNOR_SLOT;
        slots[i++] = ERC165_MAP_ITIMELOCKCONTROLLER_SLOT;
        // GovernedSafeDiamondCut mints its own ERC-165 map slot (it does NOT serve the canonical cut
        // selector). SafeDiamondCut reuses IDiamondCut's 0x1f931c1c slot (already registered by
        // DiamondLib), so it adds an ERC-7201 slot but NO new ERC-165 map slot.
        slots[i++] = ERC165_MAP_IGOVERNEDSAFEDIAMONDCUT_SLOT;
        slots[i++] = ERC165_MAP_ISAFEHARBORADOPTER_SLOT;
        // defi
        slots[i++] = ERC165_MAP_IVAULTCORE_SLOT;
        slots[i++] = ERC165_MAP_ISTRATEGYMANAGER_SLOT;
        slots[i++] = ERC165_MAP_IPROTOCOLADAPTER_SLOT;
        slots[i++] = ERC165_MAP_IAAVEV3ADAPTER_SLOT;
        // CompoundV3Adapter reuses the shared ERC165_MAP_IPROTOCOLADAPTER_SLOT (already counted
        // above under AaveV3Adapter) and only adds its protocol-specific ICompoundV3Adapter slot.
        slots[i++] = ERC165_MAP_ICOMPOUNDV3ADAPTER_SLOT;
        // ERC4626Adapter likewise reuses the shared ERC165_MAP_IPROTOCOLADAPTER_SLOT and only adds
        // its protocol-specific IERC4626Adapter slot.
        slots[i++] = ERC165_MAP_IERC4626ADAPTER_SLOT;
        // CurveStableSwapAdapter likewise reuses the shared ERC165_MAP_IPROTOCOLADAPTER_SLOT and only
        // adds its protocol-specific ICurveStableSwapAdapter slot.
        slots[i++] = ERC165_MAP_ICURVESTABLESWAPADAPTER_SLOT;
        // LidoAdapter likewise reuses the shared ERC165_MAP_IPROTOCOLADAPTER_SLOT and only adds its
        // protocol-specific ILidoAdapter slot.
        slots[i++] = ERC165_MAP_ILIDOADAPTER_SLOT;
        // UniswapV3Adapter likewise reuses the shared ERC165_MAP_IPROTOCOLADAPTER_SLOT and only adds
        // its protocol-specific IUniswapV3Adapter slot.
        slots[i++] = ERC165_MAP_IUNISWAPV3ADAPTER_SLOT;
        // amm
        slots[i++] = ERC165_MAP_ICONSTANTPRODUCT_SLOT;
        // oracles
        slots[i++] = ERC165_MAP_ICHAINLINKADAPTER_SLOT;
        slots[i++] = ERC165_MAP_ICHAINLINKVRF_SLOT;
        slots[i++] = ERC165_MAP_ITWAPORACLE_SLOT;
        // security
        slots[i++] = ERC165_MAP_IPAUSABLE_SLOT;
        slots[i++] = ERC165_MAP_IREENTRANCYGUARD_SLOT;
        slots[i++] = ERC165_MAP_IRATELIMITER_SLOT;
        slots[i++] = ERC165_MAP_ICIRCUITBREAKER_SLOT;
        slots[i++] = ERC165_MAP_IEMERGENCYSTOP_SLOT;
        slots[i++] = ERC165_MAP_IINVARIANTCHECKER_SLOT;
        // utils
        slots[i++] = ERC165_MAP_IEIP712_SLOT;
        slots[i++] = ERC165_MAP_INONCES_SLOT;
        slots[i++] = ERC165_MAP_IVESTINGWALLET_SLOT;
        // privacy (ERC6538Registry reuses the shared EIP712 + Nonces storage but mints its own
        // ERC-165 id; ERC5564Announcer is stateless and likewise mints its own ERC-165 id)
        slots[i++] = ERC165_MAP_IERC5564ANNOUNCER_SLOT;
        slots[i++] = ERC165_MAP_IERC6538REGISTRY_SLOT;
        slots[i++] = ERC165_MAP_ICOMMITREVEAL_SLOT;
        slots[i++] = ERC165_MAP_IGROTH16VERIFIER_SLOT;
        slots[i++] = ERC165_MAP_IPLONKVERIFIER_SLOT;
        slots[i++] = ERC165_MAP_ISEMAPHORE_SLOT;
        // ens
        slots[i++] = ERC165_MAP_IENSREVERSECLAIMER_SLOT;
        slots[i++] = ERC165_MAP_IENSRESOLVER_SLOT;
        slots[i++] = ERC165_MAP_IENSSUBNAMEISSUER_SLOT;
    }
}

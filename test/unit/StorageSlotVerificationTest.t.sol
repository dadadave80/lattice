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
import {ERC165_MAP_IGOVERNOR_SLOT, GOVERNOR_STORAGE_SLOT} from "@lattice/governance/libraries/GovernorLib.sol";
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
    ERC165_MAP_ISTRATEGYMANAGER_SLOT,
    STRATEGY_MANAGER_STORAGE_SLOT
} from "@lattice/defi/libraries/StrategyManagerLib.sol";
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
import {IConstantProduct} from "@lattice/interfaces/IConstantProduct.sol";
import {IEIP712} from "@lattice/interfaces/IEIP712.sol";
import {IERC20} from "@lattice/interfaces/IERC20.sol";
import {IERC20Capped} from "@lattice/interfaces/IERC20Capped.sol";
import {IERC2981} from "@lattice/interfaces/IERC2981.sol";
import {IERC4626} from "@lattice/interfaces/IERC4626.sol";
import {IEmergencyStop} from "@lattice/interfaces/IEmergencyStop.sol";
import {IGovernor} from "@lattice/interfaces/IGovernor.sol";
import {IInvariantChecker} from "@lattice/interfaces/IInvariantChecker.sol";
import {INonces} from "@lattice/interfaces/INonces.sol";
import {IPausable} from "@lattice/interfaces/IPausable.sol";
import {IProtocolAdapter} from "@lattice/interfaces/IProtocolAdapter.sol";
import {IRateLimiter} from "@lattice/interfaces/IRateLimiter.sol";
import {IReentrancyGuard} from "@lattice/interfaces/IReentrancyGuard.sol";
import {IStrategyManager} from "@lattice/interfaces/IStrategyManager.sol";
import {ITWAPOracle} from "@lattice/interfaces/ITWAPOracle.sol";
import {ITimelockController} from "@lattice/interfaces/ITimelockController.sol";
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
        slots = new bytes32[](32);
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
        // defi
        slots[i++] = VAULT_CORE_STORAGE_SLOT;
        slots[i++] = STRATEGY_MANAGER_STORAGE_SLOT;
        slots[i++] = AAVE_V3_ADAPTER_STORAGE_SLOT;
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
    }

    function _allErc165MapSlots() internal pure returns (bytes32[] memory slots) {
        slots = new bytes32[](34);
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
        // defi
        slots[i++] = ERC165_MAP_IVAULTCORE_SLOT;
        slots[i++] = ERC165_MAP_ISTRATEGYMANAGER_SLOT;
        slots[i++] = ERC165_MAP_IPROTOCOLADAPTER_SLOT;
        slots[i++] = ERC165_MAP_IAAVEV3ADAPTER_SLOT;
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
    }
}

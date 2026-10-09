// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlEnumerableStorage} from "@lattice/access/libraries/AccessControlEnumerableLib.sol";
import {AccessControlStorage} from "@lattice/access/libraries/AccessControlLib.sol";
import {AccessControlTimedStorage} from "@lattice/access/libraries/AccessControlTimedLib.sol";
import {AccessManagedStorage} from "@lattice/access/libraries/AccessManagedLib.sol";
import {AccessManagerStorage} from "@lattice/access/libraries/AccessManagerLib.sol";
import {ERC6900ModuleManagerStorage} from "@lattice/accounts/erc6900/libraries/ERC6900ModuleManagerLib.sol";
import {ERC7579ModuleConfigStorage} from "@lattice/accounts/erc7579/libraries/ERC7579ModuleConfigLib.sol";
import {AccountSignerStorage} from "@lattice/accounts/libraries/AccountSignerLib.sol";
import {ERC4337ValidationStorage} from "@lattice/accounts/libraries/ERC4337ValidationLib.sol";
import {ERC6551AccountStorage} from "@lattice/accounts/libraries/ERC6551AccountLib.sol";
import {SessionKeyStorage} from "@lattice/accounts/libraries/SessionKeyLib.sol";
import {ConstantProductStorage} from "@lattice/amm/libraries/ConstantProductLib.sol";
import {AcrossBridgeAdapterStorage} from "@lattice/crosschain/across/AcrossBridgeAdapterLib.sol";
import {AxelarGatewayAdapterStorage} from "@lattice/crosschain/axelar/AxelarGatewayAdapterLib.sol";
import {CCIPGatewayAdapterStorage} from "@lattice/crosschain/chainlink/CCIPGatewayAdapterLib.sol";
import {CCTPBridgeAdapterStorage} from "@lattice/crosschain/circle/CCTPBridgeAdapterLib.sol";
import {HyperbridgeGatewayAdapterStorage} from "@lattice/crosschain/hyperbridge/HyperbridgeGatewayAdapterLib.sol";
import {HyperlaneGatewayAdapterStorage} from "@lattice/crosschain/hyperlane/HyperlaneGatewayAdapterLib.sol";
import {LayerZeroGatewayAdapterStorage} from "@lattice/crosschain/layerzero/LayerZeroGatewayAdapterLib.sol";
import {StargateBridgeAdapterStorage} from "@lattice/crosschain/layerzero/StargateBridgeAdapterLib.sol";
import {BridgeERC20Storage} from "@lattice/crosschain/libraries/BridgeERC20Lib.sol";
import {BridgeERC7802Storage} from "@lattice/crosschain/libraries/BridgeERC7802Lib.sol";
import {ChainRegistryStorage} from "@lattice/crosschain/libraries/ChainRegistryLib.sol";
import {CrosschainLinkStorage} from "@lattice/crosschain/libraries/CrosschainLinkLib.sol";
import {ERC7786OpenBridgeStorage} from "@lattice/crosschain/libraries/ERC7786OpenBridgeLib.sol";
import {
    L1ToL2CrossDomainMessengerGatewayAdapterStorage
} from "@lattice/crosschain/optimism/L1ToL2CrossDomainMessengerGatewayAdapterLib.sol";
import {
    L2ToL2CrossDomainMessengerGatewayAdapterStorage
} from "@lattice/crosschain/optimism/L2ToL2CrossDomainMessengerGatewayAdapterLib.sol";
import {StarknetGatewayAdapterStorage} from "@lattice/crosschain/starknet/StarknetGatewayAdapterLib.sol";
import {WormholeGatewayAdapterStorage} from "@lattice/crosschain/wormhole/WormholeGatewayAdapterLib.sol";
import {ZetaChainGatewayAdapterStorage} from "@lattice/crosschain/zetachain/ZetaChainGatewayAdapterLib.sol";
import {AaveV3AdapterStorage} from "@lattice/defi/libraries/AaveV3AdapterLib.sol";
import {AggregatorExecAdapterStorage} from "@lattice/defi/libraries/AggregatorExecAdapterLib.sol";
import {CompoundV3AdapterStorage} from "@lattice/defi/libraries/CompoundV3AdapterLib.sol";
import {CurveStableSwapAdapterStorage} from "@lattice/defi/libraries/CurveStableSwapAdapterLib.sol";
import {ERC4626AdapterStorage} from "@lattice/defi/libraries/ERC4626AdapterLib.sol";
import {GovernedVaultStorage} from "@lattice/defi/libraries/GovernedVaultLib.sol";
import {LidoAdapterStorage} from "@lattice/defi/libraries/LidoAdapterLib.sol";
import {StrategyManagerStorage} from "@lattice/defi/libraries/StrategyManagerLib.sol";
import {UniswapV3AdapterStorage} from "@lattice/defi/libraries/UniswapV3AdapterLib.sol";
import {VaultCoreRecoveryStorage, VaultCoreStorage} from "@lattice/defi/libraries/VaultCoreLib.sol";
import {ENSResolverStorage} from "@lattice/ens/libraries/ENSResolverLib.sol";
import {ENSReverseClaimerStorage} from "@lattice/ens/libraries/ENSReverseClaimerLib.sol";
import {ENSSubnameIssuerStorage} from "@lattice/ens/libraries/ENSSubnameIssuerLib.sol";
import {GovernedDiamondCutStorage} from "@lattice/governance/libraries/GovernedDiamondCutLib.sol";
import {GovernedSafeDiamondCutStorage} from "@lattice/governance/libraries/GovernedSafeDiamondCutLib.sol";
import {GovernorStorage} from "@lattice/governance/libraries/GovernorLib.sol";
import {SafeDiamondCutStorage} from "@lattice/governance/libraries/SafeDiamondCutLib.sol";
import {SafeHarborAdopterStorage} from "@lattice/governance/libraries/SafeHarborAdopterLib.sol";
import {TimelockControllerStorage} from "@lattice/governance/libraries/TimelockControllerLib.sol";
import {VotesStorage} from "@lattice/governance/libraries/VotesLib.sol";
import {API3AdapterStorage} from "@lattice/oracles/api3/API3AdapterLib.sol";
import {API3QRNGAdapterStorage} from "@lattice/oracles/api3/API3QRNGAdapterLib.sol";
import {BandAdapterStorage} from "@lattice/oracles/band/BandAdapterLib.sol";
import {ChainlinkAdapterStorage} from "@lattice/oracles/chainlink/ChainlinkAdapterLib.sol";
import {ChainlinkAutomationAdapterStorage} from "@lattice/oracles/chainlink/ChainlinkAutomationAdapterLib.sol";
import {ChainlinkCREAdapterStorage} from "@lattice/oracles/chainlink/ChainlinkCREAdapterLib.sol";
import {ChainlinkVRFStorage} from "@lattice/oracles/chainlink/ChainlinkVRFLib.sol";
import {ChronicleAdapterStorage} from "@lattice/oracles/chronicle/ChronicleAdapterLib.sol";
import {DIAAdapterStorage} from "@lattice/oracles/dia/DIAAdapterLib.sol";
import {GelatoAutomateAdapterStorage} from "@lattice/oracles/gelato/GelatoAutomateAdapterLib.sol";
import {GelatoVRFAdapterStorage} from "@lattice/oracles/gelato/GelatoVRFAdapterLib.sol";
import {HSSAdapterStorage} from "@lattice/oracles/hedera/HSSAdapterLib.sol";
import {OracleGuardStorage} from "@lattice/oracles/libraries/OracleGuardLib.sol";
import {PythAdapterStorage} from "@lattice/oracles/pyth/PythAdapterLib.sol";
import {PythEntropyAdapterStorage} from "@lattice/oracles/pyth/PythEntropyAdapterLib.sol";
import {RedStoneAdapterStorage} from "@lattice/oracles/redstone/RedStoneAdapterLib.sol";
import {TellorAdapterStorage} from "@lattice/oracles/tellor/TellorAdapterLib.sol";
import {TWAPOracleStorage} from "@lattice/oracles/uniswap/TWAPOracleLib.sol";
import {CommitRevealStorage} from "@lattice/privacy/libraries/CommitRevealLib.sol";
import {ERC6538RegistryStorage} from "@lattice/privacy/libraries/ERC6538RegistryLib.sol";
import {PrivateVotingStorage} from "@lattice/privacy/libraries/PrivateVotingLib.sol";
import {SemaphoreStorage} from "@lattice/privacy/libraries/SemaphoreLib.sol";
import {ShieldedPoolStorage} from "@lattice/privacy/libraries/ShieldedPoolLib.sol";
import {CircuitBreakerStorage} from "@lattice/security/libraries/CircuitBreakerLib.sol";
import {EmergencyStopStorage} from "@lattice/security/libraries/EmergencyStopLib.sol";
import {InvariantCheckerStorage} from "@lattice/security/libraries/InvariantCheckerLib.sol";
import {PausableStorage} from "@lattice/security/libraries/PausableLib.sol";
import {RateLimiterStorage} from "@lattice/security/libraries/RateLimiterLib.sol";
import {ERC1155Storage} from "@lattice/tokens/ERC1155/libraries/ERC1155Lib.sol";
import {ERC1155SupplyStorage} from "@lattice/tokens/ERC1155/libraries/ERC1155SupplyLib.sol";
import {ERC1155URIStorageStorage} from "@lattice/tokens/ERC1155/libraries/ERC1155URIStorageLib.sol";
import {ERC20CappedStorage} from "@lattice/tokens/ERC20/libraries/ERC20CappedLib.sol";
import {ERC20Storage} from "@lattice/tokens/ERC20/libraries/ERC20Lib.sol";
import {ERC20WrapperStorage} from "@lattice/tokens/ERC20/libraries/ERC20WrapperLib.sol";
import {ERC2981Storage} from "@lattice/tokens/ERC2981/libraries/ERC2981Lib.sol";
import {ERC4626Storage} from "@lattice/tokens/ERC4626/libraries/ERC4626Lib.sol";
import {ERC721ConsecutiveStorage} from "@lattice/tokens/ERC721/libraries/ERC721ConsecutiveLib.sol";
import {ERC721EnumerableStorage} from "@lattice/tokens/ERC721/libraries/ERC721EnumerableLib.sol";
import {ERC721Storage} from "@lattice/tokens/ERC721/libraries/ERC721Lib.sol";
import {ERC721URIStorageStorage} from "@lattice/tokens/ERC721/libraries/ERC721URIStorageLib.sol";
import {ERC721WrapperStorage} from "@lattice/tokens/ERC721/libraries/ERC721WrapperLib.sol";
import {HTSAdapterStorage} from "@lattice/tokens/hedera/HTSAdapterLib.sol";
import {MarketplaceZoneStorage} from "@lattice/tokens/libraries/MarketplaceZoneLib.sol";
import {EIP712Storage} from "@lattice/utils/libraries/EIP712Lib.sol";
import {NoncesStorage} from "@lattice/utils/libraries/NoncesLib.sol";
import {VestingWalletStorage} from "@lattice/utils/libraries/VestingWalletLib.sol";

/// @title StorageLayoutProbe
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Compile-only harness that declares every ERC-7201 storage struct in `src/` as a contract state
///         variable, so `forge inspect StorageLayoutProbe storageLayout` emits each struct's field-by-field
///         layout for the append-only check in `script/upgrades/check-storage-layout.sh`.
/// @dev A module's storage struct is only reached through an `assembly { $.slot := <CONST> }` cast, so solc
///      emits no layout for it. Declaring it here as state makes the layout inspectable. The structs are
///      IMPORTED from their libraries, never copied, so the checked layout is always the real one. The
///      contract is never deployed.
///
///      The check script derives the guarded list from every `@custom:storage-location erc7201:` annotation
///      in `src/`. A struct missing from this probe fails the check, so a new module's struct must be
///      imported and declared here.
contract StorageLayoutProbe {
    API3AdapterStorage internal _aPI3AdapterStorage;
    API3QRNGAdapterStorage internal _aPI3QRNGAdapterStorage;
    AaveV3AdapterStorage internal _aaveV3AdapterStorage;
    AccessControlEnumerableStorage internal _accessControlEnumerableStorage;
    AccessControlStorage internal _accessControlStorage;
    AccessControlTimedStorage internal _accessControlTimedStorage;
    AccessManagedStorage internal _accessManagedStorage;
    AccessManagerStorage internal _accessManagerStorage;
    AccountSignerStorage internal _accountSignerStorage;
    AcrossBridgeAdapterStorage internal _acrossBridgeAdapterStorage;
    AggregatorExecAdapterStorage internal _aggregatorExecAdapterStorage;
    AxelarGatewayAdapterStorage internal _axelarGatewayAdapterStorage;
    BandAdapterStorage internal _bandAdapterStorage;
    BridgeERC20Storage internal _bridgeERC20Storage;
    BridgeERC7802Storage internal _bridgeERC7802Storage;
    CCIPGatewayAdapterStorage internal _cCIPGatewayAdapterStorage;
    CCTPBridgeAdapterStorage internal _cCTPBridgeAdapterStorage;
    ChainRegistryStorage internal _chainRegistryStorage;
    ChainlinkAdapterStorage internal _chainlinkAdapterStorage;
    ChainlinkAutomationAdapterStorage internal _chainlinkAutomationAdapterStorage;
    ChainlinkCREAdapterStorage internal _chainlinkCREAdapterStorage;
    ChainlinkVRFStorage internal _chainlinkVRFStorage;
    ChronicleAdapterStorage internal _chronicleAdapterStorage;
    CircuitBreakerStorage internal _circuitBreakerStorage;
    CommitRevealStorage internal _commitRevealStorage;
    CompoundV3AdapterStorage internal _compoundV3AdapterStorage;
    ConstantProductStorage internal _constantProductStorage;
    CrosschainLinkStorage internal _crosschainLinkStorage;
    CurveStableSwapAdapterStorage internal _curveStableSwapAdapterStorage;
    DIAAdapterStorage internal _dIAAdapterStorage;
    EIP712Storage internal _eIP712Storage;
    ENSResolverStorage internal _eNSResolverStorage;
    ENSReverseClaimerStorage internal _eNSReverseClaimerStorage;
    ENSSubnameIssuerStorage internal _eNSSubnameIssuerStorage;
    ERC1155Storage internal _eRC1155Storage;
    ERC1155SupplyStorage internal _eRC1155SupplyStorage;
    ERC1155URIStorageStorage internal _eRC1155URIStorageStorage;
    ERC20CappedStorage internal _eRC20CappedStorage;
    ERC20Storage internal _eRC20Storage;
    ERC20WrapperStorage internal _eRC20WrapperStorage;
    ERC2981Storage internal _eRC2981Storage;
    ERC4337ValidationStorage internal _eRC4337ValidationStorage;
    ERC4626AdapterStorage internal _eRC4626AdapterStorage;
    ERC4626Storage internal _eRC4626Storage;
    ERC6538RegistryStorage internal _eRC6538RegistryStorage;
    ERC6551AccountStorage internal _eRC6551AccountStorage;
    ERC6900ModuleManagerStorage internal _eRC6900ModuleManagerStorage;
    ERC721Storage internal _eRC721Storage;
    ERC721ConsecutiveStorage internal _eRC721ConsecutiveStorage;
    ERC721EnumerableStorage internal _eRC721EnumerableStorage;
    ERC721URIStorageStorage internal _eRC721URIStorageStorage;
    ERC721WrapperStorage internal _eRC721WrapperStorage;
    ERC7579ModuleConfigStorage internal _eRC7579ModuleConfigStorage;
    ERC7786OpenBridgeStorage internal _eRC7786OpenBridgeStorage;
    EmergencyStopStorage internal _emergencyStopStorage;
    GelatoAutomateAdapterStorage internal _gelatoAutomateAdapterStorage;
    GelatoVRFAdapterStorage internal _gelatoVRFAdapterStorage;
    GovernedDiamondCutStorage internal _governedDiamondCutStorage;
    GovernedSafeDiamondCutStorage internal _governedSafeDiamondCutStorage;
    GovernedVaultStorage internal _governedVaultStorage;
    GovernorStorage internal _governorStorage;
    HSSAdapterStorage internal _hSSAdapterStorage;
    HTSAdapterStorage internal _hTSAdapterStorage;
    HyperbridgeGatewayAdapterStorage internal _hyperbridgeGatewayAdapterStorage;
    HyperlaneGatewayAdapterStorage internal _hyperlaneGatewayAdapterStorage;
    InvariantCheckerStorage internal _invariantCheckerStorage;
    L1ToL2CrossDomainMessengerGatewayAdapterStorage internal _l1ToL2CrossDomainMessengerGatewayAdapterStorage;
    L2ToL2CrossDomainMessengerGatewayAdapterStorage internal _l2ToL2CrossDomainMessengerGatewayAdapterStorage;
    LayerZeroGatewayAdapterStorage internal _layerZeroGatewayAdapterStorage;
    LidoAdapterStorage internal _lidoAdapterStorage;
    MarketplaceZoneStorage internal _marketplaceZoneStorage;
    NoncesStorage internal _noncesStorage;
    OracleGuardStorage internal _oracleGuardStorage;
    PausableStorage internal _pausableStorage;
    PrivateVotingStorage internal _privateVotingStorage;
    PythAdapterStorage internal _pythAdapterStorage;
    PythEntropyAdapterStorage internal _pythEntropyAdapterStorage;
    RateLimiterStorage internal _rateLimiterStorage;
    RedStoneAdapterStorage internal _redStoneAdapterStorage;
    SafeDiamondCutStorage internal _safeDiamondCutStorage;
    SafeHarborAdopterStorage internal _safeHarborAdopterStorage;
    SemaphoreStorage internal _semaphoreStorage;
    SessionKeyStorage internal _sessionKeyStorage;
    ShieldedPoolStorage internal _shieldedPoolStorage;
    StargateBridgeAdapterStorage internal _stargateBridgeAdapterStorage;
    StarknetGatewayAdapterStorage internal _starknetGatewayAdapterStorage;
    StrategyManagerStorage internal _strategyManagerStorage;
    TWAPOracleStorage internal _tWAPOracleStorage;
    TellorAdapterStorage internal _tellorAdapterStorage;
    TimelockControllerStorage internal _timelockControllerStorage;
    UniswapV3AdapterStorage internal _uniswapV3AdapterStorage;
    VaultCoreRecoveryStorage internal _vaultCoreRecoveryStorage;
    VaultCoreStorage internal _vaultCoreStorage;
    VestingWalletStorage internal _vestingWalletStorage;
    VotesStorage internal _votesStorage;
    WormholeGatewayAdapterStorage internal _wormholeGatewayAdapterStorage;
    ZetaChainGatewayAdapterStorage internal _zetaChainGatewayAdapterStorage;
}

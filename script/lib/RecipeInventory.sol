// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// Deliberate artifact dependencies: native offline collection resolves every canonical recipe by FQN.
import {DeployAccessControl} from "@lattice-script/base/access/DeployAccessControl.s.sol";
import {DeployAccessControlEnumerable} from "@lattice-script/base/access/DeployAccessControlEnumerable.s.sol";
import {DeployAccessControlTimed} from "@lattice-script/base/access/DeployAccessControlTimed.s.sol";
import {DeployAccessManaged} from "@lattice-script/base/access/DeployAccessManaged.s.sol";
import {DeployAccessManager} from "@lattice-script/base/access/DeployAccessManager.s.sol";
import {DeployAccount} from "@lattice-script/base/accounts/DeployAccount.s.sol";
import {DeployAccount6900} from "@lattice-script/base/accounts/DeployAccount6900.s.sol";
import {DeployConstantProduct} from "@lattice-script/base/amm/DeployConstantProduct.s.sol";
import {DeployAcrossBridgeAdapter} from "@lattice-script/base/crosschain/DeployAcrossBridgeAdapter.s.sol";
import {DeployAxelarGatewayAdapter} from "@lattice-script/base/crosschain/DeployAxelarGatewayAdapter.s.sol";
import {DeployBridgeERC20} from "@lattice-script/base/crosschain/DeployBridgeERC20.s.sol";
import {DeployBridgeERC7802} from "@lattice-script/base/crosschain/DeployBridgeERC7802.s.sol";
import {DeployCCIPGatewayAdapter} from "@lattice-script/base/crosschain/DeployCCIPGatewayAdapter.s.sol";
import {DeployCCTPBridgeAdapter} from "@lattice-script/base/crosschain/DeployCCTPBridgeAdapter.s.sol";
import {DeployChainRegistry} from "@lattice-script/base/crosschain/DeployChainRegistry.s.sol";
import {DeployCrosschainLink} from "@lattice-script/base/crosschain/DeployCrosschainLink.s.sol";
import {DeployCrosschainTimelockHandler} from "@lattice-script/base/crosschain/DeployCrosschainTimelockHandler.s.sol";
import {DeployERC7786OpenBridge} from "@lattice-script/base/crosschain/DeployERC7786OpenBridge.s.sol";
import {DeployHyperbridgeGatewayAdapter} from "@lattice-script/base/crosschain/DeployHyperbridgeGatewayAdapter.s.sol";
import {DeployHyperlaneGatewayAdapter} from "@lattice-script/base/crosschain/DeployHyperlaneGatewayAdapter.s.sol";
import {
    DeployL1ToL2CrossDomainMessengerGatewayAdapter
} from "@lattice-script/base/crosschain/DeployL1ToL2CrossDomainMessengerGatewayAdapter.s.sol";
import {
    DeployL2ToL2CrossDomainMessengerGatewayAdapter
} from "@lattice-script/base/crosschain/DeployL2ToL2CrossDomainMessengerGatewayAdapter.s.sol";
import {DeployLayerZeroGatewayAdapter} from "@lattice-script/base/crosschain/DeployLayerZeroGatewayAdapter.s.sol";
import {DeployStargateBridgeAdapter} from "@lattice-script/base/crosschain/DeployStargateBridgeAdapter.s.sol";
import {DeployStarknetGatewayAdapter} from "@lattice-script/base/crosschain/DeployStarknetGatewayAdapter.s.sol";
import {DeploySuperchainETHBridgeAdapter} from "@lattice-script/base/crosschain/DeploySuperchainETHBridgeAdapter.s.sol";
import {DeployWormholeGatewayAdapter} from "@lattice-script/base/crosschain/DeployWormholeGatewayAdapter.s.sol";
import {DeployZetaChainGatewayAdapter} from "@lattice-script/base/crosschain/DeployZetaChainGatewayAdapter.s.sol";
import {DeployAggregatorExecAdapter} from "@lattice-script/base/defi/DeployAggregatorExecAdapter.s.sol";
import {DeployGovernedVault} from "@lattice-script/base/defi/DeployGovernedVault.s.sol";
import {DeployGovernedVaultENS} from "@lattice-script/base/defi/DeployGovernedVaultENS.s.sol";
import {DeployStrategyManager} from "@lattice-script/base/defi/DeployStrategyManager.s.sol";
import {DeployVaultCore} from "@lattice-script/base/defi/DeployVaultCore.s.sol";
import {DeployENSResolver} from "@lattice-script/base/ens/DeployENSResolver.s.sol";
import {DeployENSReverseClaimer} from "@lattice-script/base/ens/DeployENSReverseClaimer.s.sol";
import {DeployENSSubnameIssuer} from "@lattice-script/base/ens/DeployENSSubnameIssuer.s.sol";
import {DeployGovernedDiamondCut} from "@lattice-script/base/governance/DeployGovernedDiamondCut.s.sol";
import {DeployGovernedSafeDiamondCut} from "@lattice-script/base/governance/DeployGovernedSafeDiamondCut.s.sol";
import {DeploySafeDiamondCut} from "@lattice-script/base/governance/DeploySafeDiamondCut.s.sol";
import {DeploySafeHarborAdopter} from "@lattice-script/base/governance/DeploySafeHarborAdopter.s.sol";
import {DeployAPI3Adapter} from "@lattice-script/base/oracles/DeployAPI3Adapter.s.sol";
import {DeployAPI3QRNGAdapter} from "@lattice-script/base/oracles/DeployAPI3QRNGAdapter.s.sol";
import {DeployBandAdapter} from "@lattice-script/base/oracles/DeployBandAdapter.s.sol";
import {DeployChainlinkAdapter} from "@lattice-script/base/oracles/DeployChainlinkAdapter.s.sol";
import {DeployChainlinkAutomationAdapter} from "@lattice-script/base/oracles/DeployChainlinkAutomationAdapter.s.sol";
import {DeployChainlinkCREAdapter} from "@lattice-script/base/oracles/DeployChainlinkCREAdapter.s.sol";
import {DeployChainlinkVRF} from "@lattice-script/base/oracles/DeployChainlinkVRF.s.sol";
import {DeployChronicleAdapter} from "@lattice-script/base/oracles/DeployChronicleAdapter.s.sol";
import {DeployDIAAdapter} from "@lattice-script/base/oracles/DeployDIAAdapter.s.sol";
import {DeployGelatoAutomateAdapter} from "@lattice-script/base/oracles/DeployGelatoAutomateAdapter.s.sol";
import {DeployGelatoVRFAdapter} from "@lattice-script/base/oracles/DeployGelatoVRFAdapter.s.sol";
import {DeployHSSAdapter} from "@lattice-script/base/oracles/DeployHSSAdapter.s.sol";
import {DeployOracleGuard} from "@lattice-script/base/oracles/DeployOracleGuard.s.sol";
import {DeployPythAdapter} from "@lattice-script/base/oracles/DeployPythAdapter.s.sol";
import {DeployPythEntropyAdapter} from "@lattice-script/base/oracles/DeployPythEntropyAdapter.s.sol";
import {DeployRedStoneAdapter} from "@lattice-script/base/oracles/DeployRedStoneAdapter.s.sol";
import {DeployTWAPOracle} from "@lattice-script/base/oracles/DeployTWAPOracle.s.sol";
import {DeployTellorAdapter} from "@lattice-script/base/oracles/DeployTellorAdapter.s.sol";
import {DeployCommitReveal} from "@lattice-script/base/privacy/DeployCommitReveal.s.sol";
import {DeployERC5564Announcer} from "@lattice-script/base/privacy/DeployERC5564Announcer.s.sol";
import {DeployERC6538Registry} from "@lattice-script/base/privacy/DeployERC6538Registry.s.sol";
import {DeployGroth16Verifier} from "@lattice-script/base/privacy/DeployGroth16Verifier.s.sol";
import {DeployPlonkVerifier} from "@lattice-script/base/privacy/DeployPlonkVerifier.s.sol";
import {DeployPrivateVoting} from "@lattice-script/base/privacy/DeployPrivateVoting.s.sol";
import {DeploySemaphore} from "@lattice-script/base/privacy/DeploySemaphore.s.sol";
import {DeployShieldedPool} from "@lattice-script/base/privacy/DeployShieldedPool.s.sol";
import {DeployCircuitBreaker} from "@lattice-script/base/security/DeployCircuitBreaker.s.sol";
import {DeployEmergencyStop} from "@lattice-script/base/security/DeployEmergencyStop.s.sol";
import {DeployInvariantChecker} from "@lattice-script/base/security/DeployInvariantChecker.s.sol";
import {DeployPausable} from "@lattice-script/base/security/DeployPausable.s.sol";
import {DeployRateLimiter} from "@lattice-script/base/security/DeployRateLimiter.s.sol";
import {DeployERC1155} from "@lattice-script/base/tokens/DeployERC1155.s.sol";
import {DeployERC1155Burnable} from "@lattice-script/base/tokens/DeployERC1155Burnable.s.sol";
import {DeployERC1155Pausable} from "@lattice-script/base/tokens/DeployERC1155Pausable.s.sol";
import {DeployERC1155Supply} from "@lattice-script/base/tokens/DeployERC1155Supply.s.sol";
import {DeployERC1155URIStorage} from "@lattice-script/base/tokens/DeployERC1155URIStorage.s.sol";
import {DeployERC1363} from "@lattice-script/base/tokens/DeployERC1363.s.sol";
import {DeployERC20} from "@lattice-script/base/tokens/DeployERC20.s.sol";
import {DeployERC20Burnable} from "@lattice-script/base/tokens/DeployERC20Burnable.s.sol";
import {DeployERC20Capped} from "@lattice-script/base/tokens/DeployERC20Capped.s.sol";
import {DeployERC20Crosschain} from "@lattice-script/base/tokens/DeployERC20Crosschain.s.sol";
import {DeployERC20FlashMint} from "@lattice-script/base/tokens/DeployERC20FlashMint.s.sol";
import {DeployERC20Pausable} from "@lattice-script/base/tokens/DeployERC20Pausable.s.sol";
import {DeployERC20Permit} from "@lattice-script/base/tokens/DeployERC20Permit.s.sol";
import {DeployERC20TemporaryApproval} from "@lattice-script/base/tokens/DeployERC20TemporaryApproval.s.sol";
import {DeployERC20Votes} from "@lattice-script/base/tokens/DeployERC20Votes.s.sol";
import {DeployERC20Wrapper} from "@lattice-script/base/tokens/DeployERC20Wrapper.s.sol";
import {DeployERC2981} from "@lattice-script/base/tokens/DeployERC2981.s.sol";
import {DeployERC3643} from "@lattice-script/base/tokens/DeployERC3643.s.sol";
import {DeployERC4626} from "@lattice-script/base/tokens/DeployERC4626.s.sol";
import {DeployERC721} from "@lattice-script/base/tokens/DeployERC721.s.sol";
import {DeployERC721Burnable} from "@lattice-script/base/tokens/DeployERC721Burnable.s.sol";
import {DeployERC721Consecutive} from "@lattice-script/base/tokens/DeployERC721Consecutive.s.sol";
import {DeployERC721Enumerable} from "@lattice-script/base/tokens/DeployERC721Enumerable.s.sol";
import {DeployERC721Pausable} from "@lattice-script/base/tokens/DeployERC721Pausable.s.sol";
import {DeployERC721Royalty} from "@lattice-script/base/tokens/DeployERC721Royalty.s.sol";
import {DeployERC721URIStorage} from "@lattice-script/base/tokens/DeployERC721URIStorage.s.sol";
import {DeployERC721Votes} from "@lattice-script/base/tokens/DeployERC721Votes.s.sol";
import {DeployERC721Wrapper} from "@lattice-script/base/tokens/DeployERC721Wrapper.s.sol";
import {DeployERC7802} from "@lattice-script/base/tokens/DeployERC7802.s.sol";
import {DeployHTSAdapter} from "@lattice-script/base/tokens/DeployHTSAdapter.s.sol";
import {DeployMarketplaceZone} from "@lattice-script/base/tokens/DeployMarketplaceZone.s.sol";
import {DeployMulticall} from "@lattice-script/base/utils/DeployMulticall.s.sol";

/// @title RecipeInventory
/// @author David Dada <daveproxy80@gmail.com> (https://github.com/dadadave80)
/// @notice Canonical recipe artifact identities; cut/init definitions stay local to each recipe.
/// @dev The compiler/source census rejects omitted recipes or builder signatures. Demonstration contexts are separate.
library RecipeInventory {
    function inventory() internal pure returns (string[] memory names, string[] memory artifacts) {
        string[103] memory n = [
            "DeployAccessControl",
            "DeployAccessControlEnumerable",
            "DeployAccessControlTimed",
            "DeployAccessManaged",
            "DeployAccessManager",
            "DeployAccount",
            "DeployAccount6900",
            "DeployConstantProduct",
            "DeployAcrossBridgeAdapter",
            "DeployAxelarGatewayAdapter",
            "DeployBridgeERC20",
            "DeployBridgeERC7802",
            "DeployCCIPGatewayAdapter",
            "DeployCCTPBridgeAdapter",
            "DeployChainRegistry",
            "DeployCrosschainLink",
            "DeployCrosschainTimelockHandler",
            "DeployERC7786OpenBridge",
            "DeployHyperbridgeGatewayAdapter",
            "DeployHyperlaneGatewayAdapter",
            "DeployL1ToL2CrossDomainMessengerGatewayAdapter",
            "DeployL2ToL2CrossDomainMessengerGatewayAdapter",
            "DeployLayerZeroGatewayAdapter",
            "DeployStargateBridgeAdapter",
            "DeployStarknetGatewayAdapter",
            "DeploySuperchainETHBridgeAdapter",
            "DeployWormholeGatewayAdapter",
            "DeployZetaChainGatewayAdapter",
            "DeployAggregatorExecAdapter",
            "DeployGovernedVault",
            "DeployGovernedVaultENS",
            "DeployStrategyManager",
            "DeployVaultCore",
            "DeployENSResolver",
            "DeployENSReverseClaimer",
            "DeployENSSubnameIssuer",
            "DeployGovernedDiamondCut",
            "DeployGovernedSafeDiamondCut",
            "DeploySafeDiamondCut",
            "DeploySafeHarborAdopter",
            "DeployAPI3Adapter",
            "DeployAPI3QRNGAdapter",
            "DeployBandAdapter",
            "DeployChainlinkAdapter",
            "DeployChainlinkAutomationAdapter",
            "DeployChainlinkCREAdapter",
            "DeployChainlinkVRF",
            "DeployChronicleAdapter",
            "DeployDIAAdapter",
            "DeployGelatoAutomateAdapter",
            "DeployGelatoVRFAdapter",
            "DeployHSSAdapter",
            "DeployOracleGuard",
            "DeployPythAdapter",
            "DeployPythEntropyAdapter",
            "DeployRedStoneAdapter",
            "DeployTWAPOracle",
            "DeployTellorAdapter",
            "DeployCommitReveal",
            "DeployERC5564Announcer",
            "DeployERC6538Registry",
            "DeployGroth16Verifier",
            "DeployPlonkVerifier",
            "DeployPrivateVoting",
            "DeploySemaphore",
            "DeployShieldedPool",
            "DeployCircuitBreaker",
            "DeployEmergencyStop",
            "DeployInvariantChecker",
            "DeployPausable",
            "DeployRateLimiter",
            "DeployERC1155",
            "DeployERC1155Burnable",
            "DeployERC1155Pausable",
            "DeployERC1155Supply",
            "DeployERC1155URIStorage",
            "DeployERC1363",
            "DeployERC20",
            "DeployERC20Burnable",
            "DeployERC20Capped",
            "DeployERC20Crosschain",
            "DeployERC20FlashMint",
            "DeployERC20Pausable",
            "DeployERC20Permit",
            "DeployERC20TemporaryApproval",
            "DeployERC20Votes",
            "DeployERC20Wrapper",
            "DeployERC2981",
            "DeployERC3643",
            "DeployERC4626",
            "DeployERC721",
            "DeployERC721Burnable",
            "DeployERC721Consecutive",
            "DeployERC721Enumerable",
            "DeployERC721Pausable",
            "DeployERC721Royalty",
            "DeployERC721URIStorage",
            "DeployERC721Votes",
            "DeployERC721Wrapper",
            "DeployERC7802",
            "DeployHTSAdapter",
            "DeployMarketplaceZone",
            "DeployMulticall"
        ];
        string[103] memory p = [
            "script/base/access/DeployAccessControl.s.sol:DeployAccessControl",
            "script/base/access/DeployAccessControlEnumerable.s.sol:DeployAccessControlEnumerable",
            "script/base/access/DeployAccessControlTimed.s.sol:DeployAccessControlTimed",
            "script/base/access/DeployAccessManaged.s.sol:DeployAccessManaged",
            "script/base/access/DeployAccessManager.s.sol:DeployAccessManager",
            "script/base/accounts/DeployAccount.s.sol:DeployAccount",
            "script/base/accounts/DeployAccount6900.s.sol:DeployAccount6900",
            "script/base/amm/DeployConstantProduct.s.sol:DeployConstantProduct",
            "script/base/crosschain/DeployAcrossBridgeAdapter.s.sol:DeployAcrossBridgeAdapter",
            "script/base/crosschain/DeployAxelarGatewayAdapter.s.sol:DeployAxelarGatewayAdapter",
            "script/base/crosschain/DeployBridgeERC20.s.sol:DeployBridgeERC20",
            "script/base/crosschain/DeployBridgeERC7802.s.sol:DeployBridgeERC7802",
            "script/base/crosschain/DeployCCIPGatewayAdapter.s.sol:DeployCCIPGatewayAdapter",
            "script/base/crosschain/DeployCCTPBridgeAdapter.s.sol:DeployCCTPBridgeAdapter",
            "script/base/crosschain/DeployChainRegistry.s.sol:DeployChainRegistry",
            "script/base/crosschain/DeployCrosschainLink.s.sol:DeployCrosschainLink",
            "script/base/crosschain/DeployCrosschainTimelockHandler.s.sol:DeployCrosschainTimelockHandler",
            "script/base/crosschain/DeployERC7786OpenBridge.s.sol:DeployERC7786OpenBridge",
            "script/base/crosschain/DeployHyperbridgeGatewayAdapter.s.sol:DeployHyperbridgeGatewayAdapter",
            "script/base/crosschain/DeployHyperlaneGatewayAdapter.s.sol:DeployHyperlaneGatewayAdapter",
            "script/base/crosschain/DeployL1ToL2CrossDomainMessengerGatewayAdapter.s.sol:DeployL1ToL2CrossDomainMessengerGatewayAdapter",
            "script/base/crosschain/DeployL2ToL2CrossDomainMessengerGatewayAdapter.s.sol:DeployL2ToL2CrossDomainMessengerGatewayAdapter",
            "script/base/crosschain/DeployLayerZeroGatewayAdapter.s.sol:DeployLayerZeroGatewayAdapter",
            "script/base/crosschain/DeployStargateBridgeAdapter.s.sol:DeployStargateBridgeAdapter",
            "script/base/crosschain/DeployStarknetGatewayAdapter.s.sol:DeployStarknetGatewayAdapter",
            "script/base/crosschain/DeploySuperchainETHBridgeAdapter.s.sol:DeploySuperchainETHBridgeAdapter",
            "script/base/crosschain/DeployWormholeGatewayAdapter.s.sol:DeployWormholeGatewayAdapter",
            "script/base/crosschain/DeployZetaChainGatewayAdapter.s.sol:DeployZetaChainGatewayAdapter",
            "script/base/defi/DeployAggregatorExecAdapter.s.sol:DeployAggregatorExecAdapter",
            "script/base/defi/DeployGovernedVault.s.sol:DeployGovernedVault",
            "script/base/defi/DeployGovernedVaultENS.s.sol:DeployGovernedVaultENS",
            "script/base/defi/DeployStrategyManager.s.sol:DeployStrategyManager",
            "script/base/defi/DeployVaultCore.s.sol:DeployVaultCore",
            "script/base/ens/DeployENSResolver.s.sol:DeployENSResolver",
            "script/base/ens/DeployENSReverseClaimer.s.sol:DeployENSReverseClaimer",
            "script/base/ens/DeployENSSubnameIssuer.s.sol:DeployENSSubnameIssuer",
            "script/base/governance/DeployGovernedDiamondCut.s.sol:DeployGovernedDiamondCut",
            "script/base/governance/DeployGovernedSafeDiamondCut.s.sol:DeployGovernedSafeDiamondCut",
            "script/base/governance/DeploySafeDiamondCut.s.sol:DeploySafeDiamondCut",
            "script/base/governance/DeploySafeHarborAdopter.s.sol:DeploySafeHarborAdopter",
            "script/base/oracles/DeployAPI3Adapter.s.sol:DeployAPI3Adapter",
            "script/base/oracles/DeployAPI3QRNGAdapter.s.sol:DeployAPI3QRNGAdapter",
            "script/base/oracles/DeployBandAdapter.s.sol:DeployBandAdapter",
            "script/base/oracles/DeployChainlinkAdapter.s.sol:DeployChainlinkAdapter",
            "script/base/oracles/DeployChainlinkAutomationAdapter.s.sol:DeployChainlinkAutomationAdapter",
            "script/base/oracles/DeployChainlinkCREAdapter.s.sol:DeployChainlinkCREAdapter",
            "script/base/oracles/DeployChainlinkVRF.s.sol:DeployChainlinkVRF",
            "script/base/oracles/DeployChronicleAdapter.s.sol:DeployChronicleAdapter",
            "script/base/oracles/DeployDIAAdapter.s.sol:DeployDIAAdapter",
            "script/base/oracles/DeployGelatoAutomateAdapter.s.sol:DeployGelatoAutomateAdapter",
            "script/base/oracles/DeployGelatoVRFAdapter.s.sol:DeployGelatoVRFAdapter",
            "script/base/oracles/DeployHSSAdapter.s.sol:DeployHSSAdapter",
            "script/base/oracles/DeployOracleGuard.s.sol:DeployOracleGuard",
            "script/base/oracles/DeployPythAdapter.s.sol:DeployPythAdapter",
            "script/base/oracles/DeployPythEntropyAdapter.s.sol:DeployPythEntropyAdapter",
            "script/base/oracles/DeployRedStoneAdapter.s.sol:DeployRedStoneAdapter",
            "script/base/oracles/DeployTWAPOracle.s.sol:DeployTWAPOracle",
            "script/base/oracles/DeployTellorAdapter.s.sol:DeployTellorAdapter",
            "script/base/privacy/DeployCommitReveal.s.sol:DeployCommitReveal",
            "script/base/privacy/DeployERC5564Announcer.s.sol:DeployERC5564Announcer",
            "script/base/privacy/DeployERC6538Registry.s.sol:DeployERC6538Registry",
            "script/base/privacy/DeployGroth16Verifier.s.sol:DeployGroth16Verifier",
            "script/base/privacy/DeployPlonkVerifier.s.sol:DeployPlonkVerifier",
            "script/base/privacy/DeployPrivateVoting.s.sol:DeployPrivateVoting",
            "script/base/privacy/DeploySemaphore.s.sol:DeploySemaphore",
            "script/base/privacy/DeployShieldedPool.s.sol:DeployShieldedPool",
            "script/base/security/DeployCircuitBreaker.s.sol:DeployCircuitBreaker",
            "script/base/security/DeployEmergencyStop.s.sol:DeployEmergencyStop",
            "script/base/security/DeployInvariantChecker.s.sol:DeployInvariantChecker",
            "script/base/security/DeployPausable.s.sol:DeployPausable",
            "script/base/security/DeployRateLimiter.s.sol:DeployRateLimiter",
            "script/base/tokens/DeployERC1155.s.sol:DeployERC1155",
            "script/base/tokens/DeployERC1155Burnable.s.sol:DeployERC1155Burnable",
            "script/base/tokens/DeployERC1155Pausable.s.sol:DeployERC1155Pausable",
            "script/base/tokens/DeployERC1155Supply.s.sol:DeployERC1155Supply",
            "script/base/tokens/DeployERC1155URIStorage.s.sol:DeployERC1155URIStorage",
            "script/base/tokens/DeployERC1363.s.sol:DeployERC1363",
            "script/base/tokens/DeployERC20.s.sol:DeployERC20",
            "script/base/tokens/DeployERC20Burnable.s.sol:DeployERC20Burnable",
            "script/base/tokens/DeployERC20Capped.s.sol:DeployERC20Capped",
            "script/base/tokens/DeployERC20Crosschain.s.sol:DeployERC20Crosschain",
            "script/base/tokens/DeployERC20FlashMint.s.sol:DeployERC20FlashMint",
            "script/base/tokens/DeployERC20Pausable.s.sol:DeployERC20Pausable",
            "script/base/tokens/DeployERC20Permit.s.sol:DeployERC20Permit",
            "script/base/tokens/DeployERC20TemporaryApproval.s.sol:DeployERC20TemporaryApproval",
            "script/base/tokens/DeployERC20Votes.s.sol:DeployERC20Votes",
            "script/base/tokens/DeployERC20Wrapper.s.sol:DeployERC20Wrapper",
            "script/base/tokens/DeployERC2981.s.sol:DeployERC2981",
            "script/base/tokens/DeployERC3643.s.sol:DeployERC3643",
            "script/base/tokens/DeployERC4626.s.sol:DeployERC4626",
            "script/base/tokens/DeployERC721.s.sol:DeployERC721",
            "script/base/tokens/DeployERC721Burnable.s.sol:DeployERC721Burnable",
            "script/base/tokens/DeployERC721Consecutive.s.sol:DeployERC721Consecutive",
            "script/base/tokens/DeployERC721Enumerable.s.sol:DeployERC721Enumerable",
            "script/base/tokens/DeployERC721Pausable.s.sol:DeployERC721Pausable",
            "script/base/tokens/DeployERC721Royalty.s.sol:DeployERC721Royalty",
            "script/base/tokens/DeployERC721URIStorage.s.sol:DeployERC721URIStorage",
            "script/base/tokens/DeployERC721Votes.s.sol:DeployERC721Votes",
            "script/base/tokens/DeployERC721Wrapper.s.sol:DeployERC721Wrapper",
            "script/base/tokens/DeployERC7802.s.sol:DeployERC7802",
            "script/base/tokens/DeployHTSAdapter.s.sol:DeployHTSAdapter",
            "script/base/tokens/DeployMarketplaceZone.s.sol:DeployMarketplaceZone",
            "script/base/utils/DeployMulticall.s.sol:DeployMulticall"
        ];
        names = new string[](n.length);
        artifacts = new string[](p.length);
        for (uint256 i; i < n.length; ++i) {
            names[i] = n[i];
            artifacts[i] = p[i];
        }
    }
}

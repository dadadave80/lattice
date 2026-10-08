# Vendored third-party dependencies

These directories hold **verbatim, audited** Solidity sources vendored into the
repo (byte-identical to upstream — no edits) because their canonical git remotes
are intermittently unreachable for submodule installation. Each is forge-
installable normally; vendoring is the fallback and keeps builds reproducible.
Swap for real submodules when convenient — the remappings already match the
upstream import paths, so no source change is needed.

Later sections list the third-party interfaces re-declared under `src/interfaces/external/` and the
modules ported or adapted from external sources, with each upstream's license.

| Path | Upstream | Version / commit | License |
|------|----------|------------------|---------|
| `poseidon-solidity/PoseidonT3.sol` | npm `poseidon-solidity` (chancehudson) | 0.0.5 | MIT |
| `zk-kit/lean-imt/` | github.com/privacy-scaling-explorations/zk-kit.solidity `packages/lean-imt/contracts` | a171c845ec7fdc50cdd1fe96c14c27d707cdfbed | MIT |
| `semaphore/` | github.com/semaphore-protocol/semaphore `packages/contracts/contracts` (SemaphoreVerifier + KeyPts + Constants + ISemaphoreVerifier) | 341475c66bee7473f8d25f44bc0dcf6b255b5a6c | MIT |

PoseidonT3 is the gas-optimized BN254 Poseidon used by every SNARK-friendly
incremental Merkle tree in the ecosystem; LeanIMT is the PSE-audited (Semaphore
v4 audit, PSE, Mar 2024) dynamic-depth incremental Merkle tree. Both are
required because Lattice's ZK circuits hash with Poseidon — a keccak tree would
not verify against them.

Pipeline note: `PoseidonT3.sol` is hand-tuned assembly optimized for solc's
**legacy** (non-`via_ir`) pipeline, where it deploys at ~23.5 KB — under the
EIP-170 24,576 B limit. Under `--via-ir` the IR optimizer restructures that
assembly and the contract balloons to ~29–55 KB, exceeding EIP-170 regardless of
`optimizer_runs`. Lattice's CI/deploy profile sets `via_ir = false`, so PoseidonT3
(and any Poseidon-based ZK module that links it) is deployed via the legacy
pipeline. The CI `via_ir` step still enforces EIP-170/EIP-3860 on every Lattice
contract but exempts PoseidonT3 specifically (the legacy `--sizes` build remains
its authoritative gate). Consumers compiling Lattice's ZK privacy modules should
likewise deploy PoseidonT3 with the legacy pipeline.

Note: upstream's `zk-kit/lean-imt/Constants.sol` ships an `UNLICENSED` SPDX tag
even though the zk-kit.solidity repository is MIT-licensed (Ethereum Foundation
2025, repo-root `LICENSE`). The file is vendored verbatim, so that per-file tag is
preserved as-is — faithful to upstream, not an injected edit. It holds only the
public BN254 scalar-field constant; Lattice's own libraries define
`SNARK_SCALAR_FIELD` first-party (MIT) rather than importing that file.

## Account passkey crypto (`src/utils/libraries/`)

The smart-account signer (`src/accounts/SignerECDSA`) verifies P256 (secp256r1) and
WebAuthn signatures using audited Solady crypto. Unlike the byte-identical `lib/`
vendors above, these are vendored into `src/utils/libraries/` with **minimal
mechanical edits** — see each file's header for the exact delta:

| Path | Upstream | Version / commit | License |
|------|----------|------------------|---------|
| `src/utils/libraries/P256.sol` | Vectorized/solady `src/utils/P256.sol` | ab96a830e705de13e0f58cfaefadab4ac8257655 | MIT |
| `src/utils/libraries/Base64.sol` | Vectorized/solady `src/utils/Base64.sol` | ab96a830e705de13e0f58cfaefadab4ac8257655 | MIT |
| `src/utils/libraries/WebAuthn.sol` | Vectorized/solady `src/utils/WebAuthn.sol` | ab96a830e705de13e0f58cfaefadab4ac8257655 | MIT |

Edits are limited to: pragma pinned to `^0.8.30`; and in `WebAuthn.sol`, the two
import paths rewritten to `@lattice/utils/libraries/{Base64,P256}.sol`. No logic or
assembly is changed. They are excluded from `forge fmt` (`[fmt] ignore` in
`foundry.toml`) so they stay diffable against upstream — re-sync from the pinned
commit rather than patching here. P256 verification uses the RIP-7212 precompile
(`0x100`) with a deployed-verifier fallback (`0x…D01eA45F9eFD5c54f037Fa57Ea1a`); on
a chain lacking both, passkey verification returns `false`, so gate passkey
enablement per target chain.

## Third-party interfaces (`src/interfaces/external/`)

Every file under `src/interfaces/external/` re-declares part of an external project's ABI so Lattice
can call or implement it without installing that project. Most are minimal subsets written fresh
against the upstream ABI; a few are copied verbatim (noted under "Form"). Each file is tagged
`SPDX-License-Identifier: MIT` unless a `(Lattice SPDX: <id>)` marker in the Form column says
otherwise; the marker is also shown where the Lattice tag differs from an Apache-2.0 upstream. Each
header names the upstream with `@author Vendored minimal subset of <Source> (<link>).` plus an
`Upstream license: <id>.` note. The BUSL-1.1 re-declarations (`compound/`, and `layerzero/IStargate.sol`
for its Stargate surface) instead say `@author ABI-equivalent interface authored fresh from <Source>'s
public ABI (<link>).`, because no upstream text was copied. The `ercs/` and `seal/` headers keep their
older wording until #247.

"Upstream license" is the SPDX tag of the upstream file the header links to, read from that file at
the upstream default branch in October 2026. "(repo)" means the upstream file has no SPDX tag and the
repository's root license is shown instead. "unknown" means the upstream file could not be found.
Paths are relative to `src/interfaces/external/`; `make license-check` fails if a file there is
missing from this table.

| File | Upstream | Upstream license | Form |
|------|----------|------------------|------|
| `aave/IAaveOracle.sol` | aave/aave-v3-core `contracts/interfaces/IPriceOracleGetter.sol` | AGPL-3.0 | subset |
| `aave/IAaveRewardsController.sol` | aave/aave-v3-periphery `contracts/rewards/interfaces/IRewardsController.sol` | AGPL-3.0 | subset |
| `aave/IAaveV3Pool.sol` | aave/aave-v3-core `contracts/interfaces/IPool.sol` | AGPL-3.0 | subset |
| `aave/IAToken.sol` | aave/aave-v3-core `contracts/interfaces/IAToken.sol` | AGPL-3.0 | subset |
| `aave/IPoolAddressesProvider.sol` | aave/aave-v3-core `contracts/interfaces/IPoolAddressesProvider.sol` | AGPL-3.0 | subset |
| `across/AcrossMessageHandler.sol` | across-protocol/contracts `contracts/interfaces/SpokePoolMessageHandler.sol` | MIT | subset |
| `across/V3SpokePoolInterface.sol` | across-protocol/contracts `contracts/interfaces/V3SpokePoolInterface.sol` | MIT | subset |
| `api3/IAirnodeRrpV0.sol` | api3dao/airnode `packages/airnode-protocol/contracts/rrp/interfaces/IAirnodeRrpV0.sol` | MIT | subset |
| `api3/IApi3Proxy.sol` | api3dao/contracts (dAPI proxy `read()`) | MIT | subset |
| `axelar/IAxelarGateway.sol` | axelarnetwork/axelar-gmp-sdk-solidity `contracts/interfaces/IAxelarGateway.sol` | MIT | subset |
| `band/IStdReference.sol` | bandprotocol/contract-tools `spec/StdReference.sol` | unknown (repository not publicly reachable) | subset |
| `chainlink/CCIPClient.sol` | smartcontractkit/chainlink-ccip `chains/evm/contracts/libraries/Client.sol` | MIT | subset (structs verbatim) |
| `chainlink/IAggregatorV3.sol` | smartcontractkit/chainlink-evm `contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol` | MIT | subset |
| `chainlink/IAny2EVMMessageReceiver.sol` | smartcontractkit/chainlink-ccip `chains/evm/contracts/interfaces/IAny2EVMMessageReceiver.sol` | MIT | subset |
| `chainlink/IAny2EVMMessageReceiverV2.sol` | smartcontractkit/chainlink-ccip `chains/evm/contracts/interfaces/IAny2EVMMessageReceiverV2.sol` | MIT | subset |
| `chainlink/IAutomationCompatible.sol` | smartcontractkit/chainlink-evm `contracts/src/v0.8/automation/interfaces/AutomationCompatibleInterface.sol` | unknown (file no longer at that path) | subset |
| `chainlink/IReceiver.sol` | Chainlink CRE docs sample `https://docs.chain.link/samples/CRE/IReceiver.sol` | MIT | subset |
| `chainlink/IRouterClient.sol` | smartcontractkit/chainlink-ccip `chains/evm/contracts/interfaces/IRouterClient.sol` | MIT | subset |
| `chainlink/IVRFConsumer.sol` | smartcontractkit/chainlink-evm `contracts/src/v0.8/vrf/interfaces/IVRFMigratableConsumerV2Plus.sol` | MIT | subset |
| `chainlink/IVRFCoordinatorV2Plus.sol` | smartcontractkit/chainlink-evm `contracts/src/v0.8/vrf/interfaces/IVRFCoordinatorV2Plus.sol` | MIT | subset |
| `chronicle/IChronicle.sol` | chronicleprotocol/chronicle-std `src/IChronicle.sol` | MIT | subset |
| `circle/IReceiverV2.sol` | circlefin/evm-cctp-contracts `src/v2/MessageTransmitterV2.sol` | Apache-2.0 | subset (Lattice SPDX: Apache-2.0) |
| `circle/ITokenMessengerV2.sol` | circlefin/evm-cctp-contracts `src/v2/TokenMessengerV2.sol` | Apache-2.0 | subset (Lattice SPDX: Apache-2.0) |
| `compound/IComet.sol` | compound-finance/comet `contracts/CometMainInterface.sol` | BUSL-1.1 | fresh ABI-equivalent re-declaration |
| `compound/ICometRewards.sol` | compound-finance/comet `contracts/CometRewards.sol` | BUSL-1.1 | fresh ABI-equivalent re-declaration |
| `createx/ICreateX.sol` | pcaversaccio/createx `src/ICreateX.sol` | AGPL-3.0-only | subset |
| `curve/ICurveGauge.sol` | curvefi/curve-dao-contracts `contracts/gauges/LiquidityGaugeV5.vy` | MIT | subset (from Vyper) |
| `curve/ICurveStableSwapPool.sol` | curvefi/curve-contract `contracts/pool-templates/base/SwapTemplateBase.vy` | none granted ("Copyright (c) Curve.Fi, 2020 - all rights reserved") | subset (from Vyper) |
| `dia/IDIAOracleV2.sol` | diadata-org/diadata `DIAOracleV2.sol` | GPL-3.0 (repo) | subset |
| `ens/IAddrResolver.sol` | ensdomains/ens-contracts `contracts/resolvers/profiles/IAddrResolver.sol` | MIT | subset |
| `ens/IENS.sol` | ensdomains/ens-contracts `contracts/registry/ENS.sol` | MIT | subset |
| `ens/IETHRegistrarController.sol` | ensdomains/ens-contracts `contracts/ethregistrar/IETHRegistrarController.sol` | MIT | subset |
| `ens/INameWrapper.sol` | ensdomains/ens-contracts `contracts/wrapper/INameWrapper.sol` | MIT | subset |
| `ens/IReverseRegistrar.sol` | ensdomains/ens-contracts `contracts/reverseRegistrar/{ReverseRegistrar,L2ReverseRegistrar}.sol` | MIT (repo for `ReverseRegistrar`; `L2ReverseRegistrar` is MIT) | subset |
| `ercs/IAccount.sol` | OpenZeppelin/openzeppelin-contracts `contracts/interfaces/draft-IERC4337.sol`; eth-infinitism/account-abstraction `contracts/interfaces/IAccount.sol` | MIT | re-authored to the ERC-4337 ABI |
| `ercs/IEntryPoint.sol` | eth-infinitism/account-abstraction `contracts/interfaces/IEntryPoint.sol` | MIT | re-authored subset |
| `ercs/IERC1271.sol` | OpenZeppelin/openzeppelin-contracts `contracts/interfaces/IERC1271.sol` | MIT | subset |
| `ercs/IERC3156FlashBorrower.sol` | OpenZeppelin/openzeppelin-contracts `contracts/interfaces/IERC3156FlashBorrower.sol` | MIT | vendored |
| `ercs/IERC3156FlashLender.sol` | OpenZeppelin/openzeppelin-contracts `contracts/interfaces/IERC3156FlashLender.sol` | MIT | vendored |
| `ercs/IERC6551.sol` | erc6551/reference `src/interfaces/IERC6551{Account,Executable,Registry}.sol` | MIT | re-authored to the ERC-6551 ABI |
| `ercs/IERC6900.sol` | ERC-6900 spec; erc6900/reference-implementation `src/interfaces/` | CC0-1.0 | subset |
| `ercs/IERC7579.sol` | OpenZeppelin/openzeppelin-contracts `contracts/interfaces/draft-IERC7579.sol` | MIT | subset |
| `ercs/IERC7786.sol` | OpenZeppelin/openzeppelin-contracts `contracts/interfaces/draft-IERC7786.sol` @ `5fd1781` | MIT | verbatim |
| `ercs/IERC7786Attributes.sol` | OpenZeppelin/openzeppelin-community-contracts `contracts/interfaces/IERC7786Attributes.sol` @ `f7e5f08` | MIT | vendored |
| `ercs/IERC7802.sol` | OpenZeppelin/openzeppelin-contracts `contracts/interfaces/draft-IERC7802.sol` @ `5fd1781` | MIT | subset |
| `ercs/IERC7821.sol` | Vectorized/solady `src/accounts/ERC7821.sol` | MIT | re-authored to the ERC-7821 ABI |
| `ercs/IERC8153.sol` | ERC-8153 draft (`https://eips.ethereum.org/EIPS/eip-8153`) | CC0-1.0 (EIP text) | subset |
| `gelato/IGelatoAutomate.sol` | gelatodigital/automate `contracts/interfaces/IAutomate.sol` | MIT | subset |
| `gelato/IGelatoVRFConsumer.sol` | gelatodigital/vrf-contracts `contracts/IGelatoVRFConsumer.sol` | unknown (repository not publicly reachable) | subset |
| `hedera/HederaResponseCodes.sol` | hiero-ledger/hiero-contracts `contracts/common/HederaResponseCodes.sol` @ `5ade6c8` | Apache-2.0 | subset (Lattice SPDX: Apache-2.0) |
| `hedera/IExchangeRate.sol` | hiero-ledger/hiero-contracts `contracts/exchange-rate/IExchangeRate.sol` @ `5ade6c8` | Apache-2.0 | subset (Lattice SPDX: Apache-2.0) |
| `hedera/IHederaAccountService.sol` | hiero-ledger/hiero-contracts `contracts/account-service/IHederaAccountService.sol` @ `5ade6c8` | Apache-2.0 | subset (Lattice SPDX: Apache-2.0) |
| `hedera/IHederaScheduleService.sol` | hiero-ledger/hiero-contracts `contracts/schedule-service/{IHRC755,IHRC1215}.sol` @ `5ade6c8` | Apache-2.0 | subset (Lattice SPDX: Apache-2.0) |
| `hedera/IHederaTokenService.sol` | hiero-ledger/hiero-contracts `contracts/token-service/IHederaTokenService.sol` @ `5ade6c8` | Apache-2.0 | subset (Lattice SPDX: Apache-2.0) |
| `hedera/IHRC719.sol` | hiero-ledger/hiero-contracts `contracts/token-service/IHRC719.sol` @ `5ade6c8` | Apache-2.0 | subset (Lattice SPDX: Apache-2.0) |
| `hedera/IPrngSystemContract.sol` | hiero-ledger/hiero-contracts `contracts/prng/IPrngSystemContract.sol` @ `5ade6c8` | Apache-2.0 | subset (Lattice SPDX: Apache-2.0) |
| `hyperbridge/IIsmpDispatcher.sol` | polytope-labs/ismp-solidity `interfaces/IDispatcher.sol` | Apache-2.0 | subset (Lattice SPDX: Apache-2.0) |
| `hyperbridge/IIsmpModule.sol` | polytope-labs/ismp-solidity `interfaces/IIsmpModule.sol` | Apache-2.0 | subset (Lattice SPDX: Apache-2.0) |
| `hyperlane/IMailbox.sol` | hyperlane-xyz/hyperlane-monorepo `solidity/contracts/interfaces/IMailbox.sol` | MIT OR Apache-2.0 | subset |
| `hyperlane/IMessageRecipient.sol` | hyperlane-xyz/hyperlane-monorepo `solidity/contracts/interfaces/IMessageRecipient.sol` | MIT OR Apache-2.0 | subset |
| `layerzero/ILayerZeroEndpointV2.sol` | LayerZero-Labs/LayerZero-v2 `.../protocol/contracts/interfaces/ILayerZeroEndpointV2.sol` | MIT | subset |
| `layerzero/ILayerZeroReceiver.sol` | LayerZero-Labs/LayerZero-v2 `.../protocol/contracts/interfaces/ILayerZeroReceiver.sol` | MIT | subset |
| `layerzero/IStargate.sol` | LayerZero-Labs/LayerZero-v2 `.../oapp/contracts/oft/interfaces/IOFT.sol` (structs); stargate-protocol/stargate-v2 `packages/stg-evm-v2/src/interfaces/IStargate.sol` (functions) | MIT (IOFT); BUSL-1.1 (IStargate) | structs verbatim from IOFT; functions a fresh ABI-equivalent re-declaration (#77) |
| `lido/ILido.sol` | lidofinance/lido-dao `contracts/0.4.24/Lido.sol` | GPL-3.0 | subset |
| `lido/ILidoWithdrawalQueue.sol` | lidofinance/lido-dao `contracts/0.8.9/WithdrawalQueueERC721.sol` | GPL-3.0 | subset |
| `lido/IWstETH.sol` | lidofinance/lido-dao `contracts/0.6.12/WstETH.sol` | GPL-3.0 | subset |
| `optimism/ICrossDomainMessenger.sol` | ethereum-optimism/optimism `packages/contracts-bedrock/src/universal/CrossDomainMessenger.sol` | MIT | subset |
| `optimism/IL2ToL2CrossDomainMessenger.sol` | ethereum-optimism/optimism `packages/contracts-bedrock/src/L2/L2ToL2CrossDomainMessenger.sol` | MIT | subset |
| `optimism/ISuperchainETHBridge.sol` | ethereum-optimism/optimism `packages/contracts-bedrock/src/L2/SuperchainETHBridge.sol` | MIT | subset |
| `pyth/IEntropy.sol` | pyth-network/pyth-crosschain `target_chains/ethereum/entropy_sdk/solidity/IEntropy.sol` | Apache-2.0 (tagged "Apache 2") | subset (Lattice SPDX: MIT) |
| `pyth/IPyth.sol` | pyth-network/pyth-crosschain `target_chains/ethereum/sdk/solidity/IPyth.sol` | Apache-2.0 | subset (Lattice SPDX: MIT) |
| `redstone/IRedstonePriceFeedsAdapter.sol` | redstone-finance/redstone-oracles-monorepo (Push `PriceFeedsAdapter`) | unknown (no matching file in the monorepo; root license BUSL-1.1) | subset |
| `safe/ISafe.sol` | safe-global/safe-smart-account `contracts/Safe.sol` | LGPL-3.0-only | subset |
| `seal/IAgreementFactory.sol` | security-alliance/safe-harbor `registry-contracts/src/types/AgreementTypes.sol` (v3.0.0) | MIT | subset |
| `seal/ISafeHarborRegistry.sol` | security-alliance/safe-harbor `registry-contracts/src/SafeHarborRegistry.sol` (v3.0.0) | MIT | subset |
| `seaport/SeaportStructs.sol` | ProjectOpenSea/seaport-types `src/lib/{ConsiderationEnums,ConsiderationStructs}.sol` @ `b724932` | MIT | subset (types verbatim) |
| `seaport/ZoneInterface.sol` | ProjectOpenSea/seaport-types `src/interfaces/ZoneInterface.sol` | MIT | subset |
| `starknet/IStarknetMessaging.sol` | starkware-libs/cairo-lang `src/starkware/starknet/solidity/IStarknetMessaging.sol` | Apache-2.0 | subset (Lattice SPDX: MIT) |
| `tellor/ITellor.sol` | tellor-io/usingtellor `contracts/interface/ITellor.sol` | MIT | subset |
| `uniswap/INonfungiblePositionManager.sol` | Uniswap/v3-periphery `contracts/interfaces/INonfungiblePositionManager.sol` | GPL-2.0-or-later | subset |
| `uniswap/IUniswapV2Pair.sol` | Uniswap/v2-core `contracts/interfaces/IUniswapV2Pair.sol` | GPL-3.0 (repo) | subset |
| `uniswap/IUniswapV3Pool.sol` | Uniswap/v3-core `contracts/interfaces/IUniswapV3Pool.sol` + `pool/IUniswapV3PoolDerivedState.sol` | GPL-2.0-or-later | subset |
| `weth/IWETH9.sol` | gnosis/canonical-weth `contracts/WETH9.sol` | GPL-3.0-or-later | subset |
| `wormhole/IWormholeRelayer.sol` | wormhole-foundation/wormhole-solidity-sdk `src/interfaces/IWormholeRelayer.sol` | Apache-2.0 | subset (Lattice SPDX: Apache-2.0) |
| `yearn/IStrategy.sol` | yearn/tokenized-strategy `src/interfaces/ITokenizedStrategy.sol` | AGPL-3.0 | subset |
| `zetachain/IGatewayEVM.sol` | zeta-chain/protocol-contracts `contracts/evm/interfaces/IGatewayEVM.sol` | MIT | subset |

## Ported and adapted modules

Lattice modules whose logic is ported or adapted from an external source carry a
`@author Modified from <Source> (<link>)` line, or `@author Adapted for EIP-2535 from OpenZeppelin ...` for OZ
ports (AGENTS.md, "External-source attribution"). The same line also appears on integration adapters that
exist to wrap one protocol; those only call the protocol through an interface in the table above, so
that table gives the relevant license. This table covers the ported logic, plus the LI.FI adapter,
which has no vendored interface. Licenses were read the same
way as above.

| Lattice files | Upstream | Upstream license |
|---------------|----------|------------------|
| `access/`, `governance/` (Governor, Timelock, Votes), `security/` (Pausable, EmergencyStop), `tokens/` (ERC20 family, ERC721, ERC1155, ERC2981, ERC4626), `defi/VaultCore*`, `defi/libraries/AdapterBaseLib.sol`, `accounts/` (ERC1271, ERC7739), `utils/` (EIP712, Nonces, Multicall, VestingWallet, Initializable, Checkpoints, ECDSA, EnumerableSet, ShortStrings, SignatureChecker, Math, SafeCast, Bytes, Calldata, Panic, InteroperableAddress, Strings, TimelockLib) and their interfaces | OpenZeppelin/openzeppelin-contracts | MIT |
| `crosschain/` (BridgeERC20, BridgeERC7802, BridgeFungible, CrosschainLink), `tokens/ERC20/ERC20Crosschain*` | OpenZeppelin/openzeppelin-contracts v5.6.1 | MIT |
| `crosschain/` (ERC7786OpenBridge, `axelar/AxelarGatewayAdapter*`, `wormhole/WormholeGatewayAdapter*`) | OpenZeppelin/openzeppelin-community-contracts | MIT |
| `utils/libraries/P256.sol`, `Base64.sol`, `WebAuthn.sol` | Vectorized/solady (see "Account passkey crypto" above) | MIT |
| `security/ReentrancyGuard*`, `accounts/erc7579/ERC7821Executor*` | Vectorized/solady `src/utils/ReentrancyGuardTransient.sol`, `src/accounts/ERC7821.sol` | MIT |
| `Lattice.sol`, `utils/Initializable.sol`, `utils/libraries/InitializableLib.sol` | dadadave80/diamond-lib (first-party) | MIT |
| `privacy/Groth16Verifier*`, `privacy/PlonkVerifier*` and their interfaces | iden3/snarkjs `templates/verifier_{groth16,plonk}.sol.ejs` | GPL-3.0 |
| `privacy/Semaphore*` | semaphore-protocol/semaphore `packages/contracts/contracts/Semaphore.sol` | MIT |
| `privacy/libraries/IncrementalMerkleTreeLib.sol` | privacy-scaling-explorations/zk-kit.solidity `packages/lean-imt` | MIT |
| `privacy/ERC5564Announcer*`, `privacy/ERC6538Registry*` | ScopeLift/stealth-address-erc-contracts `src/ERC5564Announcer.sol`, `src/ERC6538Registry.sol` | CC0-1.0 |
| `amm/ConstantProduct*` | Uniswap/v2-core `contracts/UniswapV2Pair.sol` | GPL-3.0 (repo) |
| `oracles/uniswap/TWAPOracle*` | Uniswap/v2-periphery `contracts/examples/ExampleSlidingWindowOracle.sol` | GPL-3.0 (repo) |
| `utils/libraries/UniswapV3FullRangeMath.sol` | Uniswap/v3-core `contracts/libraries/TickMath.sol` | GPL-2.0-or-later |
| `examples/crosschain/CCTPHookReceipt*` | Uniswap/v4-periphery | MIT (file tags under `src/`) |
| `defi/StrategyManager*` | yearn/yearn-vaults-v3 `contracts/VaultV3.vy` | AGPL-3.0 |
| `utils/libraries/InterestRate.sol` | compound-finance/compound-protocol `contracts/JumpRateModelV2.sol` | BSD-3-Clause |
| `accounts/ERC4337Validation*` | eth-infinitism/account-abstraction `contracts/core/` | MIT |
| `accounts/ERC6551Account*` | erc6551/reference | MIT |
| `accounts/erc6900/` | erc6900/reference-implementation | CC0-1.0 (interfaces); MIT (repo) |
| `accounts/erc7579/AccountDiamond.sol`, `ERC7579ModuleConfig*` | erc7579/erc7579-implementation | MIT |
| `ens/`, `LatticeFactory.sol` (reverse-record claim) | ensdomains/ens-contracts | MIT |
| `tokens/MarketplaceZone*` | ProjectOpenSea/seaport | MIT |
| `security/RateLimiter*`, `crosschain/chainlink/CCIPGatewayAdapter*` | smartcontractkit/chainlink-ccip | MIT |
| `oracles/chainlink/ChainlinkVRF*` | smartcontractkit/chainlink-evm `contracts/src/v0.8/vrf/VRFConsumerBaseV2Plus.sol` | MIT |
| `tokens/ERC7802/ERC7802.sol` | ERC-7802 spec (`https://eips.ethereum.org/EIPS/eip-7802`) | CC0-1.0 (EIP text) |
| `defi/AggregatorExecAdapter*` (integration adapter with no vendored interface) | lifinance/contracts | LGPL-3.0 (repo) |

## License position on re-declared interfaces

<!-- MAINTAINER: replace this placeholder with the project's position. -->
**Placeholder, pending the maintainer's decision (#230).** Record here whether Lattice treats the minimal
ABI re-declarations of GPL, LGPL, AGPL, BUSL and all-rights-reserved upstreams above (and the ported logic
from GPL/AGPL upstreams) as independent works under MIT, and whether re-declarations of Apache-2.0
upstreams keep an Apache-2.0 SPDX tag (most) or MIT (`starknet/IStarknetMessaging.sol`, `pyth/`).

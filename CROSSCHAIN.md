# Lattice Crosschain Adapter Suite

The reference for every crosschain module shipped under epic #77: the adapter taxonomy, the
per-adapter trust/fee/refund contract, the suite-wide conventions they all follow, and the
off-chain dependencies each one needs to actually deliver. Every module follows the repo's
three-layer Diamond pattern — vendored external interface (`src/interfaces/external/`) →
ERC-7201 `*Lib` (all logic + storage) → stateless facet — with a ready-to-deploy recipe in
`script/base/`, a real-diamond test base, and unit tests that assemble the production cuts.

Storage/interface slots for every module are registered in [`STORAGE_REGISTRY.md`](STORAGE_REGISTRY.md)
and re-derived from first principles by `test/unit/StorageSlotVerificationTest.t.sol` (uniqueness-swept, CI-gated).

## 1. Taxonomy — the six adapter shapes

| Shape | Contract | Members |
|---|---|---|
| **Push message gateway** (ERC-7786) | `sendMessage(recipient, payload, attributes)` out; protocol-pushed inbound callback; `chainId ↔ native-id` map; trusted remote per chainId; replay guard; delivers to `CrosschainLink` | CCIP, Axelar, Wormhole, LayerZero v2, Hyperlane, ZetaChain *(hub-routed)*, Hyperbridge *(proof-verified)* |
| **Inverted-inbound gateway** (OP Stack) | The facet itself is the relayed target; authenticates via the messenger's context, not calldata-encoded source | `L2ToL2CrossDomainMessengerGatewayAdapter`, `L1ToL2CrossDomainMessengerGatewayAdapter` |
| **Token rail** | Moves value, not messages. Three settlement models — **burn/mint attested** (CCTP), **intent/optimistic** (Across), **pooled-liquidity credits** (Stargate) — plus the gateway-routed `BridgeERC20`/`BridgeERC7802` (`FUNGIBLE_BRIDGE_TAG`) and native-ETH `SuperchainETHBridgeAdapter` | CCTPBridgeAdapter, AcrossBridgeAdapter, StargateBridgeAdapter, BridgeERC20, BridgeERC7802, SuperchainETHBridgeAdapter |
| **Execution config** (type-C) | Arbitrary quote-API calldata against an admin allow-listed `(aggregator, selector)` pair; outbound-only; all security is pull-from-caller + exact-approve→0 + delta sweeps | `AggregatorExecAdapter` base; LI.FI + Relay as pure configurations (`script/config/EnableRelay.s.sol`) |
| **Non-EVM connector** | Bespoke surface where the ERC-7786 contract can't hold (no message id, pull-based consume, non-EVM addressing) | `StarknetGatewayAdapter` (felt252, counter consume, initiator-gated cancellation) |
| **Composition layer** | M-of-N aggregation, inbound tag routing, one-action chain config | `ERC7786OpenBridge` (+ `minDirectCoverage` gate), `CrosschainLink`, `ChainRegistry` (`addEvmChain` fan-out across all 10 registered adapters) |

## 2. Per-adapter reference

| Adapter | Trust model | Identity / dedup | Fee model | Refund path | Inbound auth |
|---|---|---|---|---|---|
| CCIPGatewayAdapter | Chainlink DON | CCIP messageId; `_executed` per chain | native or feeToken via Router quote | unconsumed `msg.value` refunded to `msg.sender` (all of it on the feeToken path) | `msg.sender == router` + `ccipReceive` source check |
| AxelarGatewayAdapter | Axelar validator set | commandId; gateway `validateContractCall` one-shot (no adapter map) | none in-adapter (`msg.value` reverts); gas prepaid off-band to the Axelar gas service | off-band (gas-service level) | gateway `validateContractCall` + trusted remote |
| WormholeGatewayAdapter | Guardian set | source-minted `sendId`; `_executed[chainId][sendId]` | `msg.value` relayer quote | relayer refund address | `msg.sender == relayer` + trusted source gateway |
| LayerZeroGatewayAdapter | Endpoint + DVN config | LZ `guid`; `_executed[chainId][guid]` | `msg.value` (`quote`); ZRO flag hardcoded off | refund to `msg.sender` (user) | dual-auth: endpoint + `peers[srcEid]` |
| L2ToL2 / L1ToL2 (OP) | OP protocol messengers | `keccak(chainid, nonce)` delivery ids (L2ToL2's sendId is the messenger msgHash); messenger self-dedup | none — both reject `msg.value` (`minGasLimit` is a stored relay tunable, L1↔L2) | n/a | `crossDomainMessageContext()` / counterpart + messenger |
| ZetaChainGatewayAdapter | ZetaChain TSS/observers (hub) | `keccak(chainid, nonce)` ids; source-chain cross-check in `onCall`; registered app map | `msg.value` | `RevertOptions.abortAddress = msg.sender` | `msg.sender == gateway` + registered app + fail-closed source check |
| HyperlaneGatewayAdapter | Mailbox + ISM (default ISM v1) | envelope nonce `sendId` (no protocol id in `handle`); Mailbox `delivered()` protocol guard | `msg.value` (`quoteDispatch`), synthesized `StandardHookMetadata` | IGP refund to the **user** | dual-auth: mailbox + `trustedRemotes[domainToChainId[origin]]` |
| HyperbridgeGatewayAdapter | **Consensus/state proofs** (ISMP coprocessor); permissionless relayers | protocol nonce dedup `keccak(source, nonce)`; envelope `sendId` | **ERC-20 `feeToken`** (`perByteFee × body + relayerFee`), live-read, pull/approve/reset/sweep | `DispatchPost.payer = user` (timeout refunds); `onPostRequestTimeout` notification | host + known source machine + trusted origin module; 4 unused hooks revert |
| CCTPBridgeAdapter | Circle Iris attesters + denylist | Circle nonce (transmitter) | none at source (full amount burned; fee deducted at destination mint, `maxFee`-capped) | n/a (burn is final) | permissionless `relayMessage` → transmitter verifies attestation |
| AcrossBridgeAdapter | Relayer fronts + UMA optimistic settlement | no receiveId (intent); refund-after-`fillDeadline` | relayer fee inside `outputAmount` delta | **`depositor = user`** (expired-deposit refunds) | inbound `handleV3AcrossMessage`: SpokePool only, **not** an authenticated message |
| StargateBridgeAdapter | Stargate pools on LZ rails | LZ `guid` (outbound-only for Lattice) | `msg.value` LZ fee (`quoteSend`) | **`refundAddress = user`**; dust sweep (`amountSentLD` truncation) | n/a (pool is the LZ receiver) |
| SuperchainETHBridgeAdapter | OP interop predeploys | messenger msgHash | none | n/a | n/a (outbound-only) |
| AggregatorExecAdapter (LiFi/Relay) | quote APIs + allow-listed routers; solvers (Relay) | none — no completion signal | per-quote (`msg.value` and/or input token) | delta sweeps return every leftover to the caller | n/a (outbound-only; Relay `refundTo`-to-diamond is swept to the user) |
| StarknetGatewayAdapter | Starknet L1↔L2 core (proofs) | L2→L1 **counter** (N consumes = N sends); msgHash + initiator record | `msg.value` escrowed, **never refunded** (cancel included) | initiator-gated 2-step cancellation (fee still burned) | core contract consumes only messages addressed to the diamond + trusted L2 sender |

## 3. Suite-wide conventions (enforced, not aspirational)

- **Source-minted nonce sendIds** — where a protocol exposes no usable message id to the receiver
  (OP messengers, ZetaChain `onCall`, Hyperlane `handle`, Hyperbridge envelopes), the wire envelope
  carries a monotonic source nonce and `sendId = keccak256(abi.encode(block.chainid, nonce))`
  (receive-side recomputed from the *authenticated* source chainId). Wormhole predates the keccak
  form: its envelope ships the raw counter id itself, de-duplicated under the authenticated source
  chainId (`_executed[chainId][sendId]`). Protocol-level replay guards
  (Mailbox `delivered`, host commitment uniqueness) are treated as the primary defense; the adapter
  map is convention-level defense-in-depth.
- **ERC-7930 interoperable addressing everywhere** — 20-byte EVM via `InteroperableAddress.formatEvmV1`;
  non-EVM via `NonEvmAddress`: `parseV1ToBytes32` (canonical-width enforced; CCTP `mintRecipient`,
  Across recipients) and `parseV1ToFelt252` (`< FIELD_PRIME`, Starknet). eip-155 destinations are
  **fail-closed cross-checked** against the declared chain reference (`AcrossDestinationMismatch`
  class); Hyperbridge state-machine ids derive internally (`bytes("EVM-<chainId>")`), never caller-supplied.
- **Refunds go to the user, never the diamond** — the recurring fund-stranding trap, caught at spec
  time in three protocols: Across `depositor`, Stargate `refundAddress`, Hyperbridge `payer` (each
  with a dedicated regression test). Any new adapter must identify its refund beneficiary field first.
- **Token/fee hygiene** — `BridgeFungibleLib.pullExact` (rejects fee-on-transfer) → `AdapterBaseLib.forceApprove(exact)`
  → protocol call → `forceApprove(0)` → snapshot-**delta** leftover sweep (pre-existing diamond
  balances are provably untouchable; Stargate dust and Hyperbridge fee-token under-pulls covered).
- **Fail-loud identity admin, updatable tunables** (post-#106 rule) — chain/domain/eid/pool identity
  registers exactly once, both map directions guarded; gas/fee/remote tunables stay updatable.
  Config cross-checks fail closed (Axelar encodings, Stargate-vs-LZ eid).
- **ERC-165 precomputed map slots** (see `CLAUDE.md`) + external-source attribution on every
  derived file; the `supportsInterface` tests recompute at runtime and have caught four stale
  constants across the epic.
- **Storage discipline** — ERC-7201 namespaces registered in `STORAGE_REGISTRY.md`, guarded
  append-only by `script/upgrades/check-storage-layout.sh` (fails loudly on vacuous sections),
  slot-verified + uniqueness-swept in `StorageSlotVerificationTest`.
- **EIP-170 awareness** — `ChainRegistry` carries 10 inlined fan-out libs at 262 B margin;
  `test_ChainRegistryFacetFitsEip170` guards the ceiling in CI, and the documented plan for an
  11th adapter is a dedicated `ChainFanOut` facet split.

## 4. Composition: OpenBridge, CrosschainLink, ChainRegistry

- **`ERC7786OpenBridge`** fans one message across M enrolled gateways and executes at N-of-M
  attestations (content-keyed trackers, one-shot execution). `setMinDirectCoverage(k)` (0 = off)
  hard-refuses destinations whose **direct** registry coverage is below `k` — hub-routed coverage
  (ZetaChain via the ZEVM) never counts. Aurora is the M=2 showcase (`script/config/EnableAurora.s.sol`).
- **`CrosschainLink`** authorizes exactly **one gateway per source chain** and tag-dispatches inbound
  payloads (`FUNGIBLE_BRIDGE_TAG` → the bridge libs). This is what makes cross-adapter replay a
  non-issue: a second transport is rejected at auth, or counts as an OpenBridge attestation.
- **`ChainRegistry.addEvmChain(cfg)`** is the one-action admin fan-out: registers the chain identity
  (canonical eip-155 reference enforced), records native ids + gateway coverage, and writes each
  enabled adapter's hot-path maps **via direct internal lib calls** (the admin's `msg.sender` flows
  through every `checkRole`; external self-calls are banned). Token bridges and gateways NOT cut
  into the diamond must have their sections left disabled (documented; the writes would land in
  unread storage). Never routed: CCTP/Across/Stargate/exec-configs through OpenBridge or CrosschainLink.

## 5. Off-chain dependency matrix (what must run for liveness)

| Adapter | Off-chain dependency | Failure mode if absent |
|---|---|---|
| CCIP | Chainlink DON + executors | messages never delivered |
| Axelar | validator set + relayer (or gas-service top-up) | stuck at gateway approval |
| Wormhole | guardians + delivery relayer | VAA never delivered |
| LayerZero | DVNs + executor (per-dest gas config) | blocked verification / undelivered |
| Hyperlane | validators (ISM) + permissionless relayer | unverified / undelivered; **self-relay possible** |
| ZetaChain | TSS signers + observer set (hub liveness) | hub never forwards; `onRevert` path also depends on it |
| Hyperbridge | coprocessor consensus + permissionless proof relayers | proofs never submitted; **self-relay possible**; timeouts refund `payer` |
| OP L2↔L2 / L1↔L2 | permissionless `relayMessage` driver (pre-mainnet interop) | sent-but-unrelayed; anyone can relay |
| CCTP | Circle Iris attestation service (+ any keeper calling `relayMessage`) | burn without mint until attested; `relayMessage` is permissionless once attested |
| Across | relayer fill + UMA optimistic settlement | no fill → refund to `depositor` after `fillDeadline` |
| Stargate | LZ infra + (bus mode) bus drivers — taxi-only in v1 | delivery delayed/stuck at LZ layer |
| LI.FI / Relay | quote APIs; Relay solvers + settlement oracle | **no on-chain completion signal either way** — off-chain reconciliation is mandatory |
| Starknet | L1→L2: sequencer consumption; L2→L1: a driver calling `consumeMessage` | L1→L2 cancellable after ~5 days (fee burned); L2→L1 sits consumable forever |

## 6. Deferred surfaces (deliberate, with owners in #77)

- LayerZero **OFT token track** (separate rail; Stargate covers pooled OFT-style transfers).
- Hyperlane **custom ISM** (additive: implement `ISpecifiesInterchainSecurityModule` later; default ISM v1).
- Stargate **bus mode** (`oftCmd`), **`composeMsg`/`lzCompose`**, and **native pool** (`msg.value` fee/amount mixing).
- Across inbound consumers: `handleV3AcrossMessage` is emit-only; the event is **not** an
  authenticated message (any party can originate a deposit at the diamond) — consumers must verify
  provenance independently.
- Hyperbridge **GET requests** (proof-verified cross-chain state reads — a new primitive), and the
  **native-with-swap** fee path (Q13).
- ZetaChain universal-app hop standardization + a suite-wide revert/refund ERC-7786 attribute (Q8;
  `onPostRequestTimeout` and `RevertOptions` are the two live inputs to that design).
- NEAR native via Rainbow Bridge (GPL-3.0; separate connector).

## 7. Testing

Every adapter ships: real-diamond unit tests assembled from its production deploy recipe (no
flattened mocks), a canonical-signature protocol mock, regression tests for its specific fund
traps, and membership in the 10-adapter `ChainFanOutTest` composability diamond. Fork smoke tests
(`test/fork/*Fork.t.sol`, env-gated on `MAINNET_RPC_URL` — skipped when unset) exercise one
representative happy path per settlement family against live mainnet contracts:
`CCTPBridgeAdapterFork` (burn), `LayerZeroGatewayAdapterFork` (gateway send),
`AcrossBridgeAdapterFork` (intent deposit), `StarknetGatewayAdapterFork` (L1→L2 escrow).

```bash
# everything (fork tests skip without RPC)
forge test
# fork smoke tests
export MAINNET_RPC_URL=<url>
forge test --match-path "test/fork/*Fork.t.sol"
```

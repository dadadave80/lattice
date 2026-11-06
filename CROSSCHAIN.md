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
| **Token rail** | Moves value, not messages. Three settlement models — **burn/mint attested** (CCTP), **intent/optimistic** (Across), **pooled-liquidity credits** (Stargate) — plus the gateway-routed `BridgeERC20`/`BridgeERC7802` (`FUNGIBLE_BRIDGE_TAG`) and native-ETH `SuperchainETHBridgeAdapter` | CCTPBridgeAdapter, AcrossBridgeAdapter, StargateBridgeAdapter (+ optional StargateBusBridgeAdapter), BridgeERC20, BridgeERC7802, SuperchainETHBridgeAdapter |
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
| ZetaChainGatewayAdapter | ZetaChain TSS/observers (hub) | `keccak(chainid, nonce)` ids; source-chain cross-check in `onCall`; registered app map | exact `msg.value` accepted by configured gateway (may be zero) | caller addresses by default; per-message explicit nonzero recovery addresses | `msg.sender == gateway` + registered app + fail-closed source check |
| HyperlaneGatewayAdapter | Mailbox + ISM (default ISM v1) | envelope nonce `sendId` (no protocol id in `handle`); Mailbox `delivered()` protocol guard | `msg.value` (`quoteDispatch`), synthesized `StandardHookMetadata` | IGP refund to the **user** | dual-auth: mailbox + `trustedRemotes[domainToChainId[origin]]` |
| HyperbridgeGatewayAdapter | **Consensus/state proofs** (ISMP coprocessor); permissionless relayers | protocol nonce dedup `keccak(source, nonce)`; envelope `sendId` | Zero value: live **ERC-20 `feeToken`** pull/approve/reset/sweep; positive value: bounded native exact-output swap | Unused native delta to caller; `DispatchPost.payer = user` (timeout **relayer feeToken** refund only); `onPostRequestTimeout` notification | host + known source machine + trusted origin module; 4 unused hooks revert |
| CCTPBridgeAdapter | Circle Iris attesters + denylist | Circle nonce (transmitter) | none at source (full amount burned; fee deducted at destination mint, `maxFee`-capped) | n/a (burn is final) | permissionless `relayMessage` → transmitter verifies attestation |
| AcrossBridgeAdapter | Relayer fronts + UMA optimistic settlement | no receiveId (intent); refund-after-`fillDeadline` | relayer fee inside `outputAmount` delta | **`depositor = user`** (expired-deposit refunds) | inbound `handleV3AcrossMessage`: SpokePool only, **not** an authenticated message |
| StargateBridgeAdapter | Stargate pools on LZ rails | LZ `guid` (outbound-only for Lattice) | `msg.value` LZ fee (`quoteSend`) | **`refundAddress = user`**; dust sweep (`amountSentLD` truncation) | n/a (pool is the LZ receiver) |
| StargateBusBridgeAdapter (optional companion) | Same registered Stargate pools + upstream drivers/LZ | Source queue ticket (zero valid); later upstream `BusDriven` GUID | **exact** quoted native bus fare | no routine surplus; token dust uses the same isolated delta sweep | n/a; enqueue is not delivery |
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
- **EIP-170 awareness** — `ChainRegistry` carries 10 inlined fan-out libs in 18,838 runtime bytes,
  a 5,738 B margin (Foundry 1.9.0, solc 0.8.36, Cancun, CI profile);
  `test_ChainRegistryFacetFitsEip170` guards the ceiling in CI, and the documented plan for an
  11th adapter is a dedicated `ChainFanOut` facet split.

### ZetaChain per-message recovery options

Pass a single `abi.encodeCall(IZetaChainGatewayAttributes.revertOptions, (options))` in `attributes`.
The adapter accepts canonical ABI encoding only, rejects duplicate or unknown attributes, requires
nonzero `revertAddress` and `abortAddress`, and caps `onRevertGasLimit` at 2,000,000 (zero is valid).
`GatewayEVM.call` forbids `callOnRevert=true`, so these options do **not** request an `onRevert` callback.
Without an attribute, both addresses remain `msg.sender`, revert data is empty, and the configured
default gas applies. The attribute is an encoding interface, not an extra selector on the diamond.

For an override, `options.revertMessage` becomes
`abi.encode(senderInterop, recipientInterop, userRevertData, outboundNonce)` using the actual caller.
The normal wire message keeps its existing format. Their combined encoded length must not exceed
2,880 bytes. A terminal abort consumer must authenticate its protocol caller and the protocol's
source adapter and chain context **before** trusting this envelope; decoding it alone provides no
authentication. The caller is responsible for choosing recovery addresses it controls on the
appropriate chains. Lattice provides no recovery hook or promise of refund delivery.

The adapter forwards exactly the current call's `msg.value`; pre-existing diamond funds are untouched.
It does not quote or refund fees. The pinned upstream gateway makes the first action free and rejects
positive value for it; other deployments or later actions may differ. A fee or gateway rejection
reverts the entire send, including the nonce. See [ADR 0028](docs/adr/0028-zetachain-message-recovery-options.md)
and the [pinned upstream validation](https://github.com/zeta-chain/protocol-contracts/blob/48ecdbcc4c30a8e8a7f2f5756b6a544b316670a0/contracts/evm/libraries/GatewayEVMValidations.sol).

## 4. Composition: OpenBridge, CrosschainLink, ChainRegistry

- **`ERC7786OpenBridge`** fans one message across M enrolled gateways and executes at N-of-M
  attestations (content-keyed trackers, one-shot execution). `setMinDirectCoverage(k)` (0 = off)
  hard-refuses destinations whose **direct** registry coverage is below `k` — hub-routed coverage
  (ZetaChain via the ZEVM) never counts. Aurora is the M=2 showcase (`script/config/EnableAurora.s.sol`).
  The bridge starts at threshold 0 and never executes an inbound message in that state, so the admin
  configures it in this order: `addGateway` (each gateway), then `setThreshold`, then `registerRemoteBridge`,
  which reverts with `ThresholdViolation` while the threshold is still 0.
- **`CrosschainLink`** authorizes exactly **one gateway per source chain** and tag-dispatches inbound
  payloads (`FUNGIBLE_BRIDGE_TAG` → the bridge libs). This is what makes cross-adapter replay a
  non-issue: a second transport is rejected at auth, or counts as an OpenBridge attestation.
  Tag routing does not let one diamond host several handler facets. The link always calls
  `processMessage` (`0x902d5027`) on the tag's handler, and BridgeERC20, BridgeERC7802, ERC20Crosschain
  and CrosschainTimelockHandler all export it, so cutting a second one reverts
  `CannotAddFunctionToDiamondThatAlreadyExists`. Point other tags at an external handler contract, or
  put them on a second link diamond. The three fungible handlers share `FUNGIBLE_BRIDGE_TAG` anyway, so
  in practice this rules out a fungible bridge plus `CrosschainTimelockHandler` on one diamond. See the
  [composition hazards](docs/guides/compose-your-own-diamond.md#composition-hazards).
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
| ZetaChain | TSS signers + observer set (hub liveness) | hub never forwards; recovery also depends on it; plain-message calls disable `onRevert` |
| Hyperbridge | coprocessor consensus + permissionless proof relayers | proofs never submitted; **self-relay possible**; timeouts refund `payer` |
| OP L2↔L2 / L1↔L2 | permissionless `relayMessage` driver (pre-mainnet interop) | sent-but-unrelayed; anyone can relay |
| CCTP | Circle Iris attestation service (+ any keeper calling `relayMessage`) | burn without mint until attested; `relayMessage` is permissionless once attested |
| Across | relayer fill + UMA optimistic settlement | no fill → refund to `depositor` after `fillDeadline` |
| Stargate | LZ infrastructure; optional bus companion also needs a bus driver and valid queue prefix | queue delay plus LZ delivery delay; no bounded completion or per-ticket cancellation |
| LI.FI / Relay | quote APIs; Relay solvers + settlement oracle | **no on-chain completion signal either way** — off-chain reconciliation is mandatory |
| Starknet | L1→L2: sequencer consumption; L2→L1: a driver calling `consumeMessage` | L1→L2 cancellable after ~5 days (fee burned); L2→L1 sits consumable forever |

## 6. Deferred surfaces (deliberate, with owners in #77)

- LayerZero **OFT token track** (separate rail; Stargate covers pooled OFT-style transfers).
- Hyperlane **custom ISM** (additive: implement `ISpecifiesInterchainSecurityModule` later; default ISM v1).
- Stargate **`composeMsg`/`lzCompose`**, **native drops**, and **native pools** (`msg.value` fee/amount mixing). The optional bus companion supports plain ERC20 enqueue only.
- Across inbound consumers: `handleV3AcrossMessage` is emit-only; the event is **not** an
  authenticated message (any party can originate a deposit at the diamond) — consumers must verify
  provenance independently.
- Hyperbridge **GET requests** (proof-verified cross-chain state reads — a new primitive).
- ZetaChain universal-app hop standardization + a **suite-wide** revert/refund ERC-7786 attribute (Q8;
  the Zeta-specific per-message `RevertOptions` encoding above is available; Hyperbridge timeout
  semantics remain distinct).
- NEAR native via Rainbow Bridge (GPL-3.0; separate connector).

## Hyperbridge native fee compatibility

Positive `msg.value` on `sendMessage` or `sendMessageWithFee` is the current call's native fee
budget. Zero value keeps the ERC-20 path. `quoteDispatchFee` still returns the total in fee-token
units, including the optional relayer fee. The adapter reads the compatible host's live fee token,
per-byte rate and `uniswapV2Router()`, then calls that router's exact-output `getAmountsIn` through
a normal call. A stateful quote wrapper is supported. Only the quoted native input is forwarded;
insufficient budgets revert. Native dispatch never pulls the caller's fee tokens.

This targets the [legacy host at commit 8dce6799](https://github.com/polytope-labs/hyperbridge/blob/8dce6799f1d376443ae40054b80e16d60ac447d1/evm/src/core/EvmHost.sol),
whose charge is `perByteFee(dest) * max(body.length, 32) + relayerFee`. The adapter's ABI envelope
always exceeds that floor. Newer host revisions with different fee/callback ABIs are outside this
compatibility claim. The configured host/router and the quote's execution behavior must be
authenticated for the target deployment; local mocks do not certify any public router or corridor.

The legacy host retains router surplus. The adapter therefore requires the host's native balance
to be unchanged across quoting and dispatch, reverting the whole send if surplus remains there.
Native returned directly to the adapter joins the unused current-call delta and is refunded to
the caller; pre-existing adapter balances stay untouched. A caller rejecting a nonzero refund
causes an atomic revert, including the dispatch and nonce. The canonical recipe needs no Receive
facet to forward a payable call's value; a nonstandard host returning bare native to the adapter
would also require an explicitly composed Receive route. A zero total skips the router and refunds
the whole budget. The native quote, dispatch and refund execute under the existing reentrancy guard.
The zero-value ERC-20 send path keeps its previous guard boundary: it can still be called during
these external interactions when the nested sender funds and approves its own fee tokens. Such a
send receives a distinct nonce and cannot spend the native budget or standing native balance.

`DispatchPost.payer` remains the caller. A timeout refunds only the relayer fee in the host's
fee token to that payer; it does not refund the protocol fee or reverse the native swap. The
adapter's timeout hook emits a notification. See [ADR 0029](docs/adr/0029-hyperbridge-native-fee-budgets.md).

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

## Optional Stargate bus enqueue

[`DeployStargateBusBridgeAdapter`](script/base/crosschain/DeployStargateBusBridgeAdapter.s.sol) adds the
[`StargateBusBridgeAdapter`](src/crosschain/layerzero/StargateBusBridgeAdapter.sol) companion alongside
the original taxi facet, with the same admin-configured ERC20 pools and chainId/eid map. The original
`DeployStargateBridgeAdapter` remains taxi-only with five cuts; the optional recipe has six. No new
namespace, mapping or authority is introduced. An existing configured diamond may add the companion
and register its separate ERC165 ID via an authorized
[ReinitMultiInit batch](docs/guides/compose-your-own-diamond.md#initialize-modules-during-an-upgrade).
Do not seed AccessControl again during that upgrade.

Call `quoteBusFee` with the existing `SendTokenParams`, then supply exactly that native fare to
`sendTokenBus`. Both paths construct the same single-zero-byte bus command and empty options/compose
payload. Quote does not reserve queue space, liquidity or a fare. Underpayment and overpayment fail
before token movement; the pool's charged fare, zero enqueue GUID/nonce and nonempty passenger data
are checked before success. The pool remains an admin-selected trust boundary. This policy avoids
Stargate's best-effort surplus refund path; the taxi API's whole-value forwarding is unchanged.

The result is a **queue ticket**, opaque passenger bytes, and the amounts locally settled by the pool.
Ticket zero is valid. Neither the result nor `StargateBusQueued` proves dispatch or destination receipt.
Retain passenger bytes and the route. Using the official ABI, resolve `tokenMessaging` from the source
pool's `getAddressConfig()` and monitor its `busQueues(dstEid).nextTicketId`. For the same
TokenMessaging contract and destination eid, **`nextTicketId > ticketId`** means that ticket has been
dispatched, not necessarily delivered; an earlier prefix moving is insufficient. Correlate the later upstream
`BusDriven` event for the actual LayerZero GUID.

The upstream `quoteDriveBus(dstEid, passengers)` and payable `driveBus` are permissionless, but require
an authenticated **contiguous prefix** from the current next ticket. A user's own ticket bytes may be
insufficient when earlier passengers are pending; obtain those bytes from upstream `BusRode` events.
Call upstream directly if choosing to drive; Lattice has no drive, cancel or refund facade and holds
no local queue ledger. Queue/planner/driver availability, current pool policy and LayerZero execution
can delay completion without a time bound. No per-ticket cancellation, expiry or user refund API is
present in the reviewed queue. Native drops, native pools and compose hooks remain outside this mode.

[ADR0030](docs/adr/0030-stargate-bus-companion.md) records the pinned v12 source and alternatives.
The independently authored local queue fixture verifies adapter behavior; it is not a claim of an
upstream deployment, public fork or broadcast test.

# Lattice on Hedera

Mount Hedera's system contracts as Diamond facets: hold and issue HTS tokens, verify ED25519 account
signatures, read the network exchange rate, draw a native random seed, and schedule your own future calls.
The contracts are unaudited. **No transaction here has been sent to a live Hedera network** — every
behaviour below that needs a signed transaction is still an assumption read from consensus-node source.
Read-only `eth_call`s against the public testnet relay HAVE been run; what they settled is marked confirmed
in [Verification status](#verification-status).

## The five modules

| Facet | Area | System contract | What it gives a diamond |
| --- | --- | --- | --- |
| `HTSAdapter` | `src/tokens/hedera/` | HTS `0x167` | The diamond as an HTS account: associate/dissociate itself, create fungible and non-fungible tokens it treasuries, mint, burn, transfer its own balance, and spend an allowance granted to it. |
| `HASSignatureVerifier` | `src/accounts/hedera/` | HAS `0x16a` | HIP-632 `isAuthorizedRaw` / `isAuthorized` as never-reverting views, and the `SignerType.HederaAccount` branch that lets a **Hedera ED25519 account own a Lattice smart account**. |
| `HederaExchangeRateAdapter` | `src/oracles/hedera/` | Exchange Rate `0x168` | Tinycent/tinybar conversion and a USD-cents helper for pricing HTS fees. The network's *fee* rate, refreshed roughly hourly — never a liquidation price feed. |
| `HederaPrngAdapter` | `src/oracles/hedera/` | PRNG `0x169` | A synchronous 32-byte seed with no request/callback round trip. The ordering node sees the seed first — do not use it where that matters. |
| `HSSAdapter` | `src/oracles/hedera/` | HSS `0x16b` | HIP-1215 scheduled contract calls and HIP-755 schedule authorization; the diamond pays for and admins what it schedules. |

None of the system contracts has bytecode. Every Lattice library reaches them with `call` or `staticcall`
and never `delegatecall` — a direct delegatecall from user code has been blocked since consensus node
v0.34.5 and halts the frame with `PRECOMPILE_ERROR`, burning the frame's gas.

HTS, HAS and HSS return `int64` **response codes** instead of reverting (`SUCCESS == 22`). Each library maps
the codes its module can produce to typed errors and everything else to a catch-all carrying the selector and
the raw code, so an integrator can always recover the network's own answer. A failed frame is treated as
`UNKNOWN` (21).

## The delegatable-key rule

This is the one Hedera fact that changes how you configure a token, and it exists **because** Lattice is a
diamond. It is also more subtle than it first appears — we measured it on testnet and the naive statement
of it is wrong.

A facet call is a `delegatecall` frame. When that frame calls HTS, the node passes
`hasParentDelegateCall = true`, which becomes `onlyDelegatableContractKeysActive`, and
`ActiveContractVerificationStrategy.decideForPrimitive` then returns `INVALID` for a plain `contractId`
key. So **wherever a `contractId` key is actually verified, it fails.** `HTSAdapterLib` therefore sets
`key.delegatableContractId = address(this)` on every key it creates, and that is the right call.

What is **not** true is the tempting shorter version — "a `contractId` key held by a diamond is dead and
fails with 326". On testnet (consensus node 0.76.3, 2026-09-12) a token whose supply key was
`contractId(<diamond>)` minted **successfully** from a facet, twice, including through the production
`HTSAdapter.mintToken` path (token `0.0.10506858`, supply 1000 → 1777).

The reason is **payer-key elision**, not activation. A relay-deployed contract's own account key is
`contractId(self)`. The dispatched child `TokenMint`'s synthetic payer is the diamond, so its payer key is
`contractId(<diamond>)` — byte-identical to that supply key — and `PreHandleContextImpl.requireKey` drops a
required key equal to the payer key. The supply key was never verified at all. A `delegatableContractId`
key is a different protobuf oneof (field 8 vs field 1), so it is *not* equal to the payer key: it really is
required, really is verified, and really does pass.

Keep using `delegatableContractId`, because it is the form that is verified-and-passes rather than merely
skipped, and because the elision does not cover:

- a diamond whose account key is not `contractId(self)` (e.g. created by a HAPI `ContractCreate` with an
  explicit ED25519 admin key) — there a `contractId` key is verified, and dies;
- a `contractId` nested inside a `KeyList` or `ThresholdKey` — not `.equals()` the payer key, so required;
- any key naming a contract other than the caller.

Those three are read from consensus-node source and are **not** measured — treat them as inference.

If you hand a diamond a token created elsewhere, update its keys to the delegatable form
(`updateTokenKeys`) rather than relying on the elision. Operations needing only the diamond's own account
authority — moving its own balance, associating itself — work regardless, because the diamond is the child
transaction's payer.

## Associate before you receive

A contract created by a top-level `EthereumTransaction` — which is everything `forge script` broadcasts — gets
`maxAutomaticTokenAssociations = 0`. A diamond created through `LatticeFactory` inherits the factory's 0.
So a diamond has **no** auto-association slots and must associate explicitly, from a facet, before it can
receive a token:

```solidity
IHTSAdapter(diamond).associateToken(token);   // HTS_MANAGER_ROLE
```

Dissociation fails with `TRANSACTION_REQUIRES_ZERO_TOKEN_BALANCES` (195, surfaced as `HTSNonZeroBalance`)
while any balance remains, and with `ACCOUNT_IS_TREASURY` (196, surfaced as `HTSAccountIsTreasury`) for a token
the diamond treasuries — the treasury seat is refused first, however empty the balance is.

Two consequences worth planning for: a diamond that is a token treasury or holds HTS tokens cannot be torn
down, and a diamond that is a token's auto-renew account takes on that token's renewal charges — so it must
hold HBAR. That is why `Receive` is in the `DeployHTSAdapter` recipe.

## Build with the Hedera profile

Hedera mainnet and testnet run **Cancun** (consensus node v0.76, `contracts.evm.version = v0.67`). Prague
arrives with v0.77, planned for October 2026. Solidity 0.8.36 and Foundry 1.8.1 default to `osaka`.

In practice 0.8.36 never emits a CLZ opcode unless you write one in Yul, so the runtime bytecode is the same
either way — but the **metadata is not**, so source verification on HashScan/Sourcify only reproduces if you
pin the setting. Build and deploy everything Hedera-bound under the dedicated profile:

```sh
FOUNDRY_PROFILE=hedera forge build --skip test script
```

Deploy with `forge create`, **not** `forge script` — see the relay note below for why the script path cannot
work on Hedera at all:

```sh
FOUNDRY_PROFILE=hedera forge create src/tokens/hedera/HTSAdapter.sol:HTSAdapter \
    --rpc-url hedera-testnet --account <keystore> --broadcast --legacy \
    --verify --verifier sourcify
```

The default profile is untouched and still targets `osaka`. Switch `[profile.hedera]`'s `evm_version` to
`"prague"` once v0.77 is live.

`hedera` (295) and `hedera-testnet` (296) are already named RPC aliases in `foundry.toml`; set
`HEDERA_RPC_URL` / `HEDERA_TESTNET_RPC_URL` in `.env`.

**`forge script` broke on Hedera in Foundry 1.8.x.** It works on 1.7.1 and fails on 1.8.1, so pin 1.7.1
for Hedera broadcasts until this is fixed upstream. The regression is in the fork backend, which 1.8.x pins
by block **hash** and then queries with an EIP-1898 object that no Hedera relay implements:

```
forge 1.7.1 -> eth_getTransactionCount(addr, "latest")                              exit 0
forge 1.8.1 -> eth_getTransactionCount(addr, {"blockHash": "0x671a…", ...})          -32602
               Invalid parameter 1: The value passed is not valid: [object Object].
```

Verified on 2026-09-12 with a script that deploys **nothing**, so it is the backend and not the script. On
1.8.1 no flag avoids it — `--legacy`, `--slow`, `--skip-simulation` (with and without `--broadcast`),
`--fork-block-number` (resolved to a hash anyway), `--no-storage-caching`, `--offline`, `--sender-nonce`,
`--unlocked`, `--sender` and `--estimate` were all rejected. Changing relay does not help either: a
QuickNode Hedera-testnet endpoint returns the byte-identical error with the same relay Request-ID format,
so this is `hiero-json-rpc-relay` behaviour, not one operator's.

Everything that does not open a fork backend is unaffected on **both** Foundry versions — `forge create`,
`cast send` / `call` / `mktx`, and `vm.rpc` inside a test (which is why the relay-backed fork test passes).
`--legacy` is worth passing as Hedera's native transaction form, but it is *not* what fixes this: `cast
mktx` signs cleanly in both legacy and EIP-1559 form, so the envelope was never the problem. `--slow` still
helps against rate limits.

This repo pins Foundry 1.8.1 for CI (`.github/actions/foundry-setup`). Running a Hedera broadcast therefore
means temporarily selecting 1.7.1 (`foundryup --use v1.7.1`) and switching back — a real tension with
AGENTS.md's "pin one version uniformly" rule that is worth resolving deliberately rather than by drift.

## Deterministic deployment: Arachnid, not CreateX

CreateX (`0xba5Ed099…ba5Ed`) is **not** deployed on Hedera. The Arachnid deterministic-deployment proxy
`0x4e59b44847b379578588920cA78FbF26c0B4956C` **is** (mainnet `0.0.6264020`, testnet `0.0.4283707`), so
`CreateXDeployer` routes `deployRaw`/`predictRaw` through it when CreateX is absent, and `BaseDeploy._facet`
prefers that path over plain CREATE.

Release facets on Hedera are therefore still deterministic and still permissionless, but they land at
**different addresses** than on CreateX chains: the Arachnid path is plain EIP-1014 with the proxy as deployer
and the raw salt, where CreateX additionally applies `keccak256(abi.encode(salt))`. See
`REGISTRY_DEPLOYMENTS.md`.

`LatticeFactory.deploy` uses a native `new Lattice{salt}()`, which is standard EIP-1014 (HIP-329) and works
unmodified. Hedera's EIP-6780 semantics never delete a pre-existing contract, so the metamorphic-redeploy
concern does not arise.

## What does not work on Hedera

- **`Account7702Diamond`.** EIP-7702 is HIP-1340, approved and implemented, but
  `contracts.codeDelegations.enabled = false` even on the v0.77 branch. Gate its recipe on chain id.
- **`SignerType.HederaAccount` on a non-Hedera chain.** `setHederaAccountSigner` refuses outright where HAS
  does not answer, and that refusal is load-bearing rather than defensive: a Lattice account is its own
  `DEFAULT_ADMIN_ROLE` holder, so the signer you install is the one every later admin call must satisfy —
  `setOwner`, the only route back to ECDSA, included. Arming a Hedera signer with no live HAS would make
  every signature `false` with no authority left able to undo it, stranding the account and its `diamondCut`
  upgrade path permanently. The check probes the system contract for a real answer rather than allowlisting
  chain ids, so it stays correct on previewnet, a Solo local network, and any future Hedera chain id.
- **P256 / WebAuthn signers.** Hedera has no secp256r1 precompile (EIP-7951 is an Osaka feature) and `0x100`
  there is a system account, so `SignerType.P256` and `SignerType.WebAuthn` return `false` unless the Solady
  fallback verifier contract is deployed on the chain. Use `SignerType.HederaAccount` instead — it is strictly
  better on Hedera, because HAS follows key rotation.
- **Safe v1.4.1.** Only v1.3.0 is on Hedera mainnet, and Hedera is absent from the `safe-deployments`
  registry, so `SafeDiamondCut` / `GovernedSafeDiamondCut` recipes must point at v1.3.0.
- **HIP-1028 token metadata keys** (Deferred) and **HIP-1195 hooks** (approved, disabled by default).
- **Fork tests that execute a system contract.** A Foundry fork fetches state over RPC and executes locally in
  revm; the relay reports `0xfe` as the code of `0x167` and nothing at all for `0x168`/`0x169`/`0x16a`/`0x16b`, so no
  HTS/HAS/HSS call executes on a plain fork — reads included. `test/fork/HTSAdapterFork.t.sol` asserts that
  local shape and uses `vm.rpc("eth_call", …)` to hand anything that must really execute to the relay, where
  the mirror node simulates it. Worse, the public hashio relay cannot be forked at all: Foundry fetches
  accounts with an EIP-1898 block-parameter object and hashio rejects it, aborting the run with a database
  error no `try`/`catch` can turn into a skip. The one test that forks therefore sits behind its own
  `HEDERA_TEST_FORK=true` opt-in, so setting `HEDERA_TEST_TOKEN` alone gives you the relay-backed test
  (which passes against hashio today) plus a skip — never a spurious failure.

## Verification status

Nothing below has been executed on a live Hedera network. The semantics marked **assumed** are read from
consensus-node source and HIP text but are not yet confirmed on-chain; `script/config/hedera/ProbeHedera.s.sol`
exists to settle them, and is deliberately not broadcast by CI.

| # | Behaviour | Status |
| --- | --- | --- |
| 1 | `associateToken` from a facet, then an inbound transfer | still assumed — the probe's association target was its own treasury token, so it could only ever return 194 |
| 2 | `createFungibleToken` with `delegatableContractId` keys, then `mintToken` from a facet | **confirmed live, 2026-09-12** — token `0.0.10506856` created by a facet with the diamond as treasury and delegatable admin+supply keys; `HTSAdapter.mintToken` minted 500. Excess-`msg.value` refund still unmeasured |
| 3 | The same create with a `contractId` key → 326 | **REFUTED live, 2026-09-12** — minted successfully instead (token `0.0.10506858`, supply 1000 → 1777). The control was degenerate: the key was byte-identical to the diamond's own account key and got elided before verification. See "The delegatable-key rule" |
| 4 | HTS getters and both HAS auth functions staying `view` (`staticcall`-safe) | partly confirmed — `isToken` answers `(22, true)` through the relay's `eth_call` (2026-09-12); whether a diamond's own `view` facet function may `staticcall` it *inside a transaction* is still assumed |
| 5 | `redirectForAccount(address(this), …)` giving a diamond unlimited auto-associations | partially measured — the frame succeeded and returned 32 bytes decoding to `15`, so `0x16a` does expose the entrypoint; whether the association limit actually changed is unverified, and `redirectForAccount` stays out of the vendored interface until it is |
| 6 | `scheduleSelfCall` firing with `msg.sender == address(this)` | still assumed — the attempt reverted `HSSInvalidExpiry`: the probe computed the expiry from the fork clock, 125 s behind consensus time |
| 7 | ED25519 verification through `isAuthorizedRaw` from the ERC-1271 path | assumed |
| 8 | Sourcify verification reproducing under `FOUNDRY_PROFILE=hedera` | assumed |
| — | System-contract code shape, **both** networks: `eth_getCode(0x167)` is `0xfe`; `0x168`, `0x169`, `0x16a` and `0x16b` are all empty. (The research brief said `0x16b` also answers `0xfe` — it does not.) | **confirmed live, 2026-09-12** |
| — | CreateX `0xba5Ed099…ba5Ed` has no code on Hedera mainnet or testnet | **confirmed live, 2026-09-12** |
| — | The Arachnid proxy `0x4e59b448…956C` has code on Hedera mainnet **and** testnet, byte-identical to `test/helpers/ArachnidProxy.RUNTIME` | **confirmed live, 2026-09-12** |
| — | `forge script` cannot broadcast to Hedera at all — no flag combination, and no relay: the fork backend queries `eth_getTransactionCount` with an EIP-1898 `{blockHash,requireCanonical}` object and both hashio and a QuickNode endpoint reject it identically. `forge create`, `cast` and `vm.rpc` all work | **confirmed live, 2026-09-12** |

To run the probes you need a funded testnet account: set `HEDERA_TESTNET_RPC_URL` and `HEDERA_TESTNET_PK`
in `.env` and fund the derived address from the Hedera portal faucet. Record each outcome in the relevant
module's natspec as `@dev Verified on testnet <date>, consensus node vX.Y` — the node version matters, because
v0.77 changes gas accounting.

## Out of scope for now

HSS, exchange-rate and PRNG recipes and tests (Phase 2, gated on probe 6 — and note the known
`scheduleSelfCall` job-stranding limitation documented on `IHSSAdapter`: do not build a recurring job on it
until that is fixed); custom fees, KYC/freeze/pause/wipe,
HIP-904 airdrops, `hedera-forking` facade tests and a Solo local-node CI job (Phase 3). The skeleton files for
the Phase 2 modules compile and are inventoried, but they have no recipes or tests yet.

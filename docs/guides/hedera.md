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
diamond.

A facet call is a `delegatecall` frame. When that frame calls HTS, the consensus node passes
`hasParentDelegateCall = true`, which becomes `onlyDelegatableContractKeysActive`. The effect is absolute:

- a token key of the form `contractId = <diamond>` is **dead** — it never activates, and the operation fails
  with `INVALID_FULL_PREFIX_SIGNATURE_FOR_PRECOMPILE` (326), surfaced as `HTSKeyNotActive`;
- a token key of the form `delegatableContractId = <diamond>` activates normally.

Every key `HTSAdapterLib` sets on a token it creates therefore uses `key.delegatableContractId = address(this)`.
If you hand a diamond a token that was created elsewhere, update its keys to the delegatable form first
(`updateTokenKeys`) or the diamond will not be able to operate it.

Operations that need only the diamond's own account authority — moving its own balance, associating itself —
work regardless, because the diamond is the child transaction's payer.

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
FOUNDRY_PROFILE=hedera forge script script/base/tokens/DeployHTSAdapter.s.sol \
    --sig "run(address)" <ADMIN> \
    --rpc-url hedera-testnet --account <keystore> --broadcast --slow \
    --verify --verifier sourcify
```

The default profile is untouched and still targets `osaka`. Switch `[profile.hedera]`'s `evm_version` to
`"prague"` once v0.77 is live.

`hedera` (295) and `hedera-testnet` (296) are already named RPC aliases in `foundry.toml`; set
`HEDERA_RPC_URL` / `HEDERA_TESTNET_RPC_URL` in `.env`. Hashio is rate-limited — pass `--slow` for
development and use a provider key for anything repeated.

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
| 1 | `associateToken` from a facet, then an inbound transfer | assumed |
| 2 | `createFungibleToken` with `delegatableContractId` keys, then `mintToken` from a facet; whether excess `msg.value` on create is refunded | assumed |
| 3 | The same create with a `contractId` key → 326 | assumed |
| 4 | HTS getters and both HAS auth functions staying `view` (`staticcall`-safe) | partly confirmed — `isToken` answers `(22, true)` through the relay's `eth_call` (2026-09-12); whether a diamond's own `view` facet function may `staticcall` it *inside a transaction* is still assumed |
| 5 | `redirectForAccount(address(this), …)` giving a diamond unlimited auto-associations | unknown — experiment |
| 6 | `scheduleSelfCall` firing with `msg.sender == address(this)` | assumed — the load-bearing HSS design assumption |
| 7 | ED25519 verification through `isAuthorizedRaw` from the ERC-1271 path | assumed |
| 8 | Sourcify verification reproducing under `FOUNDRY_PROFILE=hedera` | assumed |
| — | System-contract code shape, **both** networks: `eth_getCode(0x167)` is `0xfe`; `0x168`, `0x169`, `0x16a` and `0x16b` are all empty. (The research brief said `0x16b` also answers `0xfe` — it does not.) | **confirmed live, 2026-09-12** |
| — | CreateX `0xba5Ed099…ba5Ed` has no code on Hedera mainnet or testnet | **confirmed live, 2026-09-12** |
| — | The Arachnid proxy `0x4e59b448…956C` has code on Hedera mainnet **and** testnet, byte-identical to `test/helpers/ArachnidProxy.RUNTIME` | **confirmed live, 2026-09-12** |

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

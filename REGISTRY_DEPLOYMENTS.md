# Registry Deployments

This file is the **canonical reference** for how Lattice releases land on-chain: the deterministic
address scheme of the [`LatticeRegistry`](src/LatticeRegistry.sol) singleton, the
[`LatticeFactory`](src/LatticeFactory.sol), and every
[`FacetInventory`](script/lib/FacetInventory.sol) facet, all deployed through the canonical
**CreateX** singleton — or, on a chain CreateX never reached, through the [Arachnid
proxy](#chains-without-createx-the-arachnid-fallback) — by
[`script/deploy/DeployRelease.s.sol`](script/deploy/DeployRelease.s.sol). Every address below is
reproducible offline from a salt string and an initcode hash — nothing depends on who broadcasts or
what nonce they are at. The one thing that does vary per chain is **which** of the two deterministic
deployers that chain has.

## The CreateX singleton

Release deployments go through **CreateX**
([pcaversaccio/createx](https://github.com/pcaversaccio/createx)), deployed as a singleton at the
**same address on every supported chain**:

```
0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed
```

Where that address has no code, the release falls back to the [Arachnid
proxy](#chains-without-createx-the-arachnid-fallback); `DeployRelease.release()` refuses to run only
on a chain that has **neither** deployer. For local/test runs, etch
[`test/helpers/MockCreateX.sol`](test/helpers/MockCreateX.sol) — a faithful mock of the `_guard`
transform and the CREATE2/CREATE3 derivations — at the CreateX address first (see
[`test/unit/DeployReleaseTest.t.sol`](test/unit/DeployReleaseTest.t.sol)).

## Salt formulas

Salts are **raw protocol salts** — human-readable strings hashed with keccak256, containing no
deployer address and no chain id:

| Contract | Salt formula | Value |
| --- | --- | --- |
| `LatticeRegistry` | `keccak256("lattice.LatticeRegistry")` (deploy-once singleton, versionless) | `0xc78231000c48b308a55c9ed0de492d4ee766bc920c611d52ef984a4d9baa3a9c` |
| `LatticeFactory` | `keccak256("lattice.LatticeFactory")` (versionless) | `0x23ac1297d420218079953740f312f2c5385edfea1f817c984d2e6effea132efe` |
| every facet | `keccak256("lattice.<Name>.<version>")`, e.g. `keccak256("lattice.ERC20.0.1.0")` | per facet/version (ERC20 0.1.0: `0x938c2ea7277871ff5f71c989637ac4c6733ed43924e245cd91bc1e7363db2078`) |

`<Name>` is the facet's contract name exactly as listed in
[`FacetInventory`](script/lib/FacetInventory.sol) (also the source of the parity gate — the same
string, prefixed `lattice.`, is the facet's registry name key). `<version>` is the release semver
string (`"0.1.0"`), the same value that packs to the registry's `uint64` version key
(`major<<48 | minor<<24 | patch`). The inventory's 105 entries include the four **diamond-lib core
facets** (`DiamondCutFacet`, `DiamondLoupeFacet`, `ERC165Facet`, `OwnableFacet` — ERC-8153 since
diamond-lib v0.2.0); they are release-versioned by the same `lattice.<Name>.<version>` scheme as
every Lattice facet, so e.g. the loupe's registry key is `keccak256("lattice.DiamondLoupeFacet")`.

**Factory loupe requirement.** `LatticeFactory.deploy` refuses to assemble an un-introspectable
diamond: every fresh deploy's cuts must cover the four EIP-2535 loupe selectors (`facets()`,
`facetFunctionSelectors(address)`, `facetAddresses()`, `facetAddress(bytes4)`) in some `Add` cut, or
it reverts `LatticeFactory__MissingLoupeCoverage(missingSelector)`. Coverage is selector-based —
any facet may provide it; the registered `lattice.DiamondLoupeFacet` entry is the one-line way. The
CUT facet remains optional (immutable-by-design diamonds are legal).

## Address derivation

CreateX **guards** every salt before use. A raw salt — one whose first 20 bytes are neither the
caller nor zero, which every keccak-derived salt above is (up to a negligible 2^-160 accident) —
takes the deployer- and chain-independent branch:

```
guardedSalt = keccak256(abi.encode(salt))
```

and the deployed address is the standard CREATE2 derivation **from the CreateX singleton**:

```
address = keccak256(0xff ++ 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed ++ guardedSalt ++ keccak256(initCode))[12:]
```

So an address depends on exactly three things: the CreateX singleton (constant everywhere), the salt
string, and the **initcode**. Same salt + same initcode ⇒ same address on every chain.
[`CreateXDeployer.deployRaw`/`predictRaw`](script/lib/CreateXDeployer.sol) implement the deploy and
the guard-reproducing prediction (CreateX's public `computeCreate2Address` does **not** re-guard the
salt it is given — `predictRaw` applies `keccak256(abi.encode(salt))` itself).

## Chains without CreateX: the Arachnid fallback

CreateX is not everywhere. **Hedera** is the motivating case: the singleton is deployed on neither
Hedera mainnet nor testnet. What those chains do have is the **Arachnid deterministic-deployment
proxy** ([Arachnid/deterministic-deployment-proxy](https://github.com/Arachnid/deterministic-deployment-proxy),
Hedera mainnet entity `0.0.6264020`, testnet `0.0.4283707`), itself at one address everywhere:

```
0x4e59b44847b379578588920cA78FbF26c0B4956C
```

So on a chain where CreateX has no code and that proxy does,
[`CreateXDeployer.deployRaw`/`predictRaw`](script/lib/CreateXDeployer.sol) route the raw-salt path
through the proxy instead: its 69-byte runtime takes `salt ++ initCode` as raw calldata, CREATE2-deploys,
and returns the bare 20-byte address. CreateX wins wherever both have code, so **no existing chain's
addresses move**. The fallback covers the raw-salt release path only — there is no CREATE3 equivalent,
so the adapters' `deploy`/`predict` still require CreateX itself.

The proxy applies **no guard** to the salt it is handed, so its derivation is the plain EIP-1014 form
over the **raw, unguarded** salt, with the proxy as deployer:

```
address = keccak256(0xff ++ 0x4e59b44847b379578588920cA78FbF26c0B4956C ++ salt ++ keccak256(initCode))[12:]
```

Compare with the CreateX form above, which hashes the salt first (`keccak256(abi.encode(salt))`) and
uses the CreateX singleton as the deployer. **Two deployers, two address families**: the same facet,
built from the same source at the same version, lands at one address on every CreateX chain and at a
different one on every Arachnid-only chain. That second address is no weaker — it is equally
deterministic, equally deployer-independent, equally permissionless to complete, and equally committed
to `keccak256(initCode)`, so everything the sections above claim still holds of it. What is lost is
only the symmetry *between* the families: `lattice.ERC20.0.1.0` has one address on
Ethereum/Base/Arbitrum/… and another on Hedera. Read a release's addresses off that chain's manifest
rather than assuming the CreateX ones.

A chain with **neither** deployer has no deterministic path at all. `DeployRelease.release()` keeps
refusing it (naming both addresses), and the `script/base/` recipes fall back to plain `CREATE` there
([`BaseDeploy._facet`](script/base/BaseDeploy.s.sol)) — a working diamond at an address nobody can
predict, which is fine for a throwaway local deployment and useless for a release. Note that Anvil and
Foundry's test EVM **pre-deploy** the Arachnid proxy (it is Foundry's own default CREATE2 deployer), so
a local run takes the proxy path unless that address is etched empty;
[`test/helpers/ArachnidProxy.sol`](test/helpers/ArachnidProxy.sol) carries the fetched runtime for
tests that need to put it somewhere it is missing.

## Why CREATE2 here (and CREATE3 for the adapters)

The release path deliberately uses **CREATE2, not CREATE3**, because the CREATE2 address **commits
to the initcode**:

- **Permissionless completion is squat-proof.** A release run that dies halfway leaves predictable
  empty addresses. Because each address commits to `keccak256(initCode)`, ANYONE may finish (or
  front-run) the deployment — and the only bytecode that can ever occupy a canonical address is the
  canonical bytecode. A squatter "attacking" a release just pays our gas bill.
- **Anyone can verify a release offline.** Recompute the address from the salt string and the
  published initcode hash (manifest, below); if the on-chain code is there, it is bit-for-bit the
  code the address committed to.

Contrast with the **CREATE3 path** ([`CreateXDeployer.deploy`/`predict`](script/lib/CreateXDeployer.sol),
used by [`DeployAdapters`](script/deploy/DeployAdapters.s.sol)): its address is initcode-independent
(stable across compiler/bytecode changes) but **sender-guarded + cross-chain-redeploy-protected** —
the `0x01` protection byte folds `block.chainid` into the guarded salt, so those deployments land at
a **different address per chain** and only the pinned deployer can realize them. Two tools, two jobs:
CREATE3 = "this deployer's slot, per chain, code may evolve"; raw-salt CREATE2 = "this exact code,
same address everywhere, anyone may finish the job".

## What changes an address

- **Which deterministic deployer the chain has.** CreateX and the Arachnid proxy derive different
  addresses from identical inputs (see [the fallback](#chains-without-createx-the-arachnid-fallback)).
  This is the only input that varies by chain rather than by release.
- **The initcode.** `initCode = creationCode ++ abi.encode(constructor args)`, and `creationCode` is
  a function of the source **and the compiler configuration** (solc version, optimizer settings,
  metadata). A release therefore only reproduces across machines/chains when built with the pinned
  compiler config — build with this repo's `foundry.toml` profile at the release tag, never a locally
  drifted toolchain.
- **The registry's `owner` constructor arg.** It is ABI-encoded into the registry's initcode, so the
  registry only lands at the same address on every chain if the **same owner address** is passed on
  every chain — the mainnet multisig must exist at one address on all target chains (or the
  cross-chain address symmetry for the registry, and with it the factory, is lost).
- **The factory's `registry` arg** — automatically identical everywhere once the registry is.
- **The salt string** — a facet rename or version bump re-derives that facet's salt (and its registry
  name key), by design: every release version gets fresh facet addresses.

## Recomputing / verifying an address with cast

```bash
# 1. the raw salt
SALT=$(cast keccak "lattice.ERC20.0.1.0")

# 2. CreateX's raw-salt guard: keccak256(abi.encode(salt))
GUARDED=$(cast keccak $(cast abi-encode "f(bytes32)" $SALT))

# 3. the initcode hash (facets have no constructor args; append abi-encoded args otherwise)
INITHASH=$(cast keccak $(forge inspect src/tokens/ERC20/ERC20.sol:ERC20 bytecode))

# 4. the CREATE2 address, deployed by the CreateX singleton
cast create2 --deployer 0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed --salt $GUARDED --init-code-hash $INITHASH
```

For the registry/factory, step 3 appends the constructor arg:
`cast keccak $(cast concat-hex $(forge inspect src/LatticeRegistry.sol:LatticeRegistry bytecode) $(cast abi-encode "f(address)" $OWNER))`.

On an [Arachnid-only chain](#chains-without-createx-the-arachnid-fallback) the same facet is two steps
instead of four — the proxy guards nothing, so the raw salt goes straight in:

```bash
SALT=$(cast keccak "lattice.ERC20.0.1.0")
INITHASH=$(cast keccak $(forge inspect src/tokens/ERC20/ERC20.sol:ERC20 bytecode))

# no guard step, and the PROXY is the deployer
cast create2 --deployer 0x4e59b44847b379578588920cA78FbF26c0B4956C --salt $SALT --init-code-hash $INITHASH
```

## The release manifest

Every `run(version, owner)` writes `deployments/<chainid>/release-<version>.json`:

```jsonc
{
  "version": "0.1.0",
  "chainid": 1,
  "createx": "0xba5Ed099633D3B313e4D5F7bdc1305d3c28ba5Ed",
  "registry": "0x...",
  "factory": "0x...",
  "owner": "0x...",            // read live off the registry
  "timestamp": 1780000000,
  "facets": {
    "ERC20": {
      "name": "ERC20",
      "address": "0x...",
      "codehash": "0x...",       // runtime codehash — the LatticeRegistry code pin
      "selectorsHash": "0x...",  // keccak256 of the live ERC-8153 exportSelectors() blob — the selector pin
      "salt": "0x..."            // keccak256("lattice.ERC20.0.1.0")
    }
    // ... one entry per FacetInventory facet
  }
}
```

`codehash` and `selectorsHash` are exactly the two pins `LatticeRegistry.register` records and its
live-read views re-verify, so the manifest diffs directly against on-chain state. The `createx` field
records the CreateX singleton address; on an
[Arachnid-only chain](#chains-without-createx-the-arachnid-fallback) the deployer the addresses
actually derive from is the proxy, and the manifest's own `registry`/`factory`/`facets` entries — not
that field — are the authority on where the release landed.

## Idempotency and resume

`release()` is **predict-then-skip**: every deploy first computes the deterministic address and skips
deployment if code already lives there; registration skips `(name, version)` records that already
exist and only moves `latest` when it isn't already pointing at this version. Consequences:

- A run that died halfway is finished by **re-running the same command** — completed pieces are
  adopted, missing pieces are deployed.
- A release **someone else** completed (or partially completed, permissionlessly) is adopted
  identically — the addresses cannot differ.
- Re-running a finished release is a no-op (and never trips the registry's append-only
  `RecordExists` guard).

## The mainnet multisig-owner rule

Repo security policy: the registry admin **MUST be a multisig from the first mainnet release**. The
registry's `register`/`setLatest` are owner-only, so `release()` runs its registration phase only
when `registry.owner() == msg.sender` (run the script with `--account`/`--sender` so the script's
`msg.sender` equals the broadcasting EOA). On mainnet the flow is therefore two-step by design:

1. any broadcaster runs `DeployRelease.run(version, multisig)` — deploys everything, **skips**
   registration, writes the manifest;
2. the multisig executes the `register` + `setLatest` batch out-of-band, from the manifest.

On testnets (or wherever the broadcaster IS the owner) the script registers in the same run.

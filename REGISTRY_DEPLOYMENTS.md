# Registry Deployments

This file is the **canonical reference** for how Lattice releases land on-chain: the deterministic
address scheme of the [`LatticeRegistry`](src/LatticeRegistry.sol), the
[`LatticeFactory`](src/LatticeFactory.sol), and every
[`FacetInventory`](script/lib/FacetInventory.sol) facet, all deployed through the **Arachnid
deterministic-deployment proxy** by
[`script/deploy/DeployRelease.s.sol`](script/deploy/DeployRelease.s.sol). The same salt, initcode and
constructor arguments give the same address on every chain with that proxy. Broadcasting accounts and
nonces do not enter the derivation.

[ADR 0004](docs/adr/0004-release-deployer-and-salts.md) records the salt scheme,
[ADR 0014](docs/adr/0014-arachnid-shared-release-deployer.md) selects the proxy, and
[ADR 0007](docs/adr/0007-registry-trust-model.md) describes the registry's trust model.

## The Arachnid proxy

Release deployments call the [Arachnid deterministic-deployment
proxy](https://github.com/Arachnid/deterministic-deployment-proxy) explicitly at:

```
0x4e59b44847b379578588920cA78FbF26c0B4956C
```

The proxy takes raw `salt (32 bytes) ++ initCode` calldata, applies CREATE2 without hashing the salt,
and returns the raw 20-byte deployed address. [`ArachnidDeployer`](script/lib/ArachnidDeployer.sol)
checks that the call succeeds, the return is exactly 20 bytes, the address matches its prediction and
code exists there. Calling explicitly gives scripts and non-broadcast tests identical semantics.

`DeployRelease.release()` refuses to run without the proxy, even when CreateX is present. Install the
proxy using the upstream project's chain bootstrap instructions before a release. Chains that accept
only EIP-155 replay-protected transactions cannot use the upstream keyless deployment transaction;
they need a chain-supported installation or preinstall at this address. A missing proxy is a release
prerequisite to resolve, rather than a reason to choose another address family.

Anvil and Foundry's test EVM pre-deploy the proxy. Tests can restore its runtime with
`vm.etch(ArachnidProxy.PROXY, ArachnidProxy.RUNTIME)` from
[`test/helpers/ArachnidProxy.sol`](test/helpers/ArachnidProxy.sol). Local recipes can still use plain
CREATE when the proxy is missing ([`BaseDeploy._facet`](script/base/BaseDeploy.s.sol)); that fallback
has no canonical release address.

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
(`major<<48 | minor<<24 | patch`). The inventory's 129 entries include the four **diamond-lib core
facets** (`DiamondCutFacet`, `DiamondLoupeFacet`, `ERC165Facet`, `OwnableFacet` — ERC-8153 since
diamond-lib v0.2.0); they are release-versioned by the same `lattice.<Name>.<version>` scheme as
every Lattice facet, so e.g. the loupe's registry key is `keccak256("lattice.DiamondLoupeFacet")`.

**Factory loupe requirement.** `LatticeFactory.deploy` and `deployStrict` refuse to assemble an
un-introspectable diamond: every fresh deploy's cuts must cover the four EIP-2535 loupe selectors (`facets()`,
`facetFunctionSelectors(address)`, `facetAddresses()`, `facetAddress(bytes4)`) in some `Add` cut, or
it reverts `LatticeFactory__MissingLoupeCoverage(missingSelector)`. Coverage is selector-based —
any facet may provide it; the registered `lattice.DiamondLoupeFacet` entry is the one-line way. The
CUT facet remains optional (immutable-by-design diamonds are legal).

**Registry and factory addresses move with their bytecode.** `REGISTRY_SALT` and `FACTORY_SALT` carry no
version, so the singleton addresses depend only on the `LatticeRegistry` and `LatticeFactory` bytecode
(and the registry owner). Any change to either contract, including the #176 hardening change
(`deployStrict`, the recipe hash in `DiamondDeployed`, `RecipeEntry.exclude`, bounded exporter reads),
moves both addresses. Compute them from the commit you deploy, never from an earlier one. A factory also
embeds the `Lattice` proxy build: read `factory.diamondInitCodeHash()` before predicting diamond addresses
with it.

## Address derivation

The address is the plain EIP-1014 derivation over the **raw, unguarded** salt:

```
address = keccak256(0xff ++ 0x4e59b44847b379578588920cA78FbF26c0B4956C ++ salt ++ keccak256(initCode))[12:]
```

[`ArachnidDeployer.deploy`/`predict`](script/lib/ArachnidDeployer.sol) implement this derivation.
CreateX's presence never changes a canonical release prediction. Older development releases used
CreateX first, hashing the salt as `keccak256(abi.encode(salt))` and using CreateX as the CREATE2
sender. Those releases remain historical instances; they are not adopted as deployments at the new
proxy-derived addresses. The change intentionally moves every former CreateX release address.

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
# Build from the release tag and its pinned compiler configuration.
SALT=$(cast keccak "lattice.ERC20.0.1.0")
INITHASH=$(cast keccak "$(forge inspect src/tokens/ERC20/ERC20.sol:ERC20 bytecode)")
cast create2 --deployer 0x4e59b44847b379578588920cA78FbF26c0B4956C --salt "$SALT" --init-code-hash "$INITHASH"
```

For the registry, append its owner constructor argument before hashing the initcode:

```bash
INITHASH=$(cast keccak "$(cast concat-hex "$(forge inspect src/LatticeRegistry.sol:LatticeRegistry bytecode)" "$(cast abi-encode 'f(address)' "$OWNER")")")
```

The factory similarly appends `abi.encode(registry, address(0), address(0))`. Its registry argument must
be the predicted registry for that same build and owner. Use one release build profile across chains;
a different EVM target or metadata hash can change the initcode and addresses.

## The release manifest

Every `run(version, owner)` writes `deployments/<chainid>/release-<version>.json`:

```jsonc
{
  "version": "0.1.0",
  "chainid": 1,
  "deployer": { "kind": "arachnid", "address": "0x4e59b44847b379578588920cA78FbF26c0B4956C" },
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
live-read views re-verify, so the manifest diffs directly against on-chain state. The `deployer`
entry names the actual release proxy on every chain. Legacy manifests with a `createx` field describe
the earlier deployment policy and require its historical source/configuration to reproduce.

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

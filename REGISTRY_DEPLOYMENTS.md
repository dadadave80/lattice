# Registry Deployments

This file is the **canonical reference** for how Lattice releases land on-chain: the deterministic
address scheme of the [`LatticeRegistry`](src/LatticeRegistry.sol), the
[`LatticeFactory`](src/LatticeFactory.sol), and every
[`FacetInventory`](script/lib/FacetInventory.sol) facet and
[`InitInventory`](script/lib/InitInventory.sol) stateless initializer, plus the constructor-bound
[account initializer/factory pairs](script/lib/AccountReleaseInventory.sol), all deployed through the **Arachnid
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
| every stateless init | `keccak256("lattice.<InitName>.<version>")`, e.g. `keccak256("lattice.ERC20Init.0.1.0")` | per initializer/version |
| account init/factory | `keccak256("lattice.<AccountIdentity>.<version>")`, e.g. `lattice.AccountFactoryV09.0.1.0` | per proxy kind/EntryPoint/version |

`<Name>` is the facet's contract name exactly as listed in
[`FacetInventory`](script/lib/FacetInventory.sol) (also the source of the parity gate — the same
string, prefixed `lattice.`, is the facet's registry name key). `<version>` is the release semver
string (`"0.1.0"`), the same value that packs to the registry's `uint64` version key
(`major<<48 | minor<<24 | patch`). The facet inventory includes the four **diamond-lib core
facets** (`DiamondCutFacet`, `DiamondLoupeFacet`, `ERC165Facet`, `OwnableFacet` — ERC-8153 since
diamond-lib v0.2.0); they are release-versioned by the same `lattice.<Name>.<version>` scheme as
every Lattice facet, so e.g. the loupe's registry key is `keccak256("lattice.DiamondLoupeFacet")`.

## Released initializers

`InitInventory` lists the stateless `*Init` contracts in `src/` and diamond-lib's `MultiInit`, pairing
each unique name with its compiled artifact path. The source parity test rejects missing/extra entries,
duplicates and constructors requiring arguments. `AccountInit` and `AccountInit6900` are explicitly
excluded because their EntryPoint constructor argument belongs to a specific account factory.
Their canonical instances are released separately through `AccountReleaseInventory`, as described below.

The release deploys each initializer through Arachnid and calls the registry's permissionless Tier A
`attest`. Initializers are **not facets**: they are not registered in Tier B, have no `latest` pointer,
and do not need `exportSelectors()`. A codehash resolver keeps its first attester, so identical runtime
code at a later version's new salt may still resolve to the earlier address. Consumers pin the
initializer's release manifest address when they need version identity.

## Account releases

Both account recipes create accounts through their specialized factories: `AccountFactory` deploys
`AccountDiamond` with ERC-7579 handler dispatch, and `AccountFactory6900` deploys `ModularAccount6900`
with ERC-6900 execution-module dispatch. A plain `Lattice` does not provide those fallback paths.
The factories create and initialize an account in one transaction. They bind owner and salt to its
address and intentionally return the existing account when that pair is reused.

The release includes both proxy kinds for each pinned EntryPoint:

| EntryPoint | Address | Identity suffix |
| --- | --- | --- |
| v0.7 | `0x0000000071727De22E5E9d8BAf0edAc6f37da032` | `V07` |
| v0.8 | `0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108` | `V08` |
| v0.9 (repository default) | `0x433709009B8330FDa32311DF1C2AFA402eD8D009` | `V09` |

For example, `AccountInitV09` ABI-encodes v0.9 in its constructor; `AccountFactoryV09` ABI-encodes the
ordered released facet cuts and that initializer's address. The 6900 labels add `6900` before the
suffix. The six initializers receive permissionless Tier-A attestations, without curated facet names
or `latest` pointers. Factories remain manifest-only: their runtime hash binds the immutable initializer
and proxy hash, but omits the stored blueprint. Another factory can share that runtime hash with different
cuts, so a Tier-A lookup cannot select the canonical factory. Use its exact manifest address and constructor
arguments. Blueprint facet names have one definition shared by the recipes and release.
Changing the EntryPoint, blueprint, build or version can change their predictions.

`DeployAccount.run(entryPoint, owner, salt)` and `DeployAccount6900.run(entryPoint, owner, salt)` use
these factories. The two-argument forms read `LATTICE_SALT` (default zero), and `run(owner)` uses the
repository's default EntryPoint. `buildCuts` keeps its constructor-bound initializer return type;
`buildFactory` resolves the corresponding factory without creating an account. Custom EntryPoints
remain supported with explicit `Custom` labels whose initcode binds the address. They are outside the
canonical release list. Without Arachnid, the local profile uses ordinary CREATE for the implementation,
initializer and factory contracts and has no canonical shared address.

The pinned EntryPoint address is a configuration choice, not proof that a target chain has compatible
EntryPoint code, a bundler, native EIP-7702 support or working external modules. Existing plain-Lattice
accounts are not repaired by changing a script; corrected deployments use the specialized proxy.
See [ADR 0025](docs/adr/0025-account-factory-release-identity.md).

## Composing released initializers

`BaseDeploy._init(name)` reuses those same versioned addresses. Its MultiInit, AccessControlInit and
DiamondIntrospectionInit helpers no longer deploy new copies per recipe. The security recipes likewise
use released CircuitBreakerInit, EmergencyStopInit, InvariantCheckerInit, PausableInit and RateLimiterInit.
Other per-recipe initializer migrations are tracked separately in
[#195](https://github.com/dadadave80/lattice/issues/195).

An init step is delegatecalled inside the diamond's initialization window; it does not open a window
or install facets itself. Compose the steps with MultiInit, initialize AccessControl before the
TimelockController/Governor role wiring, and initialize ERC20, EIP712, Nonces and Votes in the same call
for ERC20Votes. The standalone governance steps preserve their library semantics: VotesInit supplies
neither token accounting nor a signing domain, GovernorInit grants no roles, and TimelockControllerInit
expects any external admin to have been seeded by the preceding AccessControl step. The timelock still
grants its diamond its own admin role. These are composition preconditions; the steps do not introduce
a new ordering marker or infer an admin from the broadcasting account.

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
  Canonical builds now use solc 0.8.36, Cancun, optimizer 1,000,000 runs, the legacy pipeline and
  IPFS/CBOR metadata under Foundry v1.9.0 (`make release-build-check`). This intentionally rotates
  addresses from earlier Osaka builds, including metadata-derived addresses of unchanged contracts.
  Existing deployments retain their historical release configuration; a new build is a fresh release.
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

## Release identities and chain observations

Schema version 1 separates two kinds of evidence:

| File | Evidence |
| --- | --- |
| `deployments/release-<version>.json` | Offline identities: source version/tag/commit, explicit initial owner, Arachnid deployer, compiler configuration/input hash, Lattice proxy initcode hash, and every registry/factory/facet/init/external-library identity |
| `deployments/<chainid>/release-<version>.json` | State observed at a pinned chain block: code presence/match, registry owner, facet registration/latest and source-verification status |
| `deployments/<chainid>/plan-<version>.json` | Legacy-shaped output from `DeployRelease.run`; a simulation deployment plan, produced before broadcast inclusion, **not chain evidence** |

The offline `contracts` array begins with registry and factory, followed by the facet and stateless
initializer inventories, then external libraries and the account initializer/factory pairs. Every entry has `name`, `artifact`, `kind`, predicted `address`, raw `salt`,
`initCodeHash`, runtime `codehash`, ABI-encoded `constructorArgs`, `nameHash` and `selectorsHash`.
The last two fields are zero for non-facets. Registry/factory constructor arguments include the
initial owner and predicted registry, respectively; ENS arguments are zero. Factory runtime hashes
come from local constructor execution, including its immutable registry and proxy hash.
`deployer.librarySalt` records the pinned native Foundry library salt (zero), and
`compiler.libraries` is the actual empty solc map. The external library records supply the post-link
address map. Foundry native CREATE2 linking keeps that map identical in tests and release scripts;
it does not inject a global solc metadata map. PoseidonT3 is a shared Tier-A library and must be
included in release deployment and verification; its actual runtime includes Solidity's patched self address. See
[ADR 0022](docs/adr/0022-native-create2-release-libraries.md).
Account identities use `account-init` and `account-factory` kinds. The optional schema-v1 `accounts`
array binds each pair's names to its EntryPoint/version, proxy kind/initcode hash and
`keccak256(abi.encode(orderedCuts))` blueprint hash. Current generation includes all six pairs;
historical manifests may omit this array only when they contain no account identities. Full
`constructorArgs` remain definitive. Native validation checks bindings, canonical labels, decoded
constructors and listed-facet selector commitments; frozen source regeneration also checks the exact
blueprint and trusted artifact/proxy/runtime hashes. Schema validation alone is not source verification.

Generate identities **offline**, after committing the source inputs, with the shared pinned toolchain:

```bash
make release-manifest VERSION=<version> TAG=v<version> OWNER=<confirmed-initial-owner> \
  PUBLICATION=release DESTINATION=deployments/release-<version>.json
```

No canonical initial owner has been confirmed in this repository. Do not substitute a broadcaster,
a development owner or an ENS reverse-record address. Publication remains blocked until the
maintainer confirms that one address and the release source freeze. The small synthetic examples under
`test/fixtures/release-manifests/` use `publication: fixture`, a `fixture/` tag and an obvious test owner.
Their source/input hashes and block identifier are test sentinels, not release or chain evidence.

`lattice.commit` is the **existing source commit**, not the future commit containing its manifest.
A manifest-only successor may commit the output. For a real release, freeze an already-merged
source commit retained by `origin/dev` or `origin/main` before that successor; being an ancestor
of the current feature HEAD is insufficient after squash merging. The release tag must preserve
those build inputs. Existing tags with different inputs (including v0.5.0) cannot be relabelled as
a fresh build; use their historical source or explicit fixture mode. IPFS/CBOR metadata stays enabled: source comments, NatSpec,
paths and compiler settings can change addresses. Regenerate drafts after edits; preserve frozen
release files. [ADR 0020](docs/adr/0020-source-anchored-release-manifests.md) records this boundary.

`make release-manifests` checks schemas, CREATE2/constructor identities and per-chain cross references,
then compares **two clean builds of the current checkout**, including all shared addresses and the
proxy/compiler-input hashes. Once real release manifests exist, it also rebuilds each published golden
in a clean checkout of **its own already-merged** source commit.
Forge tests additionally check current artifact/inventory parity and immutable-adjusted runtimes.
The native schema validator implements exactly the vocabulary in `deployments/schema/`; no schema
CLI or new runtime is required. Goldens require the recorded Foundry version and locked submodules;
the source guard rejects a different toolchain rather than silently redefining historical input.
No committed fixture depends on retaining an unmerged PR head. Real release goldens are added only
after the generator is merged, a source commit is frozen and the canonical owner is confirmed.

After broadcast inclusion and multisig curation, collect actual chain state:

```bash
make release-status MANIFEST=deployments/release-<version>.json RPC_URL=<rpc-url-or-alias> \
  DESTINATION=deployments/<chainid>/release-<version>.json
```

This command forks a pinned RPC block read-only and rejects a changed block hash. `deployed: null`
means absent; `pre-existing` means code observed at that block without asserting a transaction hash.
`codeMatches` compares runtime hashes; `registered` and `latest` additionally compare the exact
version, address, runtime and selector pins. Verification starts `false` with a null verifier and
must be updated only from actual verification results. Re-observation resets verification to
unknown; it does not infer a Sourcify match from code presence. A future verification command is
tracked in [#198](https://github.com/dadadave80/lattice/issues/198).

The tagged release asset job requires the matching real release manifest, rebuilds it and attaches
`lattice-build-info-v<version>.tar.gz` with standard-JSON compiler inputs, compiler versions, manifest
and schemas, alongside the checked storage layout assets. `compiler.inputHash` is keccak256 of the
compact, sorted JSON input package without its trailing newline. Host-specific non-standard compiler
CLI path fields and compiler outputs are excluded; standard-JSON language, sources and settings
are retained. The public **v0.5.0** release had no such assets or schema-v1 golden. Its Foundry 1.8.5,
implicit Osaka build and CreateX-first policy remain historical inputs; rebuilding current Cancun
source does not reproduce or replace that release's evidence.

## Chain readiness and ownership

There are currently **no public chains certified ready by schema-v1 evidence**. RPC aliases in
`foundry.toml` are configuration options, not support claims. A chain supports a release only when:

1. its EVM supports Cancun and the Arachnid proxy is installed at the canonical address;
2. every shared identity has matching code and actual source verification;
3. all versioned facets are registered and `latest` points to that version; and
4. a reviewed block-pinned chain manifest records that state and the current registry owner.

Use the same confirmed **initial owner** on every chain so core CREATE2 predictions agree. Establish
and verify that address's control on each chain before deployment; a multisig must own the registry
from the first mainnet release. Later per-chain handovers do not change existing addresses: the
current owner calls `transferOwnership(newOwner)`, the intended multisig independently checks the
registry and pending owner, then calls `acceptOwnership()`. Record the resulting owner at a new
observed block. Passing a new owner to `DeployRelease` derives a different registry, not a handover.

Release operators advance `latest` for each supported chain after verification and curation. The
release script never downgrades it when replaying an older version; the registry owner retains
rollback authority, so consumers pin exact versions. Chain readiness is evaluated against the
observed version, not assumed from a tag or a successful simulation.

The Sepolia factory `0x9e49fb5cdbb09ecf65513f7c690909e093170037` is an **ENS-enabled development
instance**, deployed by plain CREATE according to the tracked
[broadcast](broadcast/DeployFactory.s.sol/11155111/run-latest.json). It is not the canonical raw-salt
factory. Its historical build commit and embedded proxy hash are not established by that log, so no
schema-v1 `nonCanonicalFactories` entry invents those fields. Add one only with verified source and
hash evidence. `LatticeVersion` and the release manifest currently agree at 0.5.0; normal release
promotions back-merge version bumps into dev.

## Idempotency and resume

`release()` is **predict-then-skip**: every deploy first computes the deterministic address and skips
deployment if code already lives there. Init codehashes are attested in Tier A; facet registration skips
`(name, version)` records that already exist and only moves `latest` when it isn't already pointing at this version. Consequences:

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

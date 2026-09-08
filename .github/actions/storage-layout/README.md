# ERC-7201 storage layout Action

A reusable composite GitHub Action for Foundry projects. It checks actual source structs (not handwritten
mirrors), namespace/slot metadata, nested storage types, snapshot drift, and compatibility against a
trusted previous commit. No Lattice Solidity dependency is needed.

## Requirements

Linux runner with Python **3.10+**, Git, Forge and cast. Lattice tests with Foundry **v1.8.1** and solc
**0.8.36**. Pin your compiler/profile and action commit. The Action does not install tools, fetch Git
history, write a baseline, or need a token beyond the consumer's read-only checkout.

## Consumer setup

1. Declare an ERC-7201 source struct with its `@custom:storage-location erc7201:...` annotation and a
   literal `bytes32 constant` storage root. Check the accessor actually uses that root.
2. Import that **actual** struct into a compile-only probe; add a state variable of that type. Do not
   redeclare a mirror. Use a fully qualified probe identifier to avoid ambiguous contract names.
3. Add a JSON manifest and generate/review the initial snapshot using `check.py --update` locally.
4. Commit the initial snapshot before enabling compatibility checks. Subsequent checks compare to
   a trusted base/release commit fetched by the workflow, not a snapshot edited in the same PR.

Example manifest (all paths relative to `working-directory`):

```json
[
  {
    "variable": "vault",
    "source": "src/VaultLib.sol",
    "type": "VaultStorage",
    "namespace": "example.storage.Vault",
    "slot-constant": "VAULT_STORAGE_SLOT"
  }
]
```

The source type must be a struct resolvable in the declared source AST. The slot constant must be a
literal number equal to `cast index-erc7201 example.storage.Vault`. Source structs imported directly
also expose changes to nested structs, mapping values, arrays, and enum order to the checker.

```yaml
permissions:
  contents: read
steps:
  - uses: actions/checkout@v7
    with:
      fetch-depth: 0
      submodules: recursive
      persist-credentials: false
  - uses: foundry-rs/foundry-toolchain@v1
    with:
      version: v1.8.1
  - uses: dadadave80/lattice/.github/actions/storage-layout@STORAGE_ACTION_COMMIT
    with:
      probe: script/StorageProbe.sol:StorageProbe
      manifest: storage.manifest.json
      baseline: storage.baseline.json
      baseline-ref: TRUSTED_RELEASE_COMMIT
      foundry-profile: default
```

Replace both uppercase commit placeholders with verified full SHAs. For pull requests, derive the
baseline from `github.event.pull_request.base.sha` in trusted workflow code. Never let PR contents
select their own historical baseline. Post-merge checks can use the previous branch commit. A first
push with an all-zero previous SHA needs an explicit existing seed commit.

| Input | Default / meaning |
| --- | --- |
| `working-directory` | `.`; consumer project root, spaces supported |
| `probe` | Required `source.sol:Contract` |
| `manifest` | Required source-bound JSON manifest |
| `baseline` | Required committed snapshot |
| `baseline-ref` | Required trusted historical commit, fetched by caller |
| `foundry-profile` | `ci`; use your consumer's profile |

## Local commands

Download/check out the published Action at a pinned commit. Its checker is directly runnable:

```sh
python3 /path/to/action/check.py --working-directory /path/to/consumer \
  --probe script/StorageProbe.sol:StorageProbe --manifest storage.manifest.json \
  --baseline storage.baseline.json --foundry-profile default --update
```

Add `--baseline-ref TRUSTED_COMMIT` to check compatibility before writing a proposed update. Without
`--update`, the committed candidate snapshot must match actual compiled source. A normal check without
`--baseline-ref` checks drift only and prints that limitation. GitHub Action checks always require a ref.
Errors exit nonzero and identify the namespace/member with old/new type information.

## Compatibility policy

Existing root members must remain in order with identical names, slots, offsets, and recursive types.
Only top-level tail fields may be appended. Renaming or moving a source type also fails conservatively.
A nested append is rejected: even if safe in a mapping, it may change array stride or packing elsewhere.
Numeric compiler AST IDs are ignored; enum ordering is not. Missing namespaces/types, empty layouts,
invalid metadata, source/probe mismatches, and malformed snapshots fail closed.

For Lattice's one-time text-to-JSON baseline migration only, historical comparison accepts an existing
legacy snapshot if all its namespaces remain covered and production Solidity is unchanged after canonical
formatting. Dependency changes and semantic source changes still fail. After migration, JSON structural
comparison applies. This is not an external-consumer bootstrap mechanism.

## Limits

This verifies declared compiled types and their declared slot constants. It does not prove arbitrary
assembly uses those constants, discover every undeclared storage root, or prove semantic upgrade
safety. A reviewer must audit the manifest coverage, assembly accessors, initialization and authority.
Initializable and fixed-slot reentrancy storage are outside this ERC-7201 guard. A green check is not an audit.
Keep workflows and release baselines protected: malicious workflow/checker edits can bypass any CI gate.

## Repository validation and docs

In Lattice, `script/upgrades/check-storage-layout.sh` delegates to this exact implementation;
`python3 .github/actions/storage-layout/test_check.py` runs its regression checks. The documentation
build uses `./script/docs/build.sh` with Foundry v1.8.1 and the Vocs/Node toolchain emitted by `forge doc`.

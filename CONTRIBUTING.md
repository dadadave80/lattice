# Contributing to Lattice

Lattice is an open-source public good — contributions are welcome, whether
that's a new module, a bug fix, tests, or documentation.

## Getting started

```sh
git clone https://github.com/dadadave80/lattice.git
cd lattice
git submodule update --init --recursive   # diamond-lib + forge-std
forge build
forge test
```

## Architecture conventions

Lattice modules follow a strict **three-layer pattern**. Read `CLAUDE.md` and
`STORAGE_REGISTRY.md` for the full version before opening a PR. In short:

1. **Interface** (`src/interfaces/<area>/I<Module>.sol`) — external ABI, errors, events.
2. **Library** (`src/<area>/libraries/<Module>Lib.sol`) — all logic, all storage
   access via a single ERC-7201 `*Storage()` slot, and the `__<Module>_init`.
3. **Facet** (`src/<area>/<Module>.sol`) — thin, stateless forwarding only.

Non-negotiable rules:

- **Append-only storage.** Never reorder, retype, or remove a field in an
  ERC-7201 storage struct — only append. Layout drift silently corrupts live
  proxies and is checked in CI (`script/upgrades/check-storage-layout.sh`).
- **Unique namespaces.** Every module needs its own precomputed ERC-7201 slot
  (and ERC-165 map slot). Verified by `StorageSlotVerificationTest`.
- **Stateless facets.** State lives in the Diamond proxy, never in the facet.

## Before you open a PR

- `forge fmt` passes (CI runs `forge fmt --check`).
- `forge test` is green, with tests covering new behavior.
- `FOUNDRY_PROFILE=ci forge build --sizes --skip test script` if you touched hot
  paths (CI enforces the EIP-170 size limit on deployable facets).

## Security

Do not file public issues for vulnerabilities — see [SECURITY.md](SECURITY.md)
for private reporting.

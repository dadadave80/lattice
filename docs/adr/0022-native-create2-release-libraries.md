# 0022. Shared external libraries use Foundry's native CREATE2 linker

- **Status:** Accepted
- **Date:** 2026-11-06; release implementation comparison for [#196](https://github.com/dadadave80/lattice/issues/196)
  and [#197](https://github.com/dadadave80/lattice/issues/197)

## Context

Semaphore and ShieldedPool link the existing external PoseidonT3 library. Test builds auto-link it,
but a filtered release script with only dynamic artifact reads previously omitted that dependency
and failed with unlinked bytecode. A sender-dependent library address would change facet initcode
and defeat chain-independent release predictions. Solidity also patches a library's own address
into its deployed runtime; hashing its unpatched artifact is incorrect.

## Options considered

1. **Native Foundry CREATE2 linking with an explicit dependency inventory.** Chosen: existing tools,
   deterministic addresses shared by tests/scripts, no custom linker and no compiler metadata change.
2. **Inline Poseidon.** Rejected by measurement: under solc 0.8.36/Cancun/optimizer 1,000,000, changing
   the existing public hash to internal yields Semaphore 29,176 bytes and ShieldedPool 28,866 bytes,
   both above EIP-170. The existing external library is 23,576 bytes. These measurements use the
   pre-privacy-hardening source at integration commit 3e89d90; they are not gas estimates.
3. **Set solc's global libraries map.** Rejected: it changes metadata even for unrelated contracts,
   rotating core bytecode, and complicates deriving the library's own CREATE2 identity. A standalone
   native-solc probe confirmed the unrelated metadata change.
4. **Implement a bytecode linker.** Rejected: compiler link references and Solidity runtime patching
   introduce extra parsing and correctness obligations already handled by the pinned Foundry linker.

## Decision

- Pin Arachnid as `create2_deployer` and zero as `create2_library_salt` in the common profile. Keep
  solc's `libraries` map empty. `make release-build-check` enforces all three resolved settings.
- `LibraryInventory` identifies PoseidonT3 and references its linked address, making it an actual
  dependency of filtered release scripts. Foundry 1.9.0 uses the same native CREATE2 linker for tests
  and scripts when the proxy is available. No EOA nonce participates in the accepted release map.
- Release code checks that each native linked address equals the raw CREATE2 prediction, deploys
  missing library code, verifies a trusted artifact-derived runtime hash, and attests it in Tier A.
  Library artifacts, salts, initcode and actual runtime hashes are part of the offline manifest and
  compiler input package. They are never curated facets.
- For the existing Solidity library convention, the expected runtime patches its zero PUSH20 self
  address from the trusted artifact. Unexpected prefixes/placeholders or wrong deployed code fail
  closed. Observed remote code never supplies the expected hash.
- Read-only observation scripts have no linked-library dependency. Their compilation must not cause
  Foundry to predeploy code into a fork and turn an absent dependency into a false presence claim.
- A missing on-chain Arachnid proxy remains a release error. Native script linking may perform local
  fallback preparation before the release preflight, but a failing simulation never broadcasts it.

## Consequences

The external CALL remains part of Poseidon hashing, as before. The library deployment costs roughly
4.7 million gas for code deposit alone (23,576 × 200, excluding constructor/intrinsic gas); this is
an estimate, not a measured total. Core compiler bytecode remains unchanged by these execution-only
settings. Changes to the pinned library source/toolchain can rotate its CREATE2 address and every
linked facet, so release identities and build-info must include that dependency.

## Confirmation

Release tests check missing/wrong library code, raw predictions, Tier-A-only attestation, the embedded
self address and trusted runtime hash. Actual filtered GenerateManifest and DeployRelease simulations
exercise the native script linker. An empty Anvil observation must report the library absent, and a
missing-proxy simulation must fail with installation guidance without sending transactions. Two
clean builds compare all shared identities and compiler inputs.

## References

- [Foundry native script linker](https://github.com/foundry-rs/foundry/blob/v1.9.0/crates/script/src/build.rs)
- [Foundry test/script parity regression](https://github.com/foundry-rs/foundry/blob/v1.9.0/crates/forge/tests/cli/script.rs)
- [Library inventory](../../script/lib/LibraryInventory.sol), [release process](../../REGISTRY_DEPLOYMENTS.md)

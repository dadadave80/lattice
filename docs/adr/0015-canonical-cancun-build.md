# 0015. Canonical releases target Cancun with one pinned build configuration

- **Status:** Accepted
- **Date:** maintainer decision 2026-11-06; tracked in [#197](https://github.com/dadadave80/lattice/issues/197)
  and [#336](https://github.com/dadadave80/lattice/issues/336)

## Context

Release CREATE2 addresses commit to creation bytecode, including compiler metadata. An implicit EVM
target can change with the compiler, while a chain-specific target changes metadata and addresses.
The former Osaka default also allowed instructions unavailable on Cancun chains such as Avalanche's
Fuji deployment target. Historical deployments must remain reproducible from their own source tags.

## Options considered

1. **Explicit Cancun for canonical builds.** One release bytecode family across Cancun-capable chains,
   without relying on a newer compiler target emitting an older instruction set.
2. **Osaka plus a metadata-stripped Cancun comparison.** Retains newer-target code generation, but must
   detect executable differences and still produces different metadata-derived addresses per target.
3. **A build per chain's EVM target.** Permits newer instructions where available, at the cost of
   separate release addresses and verification configurations.

## Decision

- Default and CI builds explicitly use Solidity 0.8.36, Cancun, optimizer 1,000,000 runs, the legacy
  pipeline and IPFS/CBOR metadata. The CI profile emits build info.
- Local work and every CI job share Foundry v1.9.0, the stable release verified on 2026-11-06. The
  composite setup action holds the pin; the build guard checks the running Forge against it.
- The recorded Hedera 1.7.1 script exception remains until #227 verifies its retirement. Its historical
  relay and bytecode measurements remain labelled with the versions actually measured.
- `make release-build-check` validates resolved profiles, lockfile paths/revisions and initialized
  recursive submodules before the canonical CI build. Target drift fails this guard directly; a
  Cancun-versus-Cancun bytecode comparison would prove nothing further.

## Consequences

- The Cancun metadata change intentionally rotates deterministic addresses, even for unchanged
  source. Existing instances keep their historical configuration; these settings describe fresh
  releases rather than upgrades or redeployments at the old addresses.
- Canonical modules cannot use instructions introduced after Cancun. A future target change needs
  another release decision and updated build guard.
- Runtime protocol features remain chain-dependent: EIP-7702 needs Prague, and native P256 needs
  Osaka on Ethereum or RIP-7212 elsewhere (the deployed software verifier is the alternative).
  Their feature tests select that execution hardfork explicitly while retaining Cancun compilation;
  ordinary tests continue to execute on Cancun, including a missing-P256-verifier rejection.
- Foundry 1.9.0 charges creation gas for dynamically linked `new` calls in tests. Snapshot updates
  must distinguish this accounting change from a contract execution change.
- Golden release manifests and exact build-info publication remain part of #196/#197; a settings
  guard alone does not prove an entire published release reproducible.

## Confirmation

- `script/test-check-release-build.sh` mutates EVM/compiler/optimizer/metadata settings, the toolchain
  pin and dependency identities; each drift must fail `script/check-release-build.sh`.
- The CI source-build job runs the same `make release-build-check` as `make ci` locally.

## References

- [Foundry v1.9.0 release](https://github.com/foundry-rs/foundry/releases/tag/v1.9.0)
- [`foundry.toml`](../../foundry.toml), [shared toolchain action](../../.github/actions/foundry-setup/action.yml)
- [#197](https://github.com/dadadave80/lattice/issues/197), [#336](https://github.com/dadadave80/lattice/issues/336)

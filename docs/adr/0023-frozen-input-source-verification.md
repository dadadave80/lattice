# 0023. Source verification submits the frozen compiler witness

- **Status:** Accepted
- **Date:** 2026-11-06; implementation decision for [#198](https://github.com/dadadave80/lattice/issues/198)

## Context

Release identities include metadata, constructor arguments, immutable-adjusted runtime code and
native external-library linking. Rebuilding a different checkout or injecting a solc library map can
change these identities. A verifier's completed job or partial match does not establish exact source
verification of the frozen deployment.

## Options considered

1. **Submit the archived standard-JSON input to Sourcify v2 using existing Bash, jq and curl.** Chosen:
   preserves the exact compiler witness without a new runtime, compiler or linker.
2. **Use the pinned Forge verification CLI.** It regenerates standard-JSON from a project rather than
   accepting this archived input directly. Its job-check exit status still needs a strict match lookup.
3. **Add a verifier SDK or HTTP test server.** Rejected: unnecessary runtime dependencies for this API.

## Decision

- Verify the whole existing release inventory, including shared libraries. Reproduce the frozen
  source in a fresh checkout, compare all manifest identities and the canonical compiler-input hash,
  then resolve targets and precise compiler builds from reproduced compiler output.
- Keep native library linking and the archived empty solc library map unchanged. Compare full
  creation bytecode including constructor arguments and actual runtime including library self-address
  patches against manifest hashes.
- Re-observe code and registry facts at the recorded chain block before any submission. A supplied
  creation transaction must prove the canonical direct Arachnid salt and complete initcode. Reject
  missing/wrong code, changed chain/block, ambiguous targets and non-release operational input.
- Submit exact archived standard-JSON to the fixed official Sourcify v2 service. Use bounded requests,
  conservative retries, rate-limit handling, no ambient curl configuration and no verifier credentials.
- Look up every address before submission. Only an exact creation and runtime match, with matching
  chain, address and both bytecode hashes, sets the per-chain verified flag. A completed job, conflict,
  partial match, existing flag or untrusted response cannot substitute for this proof.
- Persist progress atomically. Optional pending job IDs support safe resume and imply no success.
  Concurrent runs are excluded by a per-chain lock. Offline preparation sends no verifier requests.

## Consequences

Verification needs frozen source history, the recorded toolchain, archived inputs, historical RPC
state and Sourcify availability. It costs local rebuild time and API requests, with no on-chain gas or
production bytecode change. Partial verification remains an explicit failure. Actual publication,
owner confirmation and chain readiness are separate release prerequisites.

## Confirmation

Executable mock fixtures cover exact/partial results, job resume, malformed responses, constructor
tails, library runtime patches, transaction witnesses and rate limits without a server or network
submission. Native offline preparation checks the complete generated catalog. CI runs the fixtures.

## References

- [0020](0020-source-anchored-release-manifests.md), [0022](0022-native-create2-release-libraries.md)
- [Release command](../../script/release-verify.sh), [release guide](../../REGISTRY_DEPLOYMENTS.md)
- [Sourcify API](https://docs.sourcify.dev/docs/api/), [OpenAPI](https://sourcify.dev/server/api-docs/swagger.json)
- [Foundry v1.9.0 provider](https://github.com/foundry-rs/foundry/blob/v1.9.0/crates/verify/src/sourcify.rs)
- [#198](https://github.com/dadadave80/lattice/issues/198)

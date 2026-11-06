# 0014. Shared releases use only the Arachnid deterministic-deployment proxy

- **Status:** Accepted; supersedes the deployer choice in [0004](0004-release-deployer-and-salts.md).
  Its raw salt formulas and use of CREATE2 remain accepted.
- **Date:** 2026-11-06, implementing [#193](https://github.com/dadadave80/lattice/issues/193)

## Context

Lattice scripts and integrators must predict the same shared contract addresses without first choosing
between CreateX and Arachnid according to chain state. The previous CreateX-first policy produced two
address families: CreateX hashed raw salts before CREATE2, whereas Arachnid used them unchanged.

## Options considered

1. **Arachnid on every chain.** One plain EIP-1014 address formula; requires its canonical proxy.
2. **CreateX first, Arachnid fallback.** Preserves older CreateX development addresses but requires
   chain-dependent prediction and retains two deployment protocols for the same release.
3. **CREATE3.** Keeps addresses across bytecode changes but loses the initcode commitment and the
   permissionless completion model. Existing sender-bound CREATE3 workflows serve a different purpose.

## Decision

`DeployRelease` and `BaseDeploy._facet` use `ArachnidDeployer` to call
`0x4e59b44847b379578588920cA78FbF26c0B4956C` explicitly with `salt ++ initCode`, even when CreateX also
exists. The helper requires a successful call, exactly 20 returned bytes, the predicted address and
nonempty deployed code. The proxy is a trusted chain bootstrap prerequisite; return checks do not
replace verifying its installation.

A release fails with installation guidance when the proxy is absent. Local recipe assembly retains a
plain CREATE fallback in that case. Adapter and upgrade CREATE3 flows retain their existing CreateX
sender/chain binding. Salt formulas do not change.

## Consequences

- The same build and constructor arguments derive one shared release address on every compatible chain.
  Anyone can complete a partial release, but the address still commits to its full initcode.
- All addresses formerly derived through CreateX move. Older development instances and manifests remain
  historical artifacts and must be reproduced under their original policy.
- No deployed facet, registry or factory runtime changes because of this script-only deployer choice.
  There is no recurring diamond dispatch cost. No deployment gas improvement is claimed.
- Chains lacking the proxy cannot host a canonical release until they install it. Chains refusing the
  upstream unprotected keyless transaction need a chain-supported bootstrap or preinstall.

## Confirmation

- `DeployReleaseTest.test_Release_UsesArachnidWhenBothDeployersExist` checks the registry, factory and
  every release facet against the raw-salt proxy formula.
- `test_Release_IdempotentResume` makes every further proxy call revert, then successfully resumes.
- `test_Release_RequiresProxyEvenWhenCreateXExists` proves the missing-proxy prerequisite.
- `CreateXDeployerTest` checks both shared-facet proxy preference and the local CREATE fallback while
  retaining the existing CREATE3 and legacy raw-salt helper tests.
- `ArachnidDeployerTest` exercises malformed returns, unexpected addresses, missing code and failed
  CREATE2 calls. `ReleasePipelineTest` composes a live token and the governed-vault released facets.

## References

- [Release deployment reference](../../REGISTRY_DEPLOYMENTS.md)
- [Arachnid upstream](https://github.com/Arachnid/deterministic-deployment-proxy)
- [#193](https://github.com/dadadave80/lattice/issues/193)
- [`ArachnidDeployer.sol`](../../script/lib/ArachnidDeployer.sol)

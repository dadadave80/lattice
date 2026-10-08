# Lattice — project instructions

This is the canonical project guide for Codex, Claude, and other coding agents. Read it before
changing this repository. Explicit user instructions take precedence over repository conventions;
if older documentation conflicts with the development policy below, apply this policy.

## Development stage and design decisions

- Lattice is pre-major and actively developing. Existing versions, interfaces, and deployments are
  not stable compatibility commitments. Favor correctness, security, and measured optimization.
- Necessary breaking changes are allowed before the first major release. Update affected callers,
  interfaces, tests, scripts, and documentation together; explain the consequences.
- Fresh deployments may replace development deployments. Upgrades, redeployments, or both are valid
  strategies. Do not preserve a flawed design solely for compatibility with a development instance.
- A non-upgradeable deployed contract is not a stable implementation. LatticeRegistry and
  LatticeFactory still require rigorous testing, design comparisons, review, and optimization
  before production use; see issue #176.
- The published [versioning policy](README.md#versioning-and-compatibility) is the exception to the
  points above, and this policy does not override it. Once a module is live on any network (a
  release deployment, a Lattice demo, or a known downstream deployment), its ERC-7201 namespace and
  interfaceId are frozen: append to its storage struct only, and keep its selector set. Mark any
  ABI or storage break of an undeployed module with `!`. A `fix:` or other patch-level change never
  changes a storage layout, a selector set or interfaceId, or the `LatticeRegistry`/`LatticeFactory`
  bytecode; title such a change `feat` or with `!` so Release Please cuts a minor.
- For material architecture decisions, compare the current design with credible alternatives.
  Explain correctness guarantees, trust assumptions, complexity, deployment consequences, gas,
  and bytecode tradeoffs. Measure optimization claims; label estimates. Do not implement every
  alternative or add abstractions without a demonstrated need.

## Git workflow and authorization

- Start new implementation branches from up-to-date `dev` and target PRs at `dev` by default.
  Follow an explicit user request for a different base or target.
- Use descriptive conventional branch names identifying the work, such as
  `feat/registry-factory-optimization`, `fix/storage-layout-validation`,
  `docs/project-instructions`, or `revert/ens-grant-merge`. Never use `codex/` or agent-name prefixes.
- Commit subjects and PR titles follow Conventional Commits with the types in
  `release-please-config.json` (`feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `build`, `ci`,
  `chore`). Mark a breaking change with `!` and a `BREAKING CHANGE:` footer stating what integrators
  must change. Commits must be signed.
- Name each issue a PR completes on its own `Closes #N` line in the PR body (`Refs #N` for partial
  work). GitHub ignores closing keywords in PRs into `dev`, so
  `.github/workflows/close-linked-issues.yml` closes those issues when the PR merges.
- An implementation request authorizes local commits, pushing a feature branch, and opening a PR
  after the required validation. No additional permission is needed for those steps.
- Merging PRs, promoting to `main`, publishing releases, and deploying contracts or sites require
  explicit user authorization. An implementation request, passing CI, or “continue” alone does
  not authorize them. Do not enable automatic merging without explicit authorization.
- Preserve unrelated local changes. Stage only task-related files; never discard or include the
  user's unrelated work. Do not rewrite shared history without explicit authorization.

## Toolchain and implementation choices

- Pin one current latest stable Foundry release uniformly across local development and CI,
  including builds, tests, formatting, and documentation. Verify the current release when setting
  or updating the pin; do not use a floating release or split versions to work around incompatibility.
- Recorded exception (user-approved 2026-09-12, kept 2026-10-08): Hedera `forge script` work runs on
  Foundry 1.7.1 through `script/config/hedera/forge-hedera.sh`. By default every 1.8 release
  measured (1.8.1, 1.8.3, 1.8.5) fetches fork state with EIP-1898 block-hash objects, which Hedera's
  JSON-RPC relay rejects. Foundry 1.8.5 adds `--fork-state-by-number`, which passed a `forge script`
  simulation and the forking test on 2026-10-08 but is not yet verified for a broadcast. Under
  `[profile.hedera]` both versions emit identical bytecode (`docs/guides/hedera.md`). CI and all
  other work stay on the shared pin. #227 tracks retiring the exception once the shared pin is
  verified end to end. Do not extend the exception to other chains.
- Adapt the implementation to the shared toolchain and surface compatibility problems. Do not
  silently downgrade an individual job or change unrelated toolchain settings.
- Improve existing scripts, helpers, and workflows first. Require user approval before replacing
  an existing script's implementation language or introducing a new runtime dependency.
- Reuse existing repository patterns and tools; prefer standard-library/native capabilities and
  minimal changes. Trace callers and fix the shared root cause rather than only one symptom.

## Repository map and commands

| Path | Contents |
| --- | --- |
| `src/interfaces/<area>/I<Module>.sol` | Module ABI, errors, events (`src/interfaces/external/` holds vendored third-party subsets) |
| `src/<area>/libraries/<Module>Lib.sol` | Module logic, ERC-7201 storage, `registerInterface`, `__<Module>_init` |
| `src/<area>/<Module>.sol`, `<Module>Init.sol` | Stateless facet with `exportSelectors()`; optional standalone init |
| `script/base/<area>/Deploy<Module>.s.sol` | Deploy recipe (`buildCuts` + `run`), shared by deploys and tests |
| `script/lib/FacetInventory.sol` | Release inventory; also drives `ExportSelectorsParityTest` |
| `script/upgrades/` | Storage-layout guard, probe and baseline |
| `script/README.md` | Map of every `script/` folder, its entry points and Makefile targets |
| `test/` | Layout and conventions in [test/README.md](test/README.md) |

Adding a module touches more than its three source files: follow the
[add-a-module checklist](CONTRIBUTING.md#adding-a-module).

| Command | Purpose |
| --- | --- |
| `make install` | Fetch submodules |
| `make build` / `make test` | Compile / run tests (`MATCH=<Contract>` filters) |
| `make test-path PATH_GLOB=...` | Run tests by path |
| `make test-fork` | Fork suites (RPC-gated; unset lanes skip) |
| `make fmt` / `make fmt-check` | Format / formatting gate |
| `make sizes` | EIP-170 size gate under `FOUNDRY_PROFILE=ci` |
| `make via-ir` | IR-pipeline parity build |
| `make storage-check` / `make storage-update` | Verify / regenerate the storage-layout baseline |
| `make test-ci` | Full suite under `FOUNDRY_PROFILE=ci` |
| `make ci` | CI's Solidity gates in CI order (`fmt-check license-check scripts-check readme-check sizes via-ir storage-check test-ci snapshot-check`); CI also runs a via-ir size gate, Slither (`make slither`) and Anvil deploy checks (`make check-atomic-deploy` needs `make anvil`) |
| `make clean` | `forge clean`; run it before trusting gates after tools touched the tree |
| `make help` | Every target, including deploy and demo targets |

## Validation and readiness

- Run focused tests during development, followed by the full test suite before opening a PR.
  Use `forge test`; clearly distinguish local/offline coverage from RPC-dependent fork coverage.
- Check formatting with `forge fmt --check`. For behavior changes, add meaningful regressions and
  relevant integration tests; use fuzz and stateful invariant tests where state/sequence risks apply.
- Run applicable storage, interface/namespace, deployment-size, gas, and security checks. Use the
  repository's existing workflows and commands, including
  `script/upgrades/check-storage-layout.sh` and
  `FOUNDRY_PROFILE=ci forge build --locked --sizes --skip test script` where relevant.
- Document intentional storage incompatibility instead of bypassing a failing check. Baseline
  updates must correspond to reviewed source changes and the chosen deployment/upgrade strategy.
- Report failures and environmental blockers accurately. A partial or filtered run is not a full
  pass, and passing tests or CI is not an audit or proof of production readiness. If required
  validation cannot complete, report the blocker before opening a PR rather than silently waiving it.
- Reports and PR descriptions should explain what changed, why, validation, and remaining limits.
  Distinguish local implementation, public artifacts, deployments, and accepted grant evidence.

## Solidity architecture and storage

- Modules follow the existing interface/library/facet pattern: interfaces define ABI/errors/events;
  libraries own logic and storage access; facets are thin stateless forwarding contracts. Keep
  standalone contracts such as Registry and Factory standalone unless a justified design change
  explicitly revisits that choice.
- State belongs to the diamond rather than its facets. Use unique, precomputed ERC-7201 namespaces
  for module storage; consult `STORAGE_REGISTRY.md` and verify slot/interface constants.
- For upgrades preserving existing state, maintain compatible storage layouts (normally append-only)
  or provide an explicitly designed and tested migration. Reordering, removing, or retyping fields
  must never silently corrupt an existing instance.
- For fresh pre-major deployments, necessary layout changes are permitted. State that a fresh
  deployment is required, update baselines and consumers, and do not present incompatible code as
  safe to apply to an existing deployment. This qualifies older unconditional append-only wording.
- A namespace or interfaceId is frozen once it is live on any network, including a downstream
  project's deployment. From then on its layout follows the upgrade rule above, and the fresh-deployment
  exception no longer applies to it.
- Retain existing external-source attribution and ERC-165 conventions below.

## Specification storage

- Never store specifications, implementation/design plans, or planning Markdown in this repository
  or a worktree unless the user explicitly overrides that rule for the specific document.
- Store such documents outside the repository (the maintainer uses `~/.codex/specs/`), verify the
  destination is outside a Git worktree, and return the absolute path. This requested `AGENTS.md` is project guidance.

## External-source attribution (always)

Any file whose code is ported, adapted, vendored from, or inspired by an external source — including
integration adapters/facades that exist to wrap one specific external protocol — MUST credit that source with
a single natspec line placed immediately after the personal `@author` line (or after `@title` if there is no
author line):

```solidity
/// @author Modified from <SourceName> (<github-link|resource-link>)
```

- The facet, its `*Lib`, AND its first-party interface each carry the line (precedent: `BandAdapter`,
  `BandAdapterLib`, `IBandAdapter`).
- Files under `src/interfaces/external/` use the vendored style instead:
  `/// @author Vendored minimal subset of <SourceName> (<link>).` followed by
  `///         Upstream license: <SPDX id>.` (the upstream file's own tag; `unknown` if it cannot be found).
  An interface re-declared from a BUSL-1.1 (or other non-copyable) upstream without copying its text
  says `/// @author ABI-equivalent interface authored fresh from <Source>'s public ABI (<link>).` instead,
  still followed by the `Upstream license:` note (precedents: `IStargate`, `IComet`).
  Add a row for the file to the third-party interface table in `lib/VENDORED.md`. `make license-check`
  rejects `@author Modified from` there, requires one of the two `@author` forms plus the
  `Upstream license:` note (except under `ercs/` and `seal/`, where `IERC8153` is pinned by the registry and
  factory bytecode and four files still lack the note), and requires the table row.
- Every `.sol` file starts with an SPDX line; every id in its expression other than MIT needs its text at
  `LICENSES/<id>.txt`.
- OZ-ported modules may use `/// @author Adapted for EIP-2535 from OpenZeppelin ... (<link>[, commit <sha>])`.
- Every attribution line must contain a link. Use a file-precise `blob/master` link only when certain the
  upstream path exists; a repo-root link is the accepted fallback. Never fabricate a source or deep path.
- `*Init.sol` contracts, deploy scripts, and genuinely original Lattice logic carry NO attribution line.
- When creating any new file, add the attribution line at creation time — not retroactively.

## `registerInterface` standard (always)

ERC-165 registration in a `*Lib` uses a **precomputed** file-level map-slot constant and a single `sstore` —
never a runtime keccak, never a bare hex literal in the `sstore`, and never a local copy of the ERC-165
storage root (`0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200`):

```solidity
/// @dev 0xa777cf1b is `type(ICCTPBridgeAdapter).interfaceId`.
/// `keccak256(abi.encode(bytes4(0xa777cf1b), 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200))`.
bytes32 constant ERC165_MAP_ICCTPBRIDGEADAPTER_SLOT =
    0x30c377002135d1e8af7caedae6ec2adb3221e5a36ce695d62defb43a35cd29eb;

function registerInterface() internal {
    assembly ("memory-safe") {
        sstore(ERC165_MAP_ICCTPBRIDGEADAPTER_SLOT, true)
    }
}
```

- Constant name: `ERC165_MAP_<INTERFACE-NAME-UPPERCASED>_SLOT`; the `@dev` comment states the interfaceId and
  the full derivation.
- Multiple interfaces → `registerInterfaces()` with one `sstore` per precomputed constant (precedent:
  `ERC721Lib`).
- Adapters registering a SHARED interface id (e.g. `IERC7786GatewaySource`, `0x11967553`) declare the same
  constant/value in their own file with the SHARED note (precedent: `LayerZeroGatewayAdapterLib`).
- Verify the precomputed value with a throwaway forge test and keep the module's `test_SupportsInterface`
  test — the read path recomputes the keccak at runtime, so it catches a wrong constant.

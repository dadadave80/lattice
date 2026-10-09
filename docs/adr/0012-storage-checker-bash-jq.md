# 0012. The storage-layout checker stays in Bash and jq

- **Status:** Accepted
- **Date:** raised on [#177](https://github.com/dadadave80/lattice/issues/177); settled when
  [#316](https://github.com/dadadave80/lattice/pull/316) moved the Bash checker into the storage-safety
  Action (2026-10-09); recorded 2026-10-09

## Context

The append-only rule ([0008](0008-freeze-once-live.md)) needs a check that reads real struct layouts.
Solc emits no storage layout for a struct reached only through an assembly slot cast
([0002](0002-erc7201-namespaced-storage.md)), so the checker compiles a probe contract that declares
each struct as a state variable and compares the layouts. #177 also asked for the check as a reusable
GitHub Action for any Foundry project. Draft PR #179, since closed, had rewritten the checker in Python,
which was never approved, and AGENTS.md requires approval to change a script's language or add a runtime
dependency.

## Options considered

1. **Extend the existing Bash checker with jq.** It stays within the tools CI already needs (`bash`,
   `jq`, `git`, `forge`, `cast`), at the cost of harder-to-read recursive comparison in jq.
2. **Approve Python for the Action.** The #179 rewrite already existed with its own tests, but it would
   add a language to the gate and make `make ci` need `python3` locally.

## Decision

- The checker is one Bash script,
  [`.github/actions/storage-layout/check-storage-layout.sh`](../../.github/actions/storage-layout/check-storage-layout.sh),
  using `jq`, `git`, `forge` and `cast`. Lattice runs it through
  [`script/upgrades/check-storage-layout.sh`](../../script/upgrades/check-storage-layout.sh) with its own
  probe, baseline and resets file, and the Action runs the same script for any consumer.
- The guarded set is every `@custom:storage-location erc7201:` annotation under `src`, so there is no
  manifest or list to keep in sync. Each struct's layout must come from the struct declared in its
  annotated file (matched by AST id), and the declaring file must contain the namespace's derived slot.

## Consequences

- `make ci` and the Action need no runtime beyond the Foundry toolchain, `jq` and `git`.
- A new namespaced struct fails the check until the probe imports it and the baseline is regenerated, so
  adding one takes the probe import and `make storage-update` and nothing else.
- Struct comparison logic in jq is denser than the Python equivalent, so its behaviour rests on the
  regression suite below.

## Confirmation

- `script/test-storage-layout.sh` (run by `make scripts-check`) drives the checker over a fixture consumer
  project and asserts its exit status and reason for each case.
- CI runs the Action against the same fixture as a consumer repository, and `make storage-check` runs it on
  Lattice.

## References

- [Storage-safety Action](../../.github/actions/storage-layout/README.md)
- [#177](https://github.com/dadadave80/lattice/issues/177), [#179](https://github.com/dadadave80/lattice/pull/179),
  [#316](https://github.com/dadadave80/lattice/pull/316)

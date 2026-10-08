<!--
Title: a Conventional Commit, such as `fix(vaults): cap withdrawals at idle`. Add `!` for a breaking
change and a `BREAKING CHANGE:` footer saying what integrators must change.
Base branch: `dev`. Only release promotions target `main`.
-->

## Summary

<!-- What changed and why. -->

<!--
One `Closes #N` line per issue this PR completes; use `Refs #N` for partial work.
-->
Closes #

## Validation

<!-- The commands you ran and their results. Name the fork lanes you ran, or say none. -->

## Checklist

The full gate list is in
[CONTRIBUTING.md: Before you open a PR](https://github.com/dadadave80/lattice/blob/main/CONTRIBUTING.md#before-you-open-a-pr).
These are the steps most often missed.

- [ ] The PR targets `dev`, the title is a Conventional Commit, and every commit is signed.
- [ ] `make ci` and `make slither` pass. A gas change commits the `make snapshot` diff.
- [ ] A behavior change has regression tests through a diamond built from the module's recipe, and the
      Validation section separates offline coverage from fork coverage.
- [ ] A new or changed ERC-7201 struct is imported into `script/upgrades/StorageLayoutProbe.sol`, its
      baseline diff from `make storage-update` is reviewed, and `STORAGE_REGISTRY.md` has its row.
- [ ] A new interface has its `ERC165_MAP_I<MODULE>_SLOT` constant and `registerInterface()`, per the
      [`registerInterface` standard](https://github.com/dadadave80/lattice/blob/main/AGENTS.md#registerinterface-standard-always),
      plus a slot test.
- [ ] Ported or adapted code carries the
      [attribution line](https://github.com/dadadave80/lattice/blob/main/AGENTS.md#external-source-attribution-always).
- [ ] No namespace or interfaceId that is live on any network has changed.

Passing CI is not an audit.

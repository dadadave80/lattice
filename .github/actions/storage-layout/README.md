# ERC-7201 storage-safety Action

A composite GitHub Action that keeps the [ERC-7201](https://eips.ethereum.org/EIPS/eip-7201) namespaced
storage of a Foundry project upgrade-safe. It fails when a guarded struct:

- **drifts** from the project's committed baseline (a layout change nobody reviewed), or
- is **not an append-only extension** of the baseline at a trusted commit, such as the pull request's
  base: a field was reordered, retyped, resized, renamed or removed, a namespace or slot changed, or a
  nested struct changed.

It is written in Bash with `jq`, `git`, `forge` and `cast`, needs no Lattice sources or Solidity
dependency, and runs the same script Lattice runs on every one of its own namespaces
(`make storage-check`).

## What it checks

1. **Every annotated struct is guarded.** The checker scans the source directory for
   `@custom:storage-location erc7201:<namespace>` annotations, each directly above its `struct`. There is no
   manifest to keep in sync: a new namespaced struct is checked as soon as it exists, and fails until the
   probe covers it.
2. **The namespace is the one the library uses.** The file that declares the struct must contain the slot
   `cast index-erc7201 <namespace>` derives, as a literal (normally the `bytes32` constant its accessor loads).
3. **The layout comes from the real struct.** A probe contract imports each struct and declares a state
   variable of it, so solc lays it out. The checker compiles the probe and the files it imports once, in a
   temporary directory (your `out/` and `cache/` are never read or written), and requires each guarded
   struct's layout to carry the compiler's AST id of the struct declared in its annotated file. A probe that
   lays out a copy of a struct instead (redeclared in the probe or in any other file, under any import
   alias) fails closed, as does a probe that omits a struct or does not import its file.
4. **Drift.** Each struct's members are normalized to `slot offset label type` rows (compiler AST ids are
   stripped), with a `(nested)` section for every struct reachable from a guarded one. The result must equal
   the committed baseline.
5. **Compatibility with `baseline-ref`.** Against the baseline committed at the trusted ref, every old
   section must still exist with the same header (struct name, namespace and slot); a top-level struct's old
   rows must be an exact prefix of its new rows; a nested struct must be identical. Because the trusted
   baseline comes from git history, regenerating the baseline in the same pull request cannot hide an
   incompatible change.

Exit status: `0` pass, `1` a layout check failed (the output names the struct and the old and new rows),
`2` a usage or environment error (missing tool, file or ref, compile failure, empty probe output, a
probe that lays out a copy, or two structs or namespaces that share a name).

## Set up a consumer project

1. Annotate each storage struct and keep its slot as a literal in the same file:

   ```solidity
   /// @custom:storage-location erc7201:example.storage.Vault
   struct VaultStorage {
       address owner;
       uint256 totalAssets;
   }

   library VaultLib {
       /// @dev `cast index-erc7201 example.storage.Vault`.
       bytes32 internal constant VAULT_STORAGE_SLOT =
           0x…; // the value cast prints
   }
   ```

2. Add a compile-only probe, for example `script/StorageProbe.sol`, that imports every guarded struct from
   the file that declares it and declares one state variable per struct:

   ```solidity
   import {VaultStorage} from "../src/VaultLib.sol";

   contract StorageProbe {
       VaultStorage internal vault;
   }
   ```

3. Generate the baseline locally, review it and commit it. The checker is in this directory; run it from a
   checkout of this repository at the same commit as the Action you pin:

   ```sh
   path/to/lattice/.github/actions/storage-layout/check-storage-layout.sh \
     --root . --probe script/StorageProbe.sol:StorageProbe --baseline storage-layout.baseline --update
   ```

4. Add the workflow. The first pull request that adds the baseline has nothing to compare with, so it checks
   drift only; every later pull request compares with its base.

   ```yaml
   permissions:
     contents: read
   jobs:
     storage-layout:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@<full-sha>  # pin every action by full commit SHA
           with:
             submodules: recursive
             persist-credentials: false
         - uses: foundry-rs/foundry-toolchain@<full-sha>
           with:
             version: v1.8.5
         - name: Fetch the PR base
           if: github.event_name == 'pull_request'
           env:
             BASE: ${{ github.event.pull_request.base.sha }}
           run: git fetch --no-tags --depth=1 origin "$BASE"
         - uses: dadadave80/lattice/.github/actions/storage-layout@<full-sha>  # see "Versions" below
           with:
             probe: script/StorageProbe.sol:StorageProbe
             baseline: storage-layout.baseline
             baseline-ref: ${{ github.event.pull_request.base.sha }}
   ```

   Take `baseline-ref` from the event in the workflow, never from a file the pull request can edit. To check
   pushes too, pass `github.event.before` (an all-zero SHA on a new branch has no baseline, so skip that case),
   or a release tag that you fetch explicitly.

## Inputs

| Input | Default | Meaning |
| --- | --- | --- |
| `working-directory` | `.` | Foundry project root, relative to the workspace. Paths with spaces work. |
| `probe` | required | Probe contract, `path/To.sol:Name` (or a bare name declared in exactly one file). |
| `baseline` | required | Committed baseline, relative to `working-directory`. |
| `baseline-ref` | empty | Trusted commit for the compatibility check, already fetched. Empty checks drift only and warns. |
| `resets` | empty | Reviewed fresh-deployment resets file, relative to `working-directory`. |
| `src` | profile `src` | Directory scanned for annotations. |
| `foundry-profile` | `default` | Profile used to compile and inspect the probe. |

The Action installs nothing. The runner needs `forge` and `cast` (install Foundry first), `jq` and `git`;
GitHub's Ubuntu runners include `jq` and `git`. Lattice CI runs it on `ubuntu-latest` with Foundry v1.8.5,
and it also runs on macOS.

## Changing a layout

- **Append a field** to the end of a top-level struct, run the checker with `--update`, and commit the
  regenerated baseline with the change. The compatibility check passes because the old rows are a prefix of
  the new ones. A field appended into a slot's free bytes (a packed tail) is also an append.
- **Anything else** fails: reordering, retyping, resizing, renaming or removing a field, changing a namespace,
  or any change to a nested struct. A nested append is rejected on purpose: it shifts every later element of
  an array of that struct, and every later field of a parent that embeds it.
- **A fresh deployment** may need a layout that no existing deployment can upgrade to, for example before a
  module is first released. The failure output prints a line such as `VaultStorage 231c2131051f`. Add that line
  to the resets file (one entry per line, `#` starts a comment) and pass the file as `resets`, in the same pull
  request as the change. The hash names the struct's layout at `baseline-ref`, so the entry applies only while
  the trusted ref still holds that layout. An entry that matches the trusted ref but waives nothing (the layout
  is still compatible, for example because the change was reverted) fails the check, so a reset cannot be
  added ahead of a change or stay armed after one. After the merge, the trusted baseline of later pull
  requests into the same branch has moved on, and the entry only prints a note that it has no effect there.
  Keep it until every branch the change is promoted to has merged it (a release pull request compares with
  the release branch, which still holds the old layout), then delete it. A reset is a reviewed decision that
  no live deployment holds that storage; never reset a namespace that is live on any network.

## Limits

- It checks the declared, compiled layouts of annotated structs. It cannot prove that assembly elsewhere uses
  only those slots, find storage that has no annotation, or judge semantic upgrade safety (initializers,
  authority, the meaning of a reused field). A green check is not an audit.
- `storageLayout` records an enum as `t_enum(Name)`, so reordering an enum's members is invisible to it.
- Struct names must be unique within the probe, because sections are keyed by name: two annotated structs, or
  two distinct structs reachable from the probe, with one name stop the check (exit `2`).
- It guards the baseline and the code at the trusted ref only as well as your branch protection guards them.
  A pull request can also edit the workflow that calls the Action, so require review for workflow changes.

## Versions

Pin the Action by full commit SHA and note the release tag in a comment, as for any third-party action. The
compatibility check reads baselines written by this checker. Lattice's tags `v0.1.0` to `v0.4.0` carry a
baseline from an older checker that labelled two nested structs of `lattice.storage.ChainRegistry` with
their parent's namespace instead of `(nested)`. The current checker never writes one namespace on two
sections, so when the trusted baseline does, it compares those sections as nested structs (rows identical)
and prints a note, so that labelling alone does not fail a comparison with those tags or a release pull
request from `dev` into `main`.

## Testing the Action

In this repository, `script/test-storage-layout.sh` (part of `make scripts-check`) runs 43 cases against the
fixture project in [`fixture/`](fixture): identical and AST-id-only changes, a struct declared inside its
library, appends, reorders, removals, resizes, renames, namespace and mapping changes, nested changes, stale
baselines, used, unused and stale resets, older-checker baselines, mirror probes (in the probe, aliased, and
from a side file), shared struct names and namespaces, and missing inputs. CI also calls the Action on that
fixture as a consumer would, and requires it to fail on a reordered struct whose baseline was regenerated in
the same commit.

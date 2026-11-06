# 0019. Temporary allowances share the base allowance path

- **Status:** Accepted
- **Date:** 2026-11-06 ([#235](https://github.com/dadadave80/lattice/issues/235), related to [#234](https://github.com/dadadave80/lattice/issues/234))

## Context

ERC-7674 adds transaction-scoped grants to ordinary approval. Replacing the base ERC20 facet's two allowance
selectors would miss `burnFrom`, flash-mint repayment, votes `transferFrom` and approved vault exits, which call
`ERC20Lib._spendAllowance` internally. Existing live ERC20 namespaces and interface IDs are frozen.
[0015](0015-canonical-cancun-build.md) selected Cancun as the canonical minimum; compiler-emitted MCOPY already
means these artifacts do not promise execution on older runtimes.

## Options considered

1. **Always read the shared transient allowance.** The empty namespace reads zero without a public grant facet;
   every spender applies one policy and no persistent storage or activation state is added. Selected.
2. **An appended enable flag.** Correct but costs a cold persistent read on ordinary spends. The measured
   flag version costs more gas and bytes; no verified pre-Cancun deployment commitment justifies that state.
3. **Only replace public allowance/transferFrom.** Rejected because other spend paths would disagree.
4. **General token hooks or a dispatcher.** Unnecessary for this allowance policy; movement-policy changes
   remain a separate decision under [0009](0009-token-extension-hook-model.md) and #172.

The isolated comparison used the same token runtime/ABI fixture, solc 0.8.36, optimizer 1,000,000, legacy pipeline
and Cancun on Foundry 1.9.0. Cold persistent spend fell from **40,495 to 39,010 gas** when the flag was removed;
the flag-enabled case was 41,149 gas. Cold temporary approval fell 31,747 to 29,621; a temporary-covered warm
spend fell 31,865 to 31,732; a mixed warm spend fell 37,343 to 37,204. Warm snapshots exclude the prior grant
and batch/actor dispatch. Base ERC20 runtime fell **3,616 to 3,515 bytes** (101 bytes); the paired gas token
fell 4,997 to 4,733 (264 bytes). These comparisons measure the flag alternative, not a saving over old ERC20.

## Decision

The shared ERC20 getter saturates the persistent-plus-temporary sum at uint256 max. Its shared spender consumes
finite temporary allowance first and preserves an infinite grant. A fully covered spend never loads persistent
allowance. Native transient state uses a distinct, precomputed ERC-7201-derived mapping root under the diamond's
address. Failed calls roll back both allowance types; transient state clears at transaction end. The additive
facet exports only the standard `temporaryApprove` selector and emits no approval events. Its stateless,
guarded initializer registers a separately precomputed ERC-165 slot. No activation switch is required.

This is an allowance integration, not a change to [0009](0009-token-extension-hook-model.md)'s movement model.
The pinned OpenZeppelin parity baseline is 5.6.1; the 5.7 additions in #234 are deferred. The separate #235
ERC1363/incompatible-movement-pair acceptance condition was completed by the checked-recipe follow-up in
[0026](0026-checked-recipe-data-and-seams.md). That restriction applies to checked script composition;
arbitrary authorized diamond cuts can bypass it. The shared allowance policy remains unchanged.

## Consequences

- The original storage layout and IERC20 interfaceId remain unchanged; no persistent fields are added.
- All matching allowance readers/spenders require EIP-1153, even without this public grant facet installed.
  This follows the canonical Cancun minimum and uses no chain-ID shortcut or persistent fallback.
- Every ordinary spend pays for the empty transient read and key derivation. Final measurements are committed
  in `snapshots/ERC20GasTest.json` and `snapshots/ERC20TemporaryApproval.json`; base and registered-interface
  cases use identical runtime code, with registration affecting discovery only.
- A diamond upgrade must replace every allowance reader/spender compiled with older shared library code,
  including custom facets, when adding the public temporary API. Adding this facet alone cannot alter old
  spender code. Fresh recipes assemble matching versions; application reinitializers register discovery.
- Ordinary approve/permit updates affect only persistent allowance. Users must batch grant and spend in one
  transaction; a persistent revocation does not revoke a live temporary grant in that transaction.
- No new runtime dependency, public temporary-allowance getter, future policy field or general hook is introduced.

## Confirmation

`ERC20TemporaryApprovalTest` checks nested same-transaction use, non-vacuous next-transaction clearing,
infinite/overflow behavior, events, rollback, unchanged storage, additive use without an activation field,
and two proxies sharing facets. Its storage-access test proves a covered spend skips persistent allowance.
`ERC20TemporaryApprovalCompositionTest` exercises all other shared spenders through real production recipes.
`StorageSlotVerificationTest`, release export parity, layout/JSON guards, recipe upgrade guards, source size
checks, and the paired gas suite enforce the remaining boundaries.

## References

- [ERC-7674](https://eips.ethereum.org/EIPS/eip-7674)
- [OpenZeppelin 5.6.1 source](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/5fd1781b1454fd1ef8e722282f86f9293cacf256/contracts/token/ERC20/extensions/draft-ERC20TemporaryApproval.sol)
- [Allowance integration and upgrade requirements](../guides/selector-compatibility.md#erc-7674-temporary-allowances)
- [ERC20Lib](../../src/tokens/ERC20/libraries/ERC20Lib.sol), [temporary logic](../../src/tokens/ERC20/libraries/ERC20TemporaryApprovalLib.sol)

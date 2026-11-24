# 0033. ERC-7984 diamonds exclude diamond callers

- **Status:** Accepted
- **Date:** 2026-11-22

## Context

The ERC-7984 (confidential fungible token) module stores every balance, every transferred amount and the
total supply as handles (32-byte references to ciphertexts) in Zama's FHEVM (fully homomorphic encryption
virtual machine). Zama's access control list (ACL) contract decides who may use or decrypt each handle. It
authorizes by `msg.sender`, its grants are irrevocable, and the token grants itself every handle it stores. So
the diamond is persistently allowed on every balance, every transferred amount and the total supply.

Two consequences follow. Anything that can make the diamond act as itself can decrypt or publish any balance:
a facet that calls a target its caller chooses (an executor, a Governor, a timelock), a facet that makes the
diamond call itself, a cut initializer, or the key of an externally owned account (EOA) that hosts the diamond
under EIP-7702 (Ethereum Improvement Proposal 7702, code delegation for EOAs). And anything that can sign as
the diamond can user-decrypt any balance off chain: the holder is also allowed on its balance, so a user
decryption with user = diamond and contract = holder meets every rule of Zama's key management service (KMS).
An ERC-1271 (contract signature validation) facet's signers can sign as the diamond, and so can a delegated
EOA's key.

Lattice diamonds compose facets freely, and the module is ported from OpenZeppelin Confidential Contracts
0.5.3, which assumes it is alone at its address. This record fixes what an ERC-7984 diamond may contain, how
that is enforced, and the rule that binds every later confidential extension.

## Decision

**Three exclusion layers.**

1. **Recipe rule.** `RecipePlanLib.validateEarly` rejects `ERC7984` next to any of 14 facets with
   `IncompatibleRecipeFacets("ERC7984", name)`: `AccessManager`, `TimelockController`, `Governor`,
   `ERC7821Executor`, `ERC7579ModuleConfig`, `ERC6551Account`, `ERC6900Executor`, `AggregatorExecAdapter`,
   `HSSAdapter`, `HSSAdapterRecovery`, `GovernedDiamondCut`, `CrosschainTimelockHandler`, `ERC1271Signature`
   and `ERC6900Signature`. It binds every checked recipe script.
2. **Deny-list and host refusal in the library initializer.** `ERC7984Lib.__ERC7984_init` reverts
   `ERC7984DiamondCallerInstalled(selector, facet)` if the diamond routes any of 15 selectors: the entry points
   through which the ten executor facets make the diamond call a target its caller chooses, and ERC-1271
   `isValidSignature` (`0x1626ba7e`). It then reverts `ERC7984DelegatedHost(address(this))` if the host's code
   starts with the EIP-7702 delegation designator `0xef0100`. Both checks run before any configuration is
   written. They live in the library, not in `ERC7984Init`, so a composite initializer that calls
   `__ERC7984_init` (such as `ERC7984MintableInit`) inherits them, and they bind `LatticeFactory.deploy` and
   compositions that never pass through `validateEarly`. The check runs once: a facet cut in by a later upgrade
   is caught by nobody, which is the upgrade-authority consequence below.
3. **Entry guard.** `ERC7984Lib.guard()` runs first in every state-changing entrypoint that acts on handles
   (deviation 1 below).

**Upgrade authority is decryption authority.** Any cut initializer runs as the diamond, so whoever can cut can
decrypt every balance, forever, because grants are irrevocable. The same holds for anyone the diamond would
validate as a signer: an ERC-1271 validator's signers and a delegated EOA's key. Those are refused by layers 1
and 2; cut authority is accepted and documented. `DeployERC7984`'s immutable variant has no cut facet and no
supply. Its admin variant (`AccessControl` and `AccessControlDiamondCut`) is upgradeable, and its admin can
decrypt until `AccessControlDiamondCut` is cut away. `DeployERC7984Mintable` is the layout with supply and no
upgrade authority.

**Deviations from OpenZeppelin Confidential Contracts 0.5.3.**

1. **Entry guard.** `ERC7984Lib.guard()` runs first on ten entrypoints: the eight movers
   (`confidentialTransfer`, `confidentialTransferFrom`, `confidentialTransferAndCall` and
   `confidentialTransferFromAndCall`, each with an input-proof and a handle overload), `setOperator` and
   `requestDiscloseEncryptedAmount`. A call from the diamond itself reverts
   `ERC7984UnauthorizedCaller(address(this))`, so a self-call relay cannot spend the diamond's ACL grants;
   `Multicall` delegatecalls and keeps the outer sender. Then an unset init marker (the `IERC7984` ERC-165
   (interface detection) map slot, which `__ERC7984_init` writes) reverts `ERC7984NotInitialized()`, so a
   diamond whose shared coprocessor slot was written by some other initializer, without the deny-list, never
   goes live. Views stay open, and so does `discloseEncryptedAmount`, which needs a valid KMS proof and writes
   no storage. `ERC7984Mintable.confidentialMint` calls the guard first too, before its role check.
2. **No receiving at the diamond.** `_transfer` and `_mint` revert `ERC7984InvalidReceiver(address(this))` next
   to the zero-address checks. Without this, the entry guard would strand any balance the diamond held.
3. **Initializer instead of constructor.** `__ERC7984_init` runs the deny-list, the EIP-7702 host refusal, the
   chain-table coprocessor configuration with the repeat semantics of
   [ADR (architecture decision record) 0016](0016-shared-initialization-identity.md), the metadata and the
   ERC-165 registration. It mints nothing and makes no host call.
4. **Lattice library form.** `decimals()` is fixed at 6, the caller is `msg.sender` (no `_msgSender()`), and
   nothing is `virtual`, as with `ERC20Lib`.

**Accepted as inherited behaviour.** These are kept as in OpenZeppelin 0.5.3 and Zama's production tokens,
because closing them would deviate from the ERC:

- Audit finding M-01 of the OpenZeppelin confidential contracts audits: anyone can send a zero-value transfer
  (an empty proof with the zero handle) to any account, which rotates the recipient's balance handle and fires
  its receiver callback. The ERC requires the zero-value events.
- Audit finding M-05: an operator receives transient access to the amount it moves and can request its public
  disclosure.
- Disclosure replay: `discloseEncryptedAmount` is not tied to a request, so the same proof re-emits
  `AmountDisclosed` and changes no state.
- `setOperator(self)` and `setOperator(address(0))` are inert: a holder is always its own operator, and
  `address(0)` never calls.

**No reentrancy guard.** As in OpenZeppelin, Zama's production tokens and Lattice's ERC-1363 (payable token
with receiver callbacks), the module has no lock. It follows checks-effects-interactions (CEI): every check and
the balance and supply writes of the transfer happen before the receiver callback in the `*AndCall` movers.
The refund after the callback is a separate, best-effort balance update, so a receiver that spends during its
callback and then rejects keeps what it spent.

**Rule for every future confidential entrypoint.** A mint, burn, wrapper, votes or any other facet that uses FHE
(fully homomorphic encryption) and takes a caller-supplied handle, moves balances, sets operators or requests
disclosure must:

- call `ERC7984Lib.guard()` first;
- enforce security requirement 1 (SR-01: the caller must be allowed on the handle, `isAllowed(handle,
  msg.sender)`) on every caller-supplied handle;
- on a mint, pass a freshly computed amount handle, such as `FHEVMLib.add(FHEVMLib.asEuint64(0), amount)`,
  while the supply is uninitialized: the first mint's amount handle becomes the total-supply handle, so anyone
  allowed on that amount would be allowed on the supply.

SR-01 alone is not enough: a self-call passes it for every balance, because the diamond is allowed on all of
them. Reviewers apply this rule to any change to a facet that can share a diamond with `ERC7984`, because the
recipe rule and the inventory pin see only names and selectors, not a behaviour change behind an existing
selector.

**The shipped mint.** `ERC7984Mintable.confidentialMint(address to, externalEuint64 encryptedAmount, bytes
inputProof)` (`0x1b4d3d0d`, the selector of OpenZeppelin's `ERC7984Rwa.confidentialMint`) runs, in order:

1. `ERC7984Lib.guard()`, so a self-call reverts even when the diamond holds the role, and an uninitialized
   token reverts;
2. the role check for `ERC7984_MINTER_ROLE` (`AccessControlUnauthorizedAccount`);
3. `fromExternal`, which verifies the input proof; with an empty proof it accepts only a handle the minter is
   already allowed on;
4. while the supply is uninitialized, the first-mint re-derivation `amount = add(asEuint64(0), amount)`, so the
   first supply handle is computed by the diamond and is never the minter's input handle (re-deriving on every
   mint was measured and lowers the per-transaction mint ceiling on a token with supply from 13 to 12);
5. `_mint(to, amount)`;
6. `allow(minted, msg.sender)`, as OpenZeppelin's `ERC7984Rwa` grants its agent.

It has two honest limits, both measured and accepted:

- **Recomputed handles.** Handles are deterministic per block and name no caller, and the library grants the
  minter transient access to its verified input. So a minter that is a contract can, in the same transaction
  as its own mint, recompute and persist grants on handles whose value it chose: the supply handles its own
  consecutive mints produce while it is the only account changing the supply, and a never-credited
  recipient's first balance. It can then publish them with `requestDiscloseEncryptedAmount`. It cannot
  recompute a handle that has an operand it is not allowed on, so its reach ends once another minter changes
  the supply or another account credits the recipient.
- **Overflow bit.** An overflowing mint mints zero, and the minter is allowed on `minted`. So each mint of an
  amount `a` the minter chose reveals whether `S > 2^64-1-a`, where `S` is the live total supply. An
  overflowing mint changes no balance or supply value, so at most 64 mints recover `S` exactly. With no burn,
  `S` is the sum of every successful mint, so this tells a sole minter nothing new, but it reveals the other
  minters' combined mints to any minter. When one holder owns most of the supply, `S` approximates that
  holder's balance. Dropping `allow(minted, msg.sender)` would not prevent it: a minter that mints to itself is
  allowed on `minted` as the recipient.

**`DeployERC7984Mintable` is the supply layout without upgrade authority.** Its facets are `ERC165Facet`,
`ERC7984`, `DiamondLoupeFacet`, `AccessControl` and `ERC7984Mintable`, with no cut facet and no facet that
calls as the diamond.

- Its admin holds `DEFAULT_ADMIN_ROLE`. It can grant or revoke `ERC7984_MINTER_ROLE`, including to itself, so it
  is a supply authority, and it can renounce, which freezes the minter set. It cannot cut, run code as the
  diamond or change a role's admin (the `AccessControl` facet exports no `setRoleAdmin`). Without the minter
  role it obtains no ACL grant at all.
- A minter mints any amount to any account except the zero address and the diamond. It obtains ACL grants only
  on handles whose value it chose (its minted handles and, as a contract, the recomputed handles above), and it
  can learn the total supply through the overflow bit. So can the admin after granting itself the minter role.
  Neither obtains a grant on a handle whose value another account determined.

**Rejected mint surfaces.**

- A plaintext mint: it publishes every amount in calldata, and its first supply handle would equal any
  same-block trivial encryption of that amount.
- A proof-free `euint64` mint overload: it widens the self-call surface for no new capability.
- A burn: holder self-burn against privileged burn over balances the burner cannot see is an open decision.
  `ERC7984Lib._burn` stays for that facet.

**Accepted:** the minter's overflow bit and recomputed grants above, because a minter is a trusted supply
authority and OpenZeppelin's `ERC7984Rwa` has the same overflow bit.

**Polygon deferred.** The chain table in `FHEVMLib` has rows for Ethereum mainnet (1), Sepolia (11155111) and
chain id 31337, which is for local tests only: the recipes omit 31337 from their supported chains and their
conditions name it as local tests only ([ADR 0032](0032-thin-fhevm-host-library.md)). Polygon (137) and Amoy (80002) are added only with a fork test
lane for them.

## Alternatives and consequences

- Enforcing only the recipe rule is rejected: `LatticeFactory.deploy` and hand-built compositions bypass
  `validateEarly`. Enforcing only the deny-list is rejected: a self-call relay needs no deny-listed selector,
  and a token cut without `__ERC7984_init` would skip it.
- Adding a guard inside each executor facet is rejected: it would change the bytecode of released facets.
- An in-diamond Governor, timelock or `GovernedDiamondCut` next to the token is never offered. An upgradeable
  token keeps its cut authority outside the token diamond: a Safe through `SafeDiamondCut`, or through
  `GovernedSafeDiamondCut`, which adds a built-in delay.

Consequences:

- An executor with a non-standard entry point is invisible to the deny-list; reviewers apply this ADR.
- A facet added after the deny-list was frozen is not in it. The inventory pin in `ERC7984RecipeExclusionTest`
  hashes every facet's name and exported selectors, so a new facet or selector fails it and forces a decision.
- Every guarded call pays one extra storage read for the init marker.
- The init marker is an ERC-165 bit, and `ERC6900ModuleManager` writes ERC-165 bits for every interface id in an
  installed module's manifest, gated by the diamond's admin role or the diamond itself. On a hand-built diamond
  that also installs it, the admin can set the marker without `__ERC7984_init` (skipping the deny-list and the
  EIP-7702 host check), or clear it by uninstalling a module installed before initialization, which makes every
  guarded entrypoint revert `ERC7984NotInitialized`. No shipped recipe installs it, and the module guide's
  integrator rule 5 forbids it.
- The admin of `DeployERC7984Mintable` and its minters are trusted with supply and can learn the total supply;
  the recipe conditions and the [module guide](../guides/erc7984.md) state this.

## Confirmation

- `ERC7984InterfaceTest` pins the interface id, event topics and error selectors.
- `ERC7984InitTest` pins the deny-list (`testFuzz_Init_RevertWhen_DiamondCallerInstalled`,
  `test_LibInit_RevertWhen_DiamondCallerInstalled` for a composite initializer), the EIP-7702 refusal
  (`test_Init_RevertWhen_HostIsDelegatedEoa`), the chain table and repeat semantics, and that initialization
  makes no host call (`test_Init_MakesNoHostCall`).
- `ERC7984Test` pins the entry guard (`testFuzz_SelfCall_RevertOnEveryGuardedEntrypoint`,
  `test_SelfCall_ProofBoundToDiamondReverts`, `test_Multicall_KeepsOuterSender`), the init marker
  (`test_Uninitialized_TransferReverts`, `test_ForeignConfigWithoutInit_TransferReverts`), the diamond as
  receiver (`test_Transfer_RevertWhen_ToIsDiamond`, `test_Mint_RevertWhen_ToIsDiamond`), SR-01
  (`test_ConfidentialTransfer_RevertWhen_AmountHandleNotAllowedToSender`), the exact ACL grant sets and the
  inert `setOperator` cases.
- `ERC7984MintableTest` pins the mint order (`test_ConfidentialMint_SelfCallRevertsBeforeTheRoleCheck`,
  `test_ConfidentialMint_RevertWhen_Uninitialized`), the honest minter's grant set
  (`test_ConfidentialMint_GrantsExactAclSet`), the inherited deny-list
  (`test_Init_InheritsTheDiamondCallerDenyList`) and the first-mint re-derivation
  (`test_ConfidentialMint_FirstMintSupplyIsNotTheInputHandle`). Only this test pins the re-derivation; the
  invariant suite does not detect its removal.
- `ERC7984AcceptedHazardsTest` pins the accepted rows: M-01 (`test_ZeroHandleEmptyProofTransfer_ByStranger`),
  M-05 (`test_RequestDisclose_ByOperatorWithTransientAccess`), replay
  (`test_Disclose_ReplayEmitsAgainAndChangesNoState`), reentrancy
  (`test_TransferAndCall_ReceiverReentersTransfer`, `test_TransferAndCall_ReceiverReentersAndCall`) and the
  mint limits (`test_ConfidentialMint_MinterLearnsOverflowBit`,
  `test_ConfidentialMint_OverflowBitIsASupplyThresholdOracle`,
  `test_ConfidentialMint_RecomputingMinterGetsGrantsOnlyOnValuesItChose`,
  `test_ConfidentialMint_EmptyProofMintsAHandleTheMinterHolds`).
- `ERC7984LimitsTest` pins the per-transaction ceilings and liveness under an ACL pause.
- `ERC7984RecipeExclusionTest` pins the 14-name rule (`test_RejectsEveryDiamondCallerNextToERC7984`), the
  accepted layouts (`test_AcceptsExternallyGovernedUpgradeLayouts`, `test_AcceptsMintableLayout`) and the
  inventory pin (`test_InventoryPinnedForDiamondCallerReview`).
- `ERC7984CompositionHazardsTest` characterizes what the layers do not catch and the upgrade-authority
  consequence (`test_LaterCutTimelockGrantsDecryptionOfAnyBalance`, `test_AdminCutInitializerGrantsDecryption`,
  `test_GuardMissesNonStandardExecutor`, `test_SelfCallRelayCannotDisclose`,
  `test_HolderAndDiamondBothAllowed_UserDecryptPrecondition`), and that the no-cut mintable token's admin gets
  no ACL grant (`test_NoCutMintableToken_AdminGetsNoAclGrant`).
- `ERC7984Invariant` checks supply conservation under confidential mints and reentrant receivers, the honest
  minter's balance and supply grant sets, and that the diamond never holds tokens.
- `RecipeUpgradeabilityTokensTest` pins both recipes' upgradeability (`test_Immutable_ERC7984`,
  `test_Upgradeable_ERC7984`, `test_Immutable_ERC7984Mintable`).

## References

- [ADR 0006](0006-atomic-factory-initialization.md)
- [ADR 0016](0016-shared-initialization-identity.md)
- [ADR 0032](0032-thin-fhevm-host-library.md)
- [ERC-7984 module guide](../guides/erc7984.md)
- [Composition hazards](../guides/compose-your-own-diamond.md#composition-hazards)
- [`SECURITY.md`](../../SECURITY.md#confidential-tokens-zama-fhevm)

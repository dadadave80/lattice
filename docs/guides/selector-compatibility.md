# Selector compatibility

Two facets that export the same selector cannot both `Add` it to one diamond: the second cut reverts with
`CannotAddFunctionToDiamondThatAlreadyExists(selector)`. A `Replace` does not revert. It silently routes the
selector to the later facet. This page lists every selector that two or more release facets export, and how to
treat each one. The [composition hazards](compose-your-own-diamond.md#composition-hazards) table explains the
cases that cost more than a failed deploy.

The table is generated. [`SelectorCompatibilityTest`](../../test/composability/SelectorCompatibilityTest.t.sol)
deploys every facet in [`FacetInventory`](../../script/lib/FacetInventory.sol), reads each one's ERC-8153
`exportSelectors()`, and checks the result against its hand classification. A new shared selector, a change in
which facets share one, or a row that no longer clashes fails the test. After updating the classification,
regenerate the table with the command below and paste the printed rows under [Matrix](#matrix). The test loads
every inventory facet's artifact by path, so build the whole project first; a filtered `forge test` compiles only
the files the test imports.

```sh
forge build && forge test --match-test test_EverySharedSelectorIsClassified -vv
```

## Classes

| Class | Meaning | What to do |
| --- | --- | --- |
| Variant | Alternative implementations of one Lattice module: the cut gates, the AccessControl flavours, the account flavours | Cut exactly one |
| Override | A documented seam: a recipe routes the selector to one facet over shared storage with `_cutExcept` or `Replace` | Follow the recipe's exclusion list |
| Identical | The same function over the same storage | Cut one copy and `_cutExcept` the other |
| One per diamond | Providers with one ABI and independent storage: price adapters, ERC-7786 gateways and handlers, VRF providers, strategy adapters, and the ERC-20 and ERC-721 movement-replacing extensions and ERC-1155 burns (decision D25, see [Token extension hook model](#token-extension-hook-model)) | Use one per diamond, or a second diamond |
| Incompatible | The selector means different things in two standards, or under a name Lattice chose | Never in one diamond |

A selector with mixed relations takes the most restrictive class, and its note names the others. For example,
`transferFrom` is an ERC-20 override seam and also an ERC-20/ERC-721 standard clash, so it is Incompatible.

Today's 99 shared selectors: 19 Variant, 14 Override, 2 Identical, 36 One per diamond, 28 Incompatible.

## Scope and decisions

- **Inventory facets only.** The test covers the 129 facets in `FacetInventory`. Every facet in `src/` that
  exports its selectors (ERC-8153) is in the inventory
  ([#176](https://github.com/dadadave80/lattice/issues/176)), so the table covers them all.
- **Strategy adapters are their own diamonds.** AaveV3Adapter, CompoundV3Adapter, CurveStableSwapAdapter,
  ERC4626Adapter, LidoAdapter and UniswapV3Adapter share the `IStrategy`, `IProtocolAdapter` and
  `IAdapterOperator` surface, so a diamond holds one of them. CurveStableSwapAdapter and UniswapV3Adapter also
  share `pool()`, `slippageBps()` and `setSlippageBps(uint256)`. The adapters also clash with the vault side
  (`asset()` with ERC4626; `harvest()` and `vault()` with StrategyManager), so a vault diamond registers an
  adapter diamond as a strategy instead of cutting it in.
- **ERC1363 shares no selector but is still exclusive.** Its six `*AndCall` selectors clash with nothing, so this
  table cannot list it. It moves tokens through `ERC20Lib`, past the `transfer`/`transferFrom` that
  ERC20Pausable, ERC20Votes and GovernedVault replace, so decision D25 on
  [#234](https://github.com/dadadave80/lattice/issues/234) declares it mutually exclusive with all three.
  [`CompositionHazardsTest`](../../test/composability/CompositionHazardsTest.t.sol) pins the bypass.
- **The ERC-721 receiver seam.** ERC721Wrapper serves `onERC721Received` (`0x150b7a02`) and accepts only its
  underlying collection. UniswapV3Adapter serves the same selector to receive position NFTs. The two are Incompatible: never cut both into one diamond.
  [#201](https://github.com/dadadave80/lattice/issues/201) tracks declaring seams like this one.
- **Exclusions the table cannot show (D25).** ERC721Enumerable and ERC721Votes keep their state in step only
  when every token movement goes through their own library. ERC721Burnable and ERC721Wrapper mint and burn
  through `ERC721Lib` instead, and share no selector with either, so the cut succeeds and the state drifts.
  Never combine them; ERC721Pausable next to them leaves burns and wraps unpaused. The same holds for app code:
  the standalone `CCTPHookReceipt` example mints through `ERC721Lib._mint`, so a fork of it that adds enumeration
  or votes must mint, burn and transfer through `ERC721EnumerableLib` or `ERC721VotesLib`. `CompositionHazardsTest`
  pins each facet case, and the [composition hazards](compose-your-own-diamond.md#composition-hazards) table lists
  them.
- **Lattice-chosen names are listed, not renamed.** `getConfig()`, `getForwarder()` and the GovernedSafeDiamondCut
  operation views clash because of names Lattice picked. Renaming them changes selectors, and renaming the
  GovernedSafe views also changes ERC-165 id `0xacb1aeb6` (coordinate with
  [#206](https://github.com/dadadave80/lattice/issues/206)). The decision on
  [#240](https://github.com/dadadave80/lattice/issues/240) is to keep the names and record them in this table. A
  rename before 1.0 would need its own issue, coordinated with #206.

## Token extension hook model

Decision D25 on [#234](https://github.com/dadadave80/lattice/issues/234) (option (a), for 0.5.0) fixes how token
extensions that change transfer, mint or burn behaviour compose:

1. **Base libraries run no hooks.** `ERC20Lib._update`, `ERC721Lib._update` and `ERC1155Lib._update` move balances
   and emit the standard events. They call no extension and read no extension flag. OpenZeppelin composes its
   extensions through `virtual _update` overrides. A Lattice library cannot dispatch virtually, and a hook in the
   base library would cost every token an SLOAD per movement. The one exception is ERC-721 batch minting
   (`ERC721ConsecutiveLib`, [#236](https://github.com/dadadave80/lattice/issues/236)), which has no selector to
   replace because its batches exist only as ownership checkpoints. `ERC721Lib._ownerOf` falls back to those
   checkpoints for an id with no stored owner, and `ERC721Lib._update` bans single mints during a batch-minting
   diamond's first initialization and marks burned batch ids. On a diamond without batches that reads one storage
   slot on each mint and burn, and none on a transfer of a stored token. A batch-minting diamond also reads the
   initializable slot on each mint, and resolves an untransferred batch token through the burn bitmap and the
   checkpoint search. It lets every path, base or extension, see batch-minted tokens.
2. **A movement-replacing extension replaces the base selectors it gates.** An extension that must see or gate
   every transfer (Pausable, Votes, Enumerable, Supply) exports its own versions of the
   standard's public movement selectors. Its recipe cuts it with `Replace`, or excludes the base copies with
   `_cutExcept`.
3. **Two extensions that replace the same selectors are mutually exclusive.** Every member of a standard's family
   replaces all of that standard's movement selectors, so any two members collide. `Add` reverts with
   `CannotAddFunctionToDiamondThatAlreadyExists`. A `Replace` routes the selectors to the later facet with no
   error and drops the earlier facet's logic: Pausable over Votes stops moving votes, and Votes over Pausable
   ignores the pause.
4. **A direct mover bypasses the family.** A facet that mints, burns or moves balances by calling the base library
   (`_mint`, `_burn`, `_update`) and does not apply the extension's logic itself never goes through the replaced
   selectors. It shares no selector with a movement-replacing extension, so the cut succeeds with no signal and the
   diamond silently loses pause or vote accounting on that path. Treat every such direct mover as mutually
   exclusive with every movement-replacing extension of its standard.
5. **A mint-gating extension holds only on its own mint path.** ERC20Capped checks its cap inside the internal
   `_mint` a composing facet calls, not in `ERC20Lib._mint`, and exports only `cap()`. Every shipped facet that
   mints through the base library directly lifts the supply past the cap, so each is mutually exclusive with
   ERC20Capped.
6. **The escape is a combined facet.** A diamond that needs two behaviours on one path gets one facet that does
   both. The minimal combined facets are the sanctioned mint and burn paths that the recipes leave to the
   integrator, since `DeployERC20Pausable`, `DeployERC20Votes` and `DeployERC20Capped` expose no mint:
   - Pausable: call `PausableLib.checkNotPaused()` before `ERC20Lib._mint`/`_burn`.
   - Votes: call `ERC20VotesLib._mint`/`_burn`, which checkpoint voting units and enforce the uint208 supply bound.
   - Capped: call `ERC20Capped`'s internal `_mint`, or `ERC20CappedLib._checkCap(totalSupply + value)` before
     `ERC20Lib._mint`.
   - Two of them on one path: apply each check in one function, for example `_checkCap` then `ERC20VotesLib._mint`.

   GovernedVault is the shipped example of a full combined facet: its `transfer`/`transferFrom` and ERC-4626
   mutators move ERC-20 balances and voting units together, and `DeployGovernedVault` routes those selectors to it
   with `_cutExcept`.
7. **Option (b), a hook in each base library, is revisited only with ERC-3643
   ([#172](https://github.com/dadadave80/lattice/issues/172)).** It would append to the released `ERC20Storage`.

### ERC-20

The movement selectors are `transfer` (`0xa9059cbb`) and `transferFrom` (`0x23b872dd`).

| Facet | Role | Selectors it replaces or moves balances through | Mutually exclusive with |
| --- | --- | --- | --- |
| ERC20Pausable | Movement-replacing | `transfer`, `transferFrom` | ERC20Votes, GovernedVault; every direct mover when the pause must also stop mints and burns |
| ERC20Votes | Movement-replacing | `transfer`, `transferFrom` (and Votes' `delegate`, `delegateBySig`) | ERC20Pausable; GovernedVault, except as `DeployGovernedVault` composes them; every direct mover |
| GovernedVault | Combined facet | `transfer`, `transferFrom`, `deposit`, `mint`, `withdraw`, `redeem` | ERC20Pausable, ERC20Capped; every direct mover below except the ERC4626 and VaultCore paths it wraps |
| ERC20Capped | Mint-gating | its internal `_mint` (no selector; exports only `cap()`) | Every direct minter below (ERC20FlashMint for the length of a loan). A facet that exposes the `_mint` is itself a direct mover for ERC20Pausable and ERC20Votes |
| ERC1363 | Direct mover | `transferAndCall`, `transferFromAndCall` (both overloads) | ERC20Pausable, ERC20Votes, GovernedVault |
| ERC20Burnable | Direct mover | `burn`, `burnFrom` | ERC20Pausable, ERC20Votes |
| ERC20FlashMint | Direct mover | `flashLoan` (mints, then burns) | ERC20Pausable, ERC20Votes, ERC20Capped |
| ERC20Crosschain | Direct mover | `crosschainTransfer` (burns), `processMessage` (mints) | ERC20Pausable, ERC20Votes, ERC20Capped |
| ERC20Wrapper | Direct mover | `depositFor`, `withdrawTo` (and the library's internal `recover`) | ERC20Pausable, ERC20Votes, ERC20Capped |
| ERC7802 | Direct mover | `crosschainMint`, `crosschainBurn` | ERC20Pausable, ERC20Votes, ERC20Capped |
| ERC4626 | Direct mover | `deposit`, `mint`, `withdraw`, `redeem` | ERC20Pausable, ERC20Votes, ERC20Capped (GovernedVault reconciles ERC4626 with votes) |
| VaultCore | Direct mover | `deposit`, `mint`, `withdraw`, `redeem` (replacing ERC4626's) | ERC20Pausable, ERC20Votes, ERC20Capped (GovernedVault reconciles VaultCore with votes in `DeployGovernedVault`) |

The vote-aware `ERC20VotesLib._mint` is a direct minter for ERC20Capped too: it enforces only the uint208 bound.

[`CompositionHazardsTest`](../../test/composability/CompositionHazardsTest.t.sol) section 3 pins this:

- `test_MovementReplacingFamilyClaimsTheTransferPair`: every family member replaces both movement selectors.
- `test_PausableAddedToVotesRevertsAtCut`: `Add` of a second member reverts.
- `test_PausableReplacingVotesDesyncsVotes` and `test_VotesReplacingPausableBypassesPause`: `Replace` is silent.
- `test_BurnableNextToVotesDesyncsVotes` and `test_BurnableNextToPausableBurnsWhilePaused`: a direct mover
  bypasses the family.
- `test_ERC1363BypassesPause` and `test_ERC1363BypassesVoteCheckpoints`: ERC1363 moves tokens past the pause
  and the vote checkpoints.
- `test_DirectMinterNextToCappedExceedsCap`: ERC7802 next to the capped recipe mints past the cap, while a
  composing mint over `_checkCap` still reverts.

The matrix below classifies `transfer` as One per diamond and `transferFrom` as Incompatible (it is also the
ERC-721 selector), each with a D25 note.

### ERC-721 and ERC-1155

ERC721Enumerable, ERC721Pausable and ERC721Votes each replace the three ERC-721 movement selectors, so a diamond
takes at most one; Enumerable and Votes move tokens only through their own libs. ERC1155Pausable replaces both
ERC-1155 movement selectors and serves pause-gated `burn`/`burnBatch`. ERC1155Supply replaces no movement selector; it
serves supply-tracking `burn`/`burnBatch` and mints through `ERC1155SupplyLib`. ERC1155Burnable, ERC1155Pausable
and ERC1155Supply share the burn selectors, so a diamond takes one of the three. The ERC-721 movement selectors are `transferFrom` (`0x23b872dd`) and
both `safeTransferFrom` overloads (`0x42842e0e`, `0xb88d4fde`). The ERC-1155 movement selectors are
`safeTransferFrom` (`0xf242432a`) and `safeBatchTransferFrom` (`0x2eb2c2d6`). The shipped direct movers are
ERC721Burnable (`burn`), ERC721Wrapper (`depositFor`, `withdrawTo`, `onERC721Received`) and ERC1155Burnable
(`burn`, `burnBatch`). Each is mutually exclusive with every movement-replacing extension of its standard.

ERC-721 Consecutive is not a family member. It ships no facet and no selector: `ERC721ConsecutiveInit` mints
ERC-2309 batches in the diamond's first initialization only (an upgrade cut's reinitializer window cannot), and the
base library resolves their owners (item 1 above). So it composes with ERC721Pausable, ERC721Burnable,
ERC721URIStorage, ERC721Wrapper and ERC2981. Two extensions exclude it:

- **ERC721Enumerable**, as OpenZeppelin forbids: a batch would skip the lists. Both init orders revert
  `ERC721EnumerableForbiddenBatchMint`.
- **ERC721Votes**, unlike OpenZeppelin, which moves batch-minted voting units through `_increaseBalance`.
  `ERC721VotesLib` cannot see a batch, so the batch would vote while the supply checkpoint (and a Governor quorum
  read from it) missed it, and a vote-aware burn of a batch token would underflow that checkpoint. Both init
  orders, and `ERC721VotesInit` in a later upgrade cut, revert `ERC721VotesForbiddenBatchMint`.

`CompositionHazardsTest` pins both (`test_ERC721ConsecutiveAndEnumerableRevertInEitherOrder`,
`test_ERC721ConsecutiveAndVotesRevertInEitherOrder`).

ERC-721 Pausable, Enumerable and Votes and ERC-1155 Pausable and Supply follow the ERC-20 pattern. Each one:

- replaces all of its standard's movement selectors, so any two members collide on `Add`;
- joins a family test like `test_MovementReplacingFamilyClaimsTheTransferPair` for its standard;
- has its shared selectors classified in `SelectorCompatibilityTest` with a D25 note;
- pins its exclusivity with each shipped direct mover in `CompositionHazardsTest`, or replaces that mover's
  selectors too, or ships a combined facet;
- names in its NatSpec the selectors it replaces and the extensions it excludes.

## Matrix

| Selector | Signature | Facets | Class | Note |
| --- | --- | --- | --- | --- |
| `0x00f714ce` | `withdraw(uint256,address)` | AaveV3Adapter, CompoundV3Adapter, CurveStableSwapAdapter, ERC4626Adapter, LidoAdapter, UniswapV3Adapter | One per diamond | strategy adapters: one per diamond (each adapter is its own strategy diamond) |
| `0x01e1d114` | `totalAssets()` | ERC4626, VaultCore | Override | VaultCore's strategy-aware NAV replaces ERC4626's idle balance |
| `0x06fdde03` | `name()` | ERC20, ERC721, GovernedVault, Governor | Incompatible | ERC-20 vs ERC-721 metadata (standard); GovernedVault owns the ERC-20/Governor name |
| `0x0746a956` | `verifyInterfaceRegistered(bytes4)` | GovernedDiamondCut, GovernedSafeDiamondCut, SafeDiamondCut | Variant | cut-gate variants: cut one |
| `0x084d4783` | `latestAnswer(bytes32)` | API3Adapter, BandAdapter, ChainlinkAdapter, ChronicleAdapter, DIAAdapter, PythAdapter, RedStoneAdapter, TellorAdapter | One per diamond | price adapters: one per diamond |
| `0x095ea7b3` | `approve(address,uint256)` | ERC20, ERC721 | Incompatible | ERC-20 vs ERC-721 (standard) |
| `0x0dfe1681` | `token0()` | ConstantProduct, UniswapV3Adapter | Incompatible | the AMM pair's token vs the Uniswap V3 position's token |
| `0x0e89341c` | `uri(uint256)` | ERC1155, ERC1155URIStorage | Override | ERC1155URIStorage's per-token URI replaces ERC1155's template |
| `0x116191b6` | `gateway()` | AxelarGatewayAdapter, ZetaChainGatewayAdapter | One per diamond | ERC-7786 gateways: one per diamond |
| `0x13bc9f20` | `isOperationReady(bytes32)` | GovernedSafeDiamondCut, TimelockController | Incompatible | GovernedSafe cut views vs TimelockController (Lattice-chosen; 0xacb1aeb6) |
| `0x150b7a02` | `onERC721Received(address,address,uint256,bytes)` | ERC721Wrapper, UniswapV3Adapter | Incompatible | the ERC-721 receiver seam (#201): ERC721Wrapper accepts only its underlying collection, UniswapV3Adapter its position NFTs |
| `0x1626ba7e` | `isValidSignature(bytes32,bytes)` | ERC1271Signature, ERC6900Signature | Variant | account flavours: cut one |
| `0x16f0115b` | `pool()` | CurveStableSwapAdapter, UniswapV3Adapter | One per diamond | the Curve pool vs the Uniswap V3 pool each adapter deposits into; strategy adapters: one per diamond |
| `0x17f33340` | `rewardRecipient()` | AaveV3Adapter, CompoundV3Adapter, CurveStableSwapAdapter, ERC4626Adapter, LidoAdapter, UniswapV3Adapter | One per diamond | strategy adapters: one per diamond (each adapter is its own strategy diamond) |
| `0x18160ddd` | `totalSupply()` | ERC1155Supply, ERC20, ERC721Enumerable | Incompatible | ERC-20 supply vs ERC-721 enumeration vs ERC-1155 supply (standard) |
| `0x186f0354` | `safe()` | GovernedSafeDiamondCut, SafeDiamondCut | Variant | cut-gate variants: cut one |
| `0x19822f7c` | `validateUserOp((address,uint256,bytes,bytes,bytes32,uint256,bytes32,bytes,bytes),bytes32,uint256)` | ERC4337Validation, ERC6900Validation | Variant | account flavours: cut one |
| `0x1a3ce4e6` | `setSlippageBps(uint256)` | CurveStableSwapAdapter, UniswapV3Adapter | One per diamond | strategy adapters: one per diamond (each adapter is its own strategy diamond) |
| `0x1f931c1c` | `diamondCut((address,uint8,bytes4[])[],address,bytes)` | AccessControlDiamondCut, GovernedDiamondCut, SafeDiamondCut, DiamondCutFacet | Variant | cut-gate variants: cut one |
| `0x22841f01` | `healthFactor()` | AaveV3Adapter, CompoundV3Adapter, CurveStableSwapAdapter, ERC4626Adapter, LidoAdapter, UniswapV3Adapter | One per diamond | strategy adapters: one per diamond (each adapter is its own strategy diamond) |
| `0x22cabf70` | `frozenSelectors()` | GovernedDiamondCut, GovernedSafeDiamondCut, SafeDiamondCut | Variant | cut-gate variants: cut one |
| `0x23b872dd` | `transferFrom(address,address,uint256)` | ERC20, ERC20Pausable, ERC20Votes, ERC721, ERC721Enumerable, ERC721Pausable, ERC721Votes, GovernedVault | Incompatible | ERC-20 vs ERC-721 (standard); one ERC-20 and one ERC-721 movement-replacing extension per diamond (D25) |
| `0x2432ef26` | `receiveMessage(bytes32,bytes,bytes)` | CrosschainLink, ERC7786OpenBridge | One per diamond | inbound ERC-7786 recipients: one per diamond |
| `0x248a9ca3` | `getRoleAdmin(bytes32)` | AccessControl, AccessControlEnumerable, AccessControlTimed | Variant | AccessControl flavours: cut one |
| `0x280aebcf` | `getFeed(bytes32)` | API3Adapter, BandAdapter, ChainlinkAdapter, ChronicleAdapter, DIAAdapter, PythAdapter, RedStoneAdapter, TellorAdapter | One per diamond | price adapters: one per diamond |
| `0x28dcc8d8` | `crosschainTransfer(bytes,uint256)` | BridgeERC20, BridgeERC7802, ERC20Crosschain | One per diamond | fungible bridges: one per diamond |
| `0x2a589908` | `unregisterFeed(bytes32)` | API3Adapter, BandAdapter, ChainlinkAdapter, ChronicleAdapter, DIAAdapter, PythAdapter, RedStoneAdapter, TellorAdapter | One per diamond | price adapters: one per diamond |
| `0x2ab0f529` | `isOperationDone(bytes32)` | GovernedSafeDiamondCut, TimelockController | Incompatible | GovernedSafe cut views vs TimelockController (Lattice-chosen; 0xacb1aeb6) |
| `0x2eb2c2d6` | `safeBatchTransferFrom(address,address,uint256[],uint256[],bytes)` | ERC1155, ERC1155Pausable | Override | ERC1155Pausable's pause-gated transfer replaces ERC1155's (D25) |
| `0x2f2ff15d` | `grantRole(bytes32,address)` | AccessControl, AccessControlEnumerable, AccessControlTimed | Variant | AccessControl flavours: cut one |
| `0x313ce567` | `decimals()` | ERC20, ERC20Wrapper, ERC4626 | Incompatible | ERC4626's share decimals and ERC20Wrapper's underlying decimals each replace ERC20's (Override); a share token and a wrapper never share a diamond |
| `0x35342750` | `previewCut((address,uint8,bytes4[])[])` | GovernedDiamondCut, GovernedSafeDiamondCut, SafeDiamondCut | Variant | cut-gate variants: cut one |
| `0x3644e515` | `DOMAIN_SEPARATOR()` | ERC20Permit, ERC6538Registry | Identical | both return EIP712Lib.domainSeparatorV4(): cut one copy |
| `0x36568abe` | `renounceRole(bytes32,address)` | AccessControl, AccessControlEnumerable, AccessControlTimed | Variant | AccessControl flavours: cut one |
| `0x38d52e0f` | `asset()` | ERC4626, AaveV3Adapter, CompoundV3Adapter, CurveStableSwapAdapter, ERC4626Adapter, LidoAdapter, UniswapV3Adapter | Incompatible | the ERC-4626 vault's asset vs a strategy adapter's own asset; strategy adapters: one per diamond |
| `0x3adda78e` | `getCutRecord(uint256)` | GovernedDiamondCut, GovernedSafeDiamondCut, SafeDiamondCut | Variant | cut-gate variants: cut one |
| `0x3cb747bf` | `messenger()` | L1ToL2CrossDomainMessengerGatewayAdapter, L2ToL2CrossDomainMessengerGatewayAdapter | One per diamond | OP messenger gateways: one per diamond |
| `0x402d267d` | `maxDeposit(address)` | ERC4626, VaultCore | Override | VaultCore's deposit-latch-aware cap replaces ERC4626's |
| `0x42842e0e` | `safeTransferFrom(address,address,uint256)` | ERC721, ERC721Enumerable, ERC721Pausable, ERC721Votes | One per diamond | ERC721Enumerable, ERC721Pausable and ERC721Votes each replace ERC721's: one per diamond (D25) |
| `0x42966c68` | `burn(uint256)` | ERC20Burnable, ERC721Burnable | Incompatible | ERC-20 vs ERC-721 (standard) |
| `0x4487678f` | `freezeSelectors(bytes4[])` | GovernedDiamondCut, GovernedSafeDiamondCut, SafeDiamondCut | Variant | cut-gate variants: cut one |
| `0x4641257d` | `harvest()` | AaveV3Adapter, CompoundV3Adapter, CurveStableSwapAdapter, ERC4626Adapter, LidoAdapter, StrategyManager, UniswapV3Adapter | Incompatible | StrategyManager harvests every strategy; an adapter harvests its own position (one per diamond) |
| `0x4bf5d7e9` | `CLOCK_MODE()` | GovernedVault, Governor, Votes | Override | GovernedVault owns it; Governor's version reads its token's clock(), here the diamond itself |
| `0x570ca735` | `operator()` | AaveV3Adapter, CompoundV3Adapter, CurveStableSwapAdapter, ERC4626Adapter, LidoAdapter, UniswapV3Adapter | One per diamond | strategy adapters: one per diamond (each adapter is its own strategy diamond) |
| `0x578c71d9` | `slippageBps()` | CurveStableSwapAdapter, UniswapV3Adapter | One per diamond | strategy adapters: one per diamond (each adapter is its own strategy diamond) |
| `0x584b153e` | `isOperationPending(bytes32)` | GovernedSafeDiamondCut, TimelockController | Incompatible | GovernedSafe cut views vs TimelockController (Lattice-chosen; 0xacb1aeb6) |
| `0x58d14c04` | `quoteFee(bytes,bytes)` | CCIPGatewayAdapter, HyperlaneGatewayAdapter, LayerZeroGatewayAdapter | One per diamond | ERC-7786 gateways: one per diamond |
| `0x5c19a95c` | `delegate(address)` | ERC20Votes, ERC721Votes, Votes | Incompatible | ERC20Votes' and ERC721Votes' balance-aware delegation each replace Votes' (Override); ERC-20 vs ERC-721 units |
| `0x5db0cb94` | `setSafe(address)` | GovernedSafeDiamondCut, SafeDiamondCut | Variant | cut-gate variants: cut one |
| `0x610683bc` | `receiveCrossChainMessage(bytes,bytes,bytes,uint256)` | L1ToL2CrossDomainMessengerGatewayAdapter, L2ToL2CrossDomainMessengerGatewayAdapter | One per diamond | OP messenger gateways: one per diamond |
| `0x613c822b` | `totalAssetsManaged()` | AaveV3Adapter, CompoundV3Adapter, CurveStableSwapAdapter, ERC4626Adapter, LidoAdapter, UniswapV3Adapter | One per diamond | strategy adapters: one per diamond (each adapter is its own strategy diamond) |
| `0x6b20c454` | `burnBatch(address,uint256[],uint256[])` | ERC1155Burnable, ERC1155Pausable, ERC1155Supply | One per diamond | plain, pause-gated and supply-tracking ERC-1155 burns: one per diamond (D25) |
| `0x6e553f65` | `deposit(uint256,address)` | ERC4626, GovernedVault, VaultCore | Override | ERC4626 < VaultCore < GovernedVault checkpoint seam |
| `0x6f307dc3` | `underlying()` | ERC20Wrapper, ERC721Wrapper | Incompatible | an ERC-20 wrapper and an ERC-721 wrapper never share a diamond |
| `0x70a08231` | `balanceOf(address)` | ERC20, ERC721 | Incompatible | ERC-20 vs ERC-721 (standard) |
| `0x752bcf06` | `getRemoteGateway(uint256)` | CCIPGatewayAdapter, WormholeGatewayAdapter | One per diamond | ERC-7786 gateways: one per diamond |
| `0x775c300c` | `deploy()` | AaveV3Adapter, CompoundV3Adapter, CurveStableSwapAdapter, ERC4626Adapter, LidoAdapter, UniswapV3Adapter | One per diamond | strategy adapters: one per diamond (each adapter is its own strategy diamond) |
| `0x7ecebe00` | `nonces(address)` | ERC20Permit, Nonces | Identical | both read NoncesLib: cut one copy |
| `0x8da5cb5b` | `owner()` | AccountSigner, OwnableFacet | Incompatible | AccountSigner's signer vs ERC-173 diamond owner (separate storage) |
| `0x8ff262e3` | `castVoteBySig(uint256,uint8,address,bytes)` | GovernedVault, Governor | Override | GovernedVault's ballot-nonce reconciliation replaces Governor's |
| `0x902d5027` | `processMessage(bytes32,bytes,bytes)` | BridgeERC20, BridgeERC7802, CrosschainTimelockHandler, ERC20Crosschain | One per diamond | ERC-7786 handlers: one per link diamond |
| `0x915d3063` | `registerFeed(bytes32,address,uint48)` | API3Adapter, ChainlinkAdapter, ChronicleAdapter | One per diamond | price adapters: one per diamond |
| `0x91d14854` | `hasRole(bytes32,address)` | AccessControl, AccessControlEnumerable, AccessControlTimed | Variant | AccessControl flavours: cut one |
| `0x91ddadf4` | `clock()` | GovernedVault, Governor, Votes | Override | GovernedVault owns it; Governor's version reads its token's clock(), here the diamond itself |
| `0x94bf804d` | `mint(uint256,address)` | ERC4626, GovernedVault, VaultCore | Override | ERC4626 < VaultCore < GovernedVault checkpoint seam |
| `0x95d89b41` | `symbol()` | ERC20, ERC721 | Incompatible | ERC-20 vs ERC-721 metadata (standard) |
| `0x997ce1f0` | `registerRemoteGateway(uint256,address)` | CCIPGatewayAdapter, WormholeGatewayAdapter | One per diamond | ERC-7786 gateways: one per diamond |
| `0x9cfd7cff` | `accountId()` | ERC6900ModuleManager, ERC7579ModuleConfig | Variant | account flavours (ERC-6900 vs ERC-7579): cut one |
| `0xa0042526` | `getForwarder()` | ChainlinkAutomationAdapter, ChainlinkCREAdapter | Incompatible | Chainlink Automation vs CRE forwarder (Lattice-chosen) |
| `0xa22cb465` | `setApprovalForAll(address,bool)` | ERC1155, ERC721 | Incompatible | ERC-721 vs ERC-1155 over separate storage (standard) |
| `0xa9059cbb` | `transfer(address,uint256)` | ERC20, ERC20Pausable, ERC20Votes, GovernedVault | One per diamond | ERC20Pausable, ERC20Votes and GovernedVault each replace ERC20's: one per diamond (D25) |
| `0xaa982c45` | `cutCount()` | GovernedDiamondCut, GovernedSafeDiamondCut, SafeDiamondCut | Variant | cut-gate variants: cut one |
| `0xad0ddbee` | `latestAnswerRaw(bytes32)` | ChainlinkAdapter, PythAdapter | One per diamond | price adapters: one per diamond |
| `0xb187bd26` | `isPaused()` | AaveV3Adapter, CompoundV3Adapter, CurveStableSwapAdapter, ERC4626Adapter, LidoAdapter, UniswapV3Adapter | One per diamond | strategy adapters: one per diamond (each adapter is its own strategy diamond) |
| `0xb3ab15fb` | `setOperator(address)` | GelatoVRFAdapter, AaveV3Adapter, CompoundV3Adapter, CurveStableSwapAdapter, ERC4626Adapter, LidoAdapter, UniswapV3Adapter | Incompatible | GelatoVRFAdapter's VRF operator vs a strategy adapter's keeper (Lattice-chosen name); adapters: one per diamond |
| `0xb460af94` | `withdraw(uint256,address,address)` | ERC4626, GovernedVault, VaultCore | Override | ERC4626 < VaultCore < GovernedVault checkpoint seam |
| `0xb88d4fde` | `safeTransferFrom(address,address,uint256,bytes)` | ERC721, ERC721Enumerable, ERC721Pausable, ERC721Votes | One per diamond | ERC721Enumerable, ERC721Pausable and ERC721Votes each replace ERC721's: one per diamond (D25) |
| `0xba087652` | `redeem(uint256,address,address)` | ERC4626, GovernedVault, VaultCore | Override | ERC4626 < VaultCore < GovernedVault checkpoint seam |
| `0xc3cda520` | `delegateBySig(address,uint256,uint256,uint8,bytes32,bytes32)` | ERC20Votes, ERC721Votes, Votes | Incompatible | ERC20Votes' and ERC721Votes' balance-aware delegation each replace Votes' (Override); ERC-20 vs ERC-721 units |
| `0xc3f909d4` | `getConfig()` | API3QRNGAdapter, ChainlinkVRF, GelatoAutomateAdapter, PythEntropyAdapter | Incompatible | four different return types (Lattice-chosen) |
| `0xc63d75b6` | `maxMint(address)` | ERC4626, VaultCore | Override | VaultCore's deposit-latch-aware cap replaces ERC4626's |
| `0xc83542a6` | `emergencyRemoveCut((address,uint8,bytes4[])[])` | GovernedDiamondCut, GovernedSafeDiamondCut, SafeDiamondCut | Variant | cut-gate variants: cut one |
| `0xc87b56dd` | `tokenURI(uint256)` | ERC721, ERC721URIStorage | Override | ERC721URIStorage's per-token URI replaces ERC721's (Replace in DeployERC721URIStorage) |
| `0xc8d8e114` | `isSelectorFrozen(bytes4)` | GovernedDiamondCut, GovernedSafeDiamondCut, SafeDiamondCut | Variant | cut-gate variants: cut one |
| `0xcdfe7f5c` | `sendMessage(bytes,bytes,bytes[])` | AxelarGatewayAdapter, CCIPGatewayAdapter, CrosschainLink, ERC7786OpenBridge, HyperbridgeGatewayAdapter, HyperlaneGatewayAdapter, L1ToL2CrossDomainMessengerGatewayAdapter, L2ToL2CrossDomainMessengerGatewayAdapter, LayerZeroGatewayAdapter, WormholeGatewayAdapter, ZetaChainGatewayAdapter | One per diamond | ERC-7786 senders: one per diamond |
| `0xd21220a7` | `token1()` | ConstantProduct, UniswapV3Adapter | Incompatible | the AMM pair's token vs the Uniswap V3 position's token |
| `0xd2c725e0` | `reentrancyGuardEntered()` | AaveV3Adapter, CompoundV3Adapter, CurveStableSwapAdapter, ERC4626Adapter, LidoAdapter, StrategyManager, UniswapV3Adapter | One per diamond | strategy adapters: one per diamond; each copy, StrategyManager's too, reads ReentrancyGuardLib (Identical) |
| `0xd45c4435` | `getTimestamp(bytes32)` | GovernedSafeDiamondCut, TimelockController | Incompatible | GovernedSafe cut views vs TimelockController (Lattice-chosen; 0xacb1aeb6) |
| `0xd547741f` | `revokeRole(bytes32,address)` | AccessControl, AccessControlEnumerable, AccessControlTimed | Variant | AccessControl flavours: cut one |
| `0xdb2e21bc` | `emergencyWithdraw()` | AaveV3Adapter, CompoundV3Adapter, CurveStableSwapAdapter, ERC4626Adapter, LidoAdapter, UniswapV3Adapter | One per diamond | strategy adapters: one per diamond (each adapter is its own strategy diamond) |
| `0xdc680a0f` | `supportsAttribute(bytes4)` | AxelarGatewayAdapter, CCIPGatewayAdapter, ERC7786OpenBridge, HyperbridgeGatewayAdapter, HyperlaneGatewayAdapter, L1ToL2CrossDomainMessengerGatewayAdapter, L2ToL2CrossDomainMessengerGatewayAdapter, LayerZeroGatewayAdapter, WormholeGatewayAdapter, ZetaChainGatewayAdapter | One per diamond | ERC-7786 gateways: one per diamond |
| `0xdd1e2651` | `getUserKey(uint256)` | ChainlinkVRF, GelatoVRFAdapter | One per diamond | VRF providers: one per diamond |
| `0xe1b4264c` | `minHealthFactor()` | AaveV3Adapter, CompoundV3Adapter, CurveStableSwapAdapter, ERC4626Adapter, LidoAdapter, UniswapV3Adapter | One per diamond | strategy adapters: one per diamond (each adapter is its own strategy diamond) |
| `0xe521136f` | `setRewardRecipient(address)` | AaveV3Adapter, CompoundV3Adapter, CurveStableSwapAdapter, ERC4626Adapter, LidoAdapter, UniswapV3Adapter | One per diamond | strategy adapters: one per diamond (each adapter is its own strategy diamond) |
| `0xe985e9c5` | `isApprovedForAll(address,address)` | ERC1155, ERC721 | Incompatible | ERC-721 vs ERC-1155 over separate storage (standard) |
| `0xf242432a` | `safeTransferFrom(address,address,uint256,uint256,bytes)` | ERC1155, ERC1155Pausable | Override | ERC1155Pausable's pause-gated transfer replaces ERC1155's (D25) |
| `0xf5298aca` | `burn(address,uint256,uint256)` | ERC1155Burnable, ERC1155Pausable, ERC1155Supply | One per diamond | plain, pause-gated and supply-tracking ERC-1155 burns: one per diamond (D25) |
| `0xfbfa77cf` | `vault()` | AaveV3Adapter, CompoundV3Adapter, CurveStableSwapAdapter, ERC4626Adapter, LidoAdapter, StrategyManager, UniswapV3Adapter | Incompatible | StrategyManager's vault vs the vault an adapter serves, from separate storage; adapters: one per diamond |
| `0xfc0c546a` | `token()` | BridgeERC20, BridgeERC7802, ERC6551Account, Governor | Incompatible | Governor's voting token vs the bridges' bridged token (one bridge per diamond) vs ERC6551Account's bound NFT |

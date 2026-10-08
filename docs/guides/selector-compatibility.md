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
| One per diamond | Providers with one ABI and independent storage: price adapters, ERC-7786 gateways and handlers, VRF providers, and the ERC-20 movement-replacing extensions (decision D25, see [Token extension hook model](#token-extension-hook-model)) | Use one per diamond, or a second diamond |
| Incompatible | The selector means different things in two standards, or under a name Lattice chose | Never in one diamond |

A selector with mixed relations takes the most restrictive class, and its note names the others. For example,
`transferFrom` is an ERC-20 override seam and also an ERC-20/ERC-721 standard clash, so it is Incompatible.

Today's 67 shared selectors: 18 Variant, 14 Override, 1 Identical, 18 One per diamond, 16 Incompatible.

## Scope and decisions

- **Inventory facets only.** The test covers the 110 facets in `FacetInventory`. VestingWallet and
  ERC20Wrapper export no selectors yet ([#176](https://github.com/dadadave80/lattice/issues/176)), so they are
  not in the table. Checked by hand against the inventory: VestingWallet shares no selector, and ERC20Wrapper
  shares `decimals()` (`0x313ce567`) with ERC20 and ERC4626 and `underlying()` (`0x6f307dc3`) with
  ERC721Wrapper. Its `decimals()` replaces ERC20's to mirror the underlying (Override), it cannot share a
  diamond with an ERC4626 share token (Incompatible), and an ERC-20 wrapper and an ERC-721 wrapper cannot share
  a diamond either (Incompatible).
- **The ERC-721 receiver seam.** ERC721Wrapper serves `onERC721Received` (`0x150b7a02`) and accepts only its
  underlying collection. UniswapV3Adapter, which is not in the inventory, serves the same selector to receive
  position NFTs. The two are Incompatible: never cut both into one diamond.
  [#201](https://github.com/dadadave80/lattice/issues/201) tracks declaring seams like this one.
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
   base library would cost every token an SLOAD per movement.
2. **A movement-replacing extension replaces the base selectors it gates.** An extension that must see or gate
   every transfer (Pausable, Votes, and later Enumerable, Supply, Consecutive) exports its own versions of the
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
- `test_DirectMinterNextToCappedExceedsCap`: ERC7802 next to the capped recipe mints past the cap, while a
  composing mint over `_checkCap` still reverts.

The matrix below classifies `transfer` as One per diamond and `transferFrom` as Incompatible (it is also the
ERC-721 selector), each with a D25 note.

### ERC-721 and ERC-1155

No movement-replacing extension ships yet. The ERC-721 movement selectors are `transferFrom` (`0x23b872dd`) and
both `safeTransferFrom` overloads (`0x42842e0e`, `0xb88d4fde`). The ERC-1155 movement selectors are
`safeTransferFrom` (`0xf242432a`) and `safeBatchTransferFrom` (`0x2eb2c2d6`). The shipped direct movers are
ERC721Burnable (`burn`), ERC721Wrapper (`depositFor`, `withdrawTo`, `onERC721Received`) and ERC1155Burnable
(`burn`, `burnBatch`). Each is mutually exclusive with every movement-replacing extension of its standard.

ERC-721 Pausable, Enumerable, Votes and Consecutive
([#236](https://github.com/dadadave80/lattice/issues/236)) and ERC-1155 Pausable and Supply
([#237](https://github.com/dadadave80/lattice/issues/237)) follow the ERC-20 pattern. Each one:

- replaces all of its standard's movement selectors, so any two members collide on `Add`;
- joins a family test like `test_MovementReplacingFamilyClaimsTheTransferPair` for its standard;
- has its shared selectors classified in `SelectorCompatibilityTest` with a D25 note;
- pins its exclusivity with each shipped direct mover in `CompositionHazardsTest`, or replaces that mover's
  selectors too, or ships a combined facet;
- names in its NatSpec the selectors it replaces and the extensions it excludes.

## Matrix

| Selector | Signature | Facets | Class | Note |
| --- | --- | --- | --- | --- |
| `0x01e1d114` | `totalAssets()` | ERC4626, VaultCore | Override | VaultCore's strategy-aware NAV replaces ERC4626's idle balance |
| `0x06fdde03` | `name()` | ERC20, ERC721, GovernedVault, Governor | Incompatible | ERC-20 vs ERC-721 metadata (standard); GovernedVault owns the ERC-20/Governor name |
| `0x0746a956` | `verifyInterfaceRegistered(bytes4)` | GovernedDiamondCut, GovernedSafeDiamondCut, SafeDiamondCut | Variant | cut-gate variants: cut one |
| `0x084d4783` | `latestAnswer(bytes32)` | API3Adapter, BandAdapter, ChainlinkAdapter, ChronicleAdapter, DIAAdapter, PythAdapter, RedStoneAdapter, TellorAdapter | One per diamond | price adapters: one per diamond |
| `0x095ea7b3` | `approve(address,uint256)` | ERC20, ERC721 | Incompatible | ERC-20 vs ERC-721 (standard) |
| `0x0e89341c` | `uri(uint256)` | ERC1155, ERC1155URIStorage | Override | ERC1155URIStorage's per-token URI replaces ERC1155's template |
| `0x116191b6` | `gateway()` | AxelarGatewayAdapter, ZetaChainGatewayAdapter | One per diamond | ERC-7786 gateways: one per diamond |
| `0x13bc9f20` | `isOperationReady(bytes32)` | GovernedSafeDiamondCut, TimelockController | Incompatible | GovernedSafe cut views vs TimelockController (Lattice-chosen; 0xacb1aeb6) |
| `0x1626ba7e` | `isValidSignature(bytes32,bytes)` | ERC1271Signature, ERC6900Signature | Variant | account flavours: cut one |
| `0x186f0354` | `safe()` | GovernedSafeDiamondCut, SafeDiamondCut | Variant | cut-gate variants: cut one |
| `0x19822f7c` | `validateUserOp((address,uint256,bytes,bytes,bytes32,uint256,bytes32,bytes,bytes),bytes32,uint256)` | ERC4337Validation, ERC6900Validation | Variant | account flavours: cut one |
| `0x1f931c1c` | `diamondCut((address,uint8,bytes4[])[],address,bytes)` | AccessControlDiamondCut, GovernedDiamondCut, SafeDiamondCut, DiamondCutFacet | Variant | cut-gate variants: cut one |
| `0x22cabf70` | `frozenSelectors()` | GovernedDiamondCut, GovernedSafeDiamondCut, SafeDiamondCut | Variant | cut-gate variants: cut one |
| `0x23b872dd` | `transferFrom(address,address,uint256)` | ERC20, ERC20Pausable, ERC20Votes, ERC721, GovernedVault | Incompatible | ERC-20 vs ERC-721 (standard); one ERC-20 movement-replacing extension per diamond (D25) |
| `0x2432ef26` | `receiveMessage(bytes32,bytes,bytes)` | CrosschainLink, ERC7786OpenBridge | One per diamond | inbound ERC-7786 recipients: one per diamond |
| `0x248a9ca3` | `getRoleAdmin(bytes32)` | AccessControl, AccessControlEnumerable, AccessControlTimed | Variant | AccessControl flavours: cut one |
| `0x280aebcf` | `getFeed(bytes32)` | API3Adapter, BandAdapter, ChainlinkAdapter, ChronicleAdapter, DIAAdapter, PythAdapter, RedStoneAdapter, TellorAdapter | One per diamond | price adapters: one per diamond |
| `0x28dcc8d8` | `crosschainTransfer(bytes,uint256)` | BridgeERC20, BridgeERC7802, ERC20Crosschain | One per diamond | fungible bridges: one per diamond |
| `0x2a589908` | `unregisterFeed(bytes32)` | API3Adapter, BandAdapter, ChainlinkAdapter, ChronicleAdapter, DIAAdapter, PythAdapter, RedStoneAdapter, TellorAdapter | One per diamond | price adapters: one per diamond |
| `0x2ab0f529` | `isOperationDone(bytes32)` | GovernedSafeDiamondCut, TimelockController | Incompatible | GovernedSafe cut views vs TimelockController (Lattice-chosen; 0xacb1aeb6) |
| `0x2f2ff15d` | `grantRole(bytes32,address)` | AccessControl, AccessControlEnumerable, AccessControlTimed | Variant | AccessControl flavours: cut one |
| `0x313ce567` | `decimals()` | ERC20, ERC4626 | Override | ERC4626's share decimals replace ERC20's |
| `0x35342750` | `previewCut((address,uint8,bytes4[])[])` | GovernedDiamondCut, GovernedSafeDiamondCut, SafeDiamondCut | Variant | cut-gate variants: cut one |
| `0x3644e515` | `DOMAIN_SEPARATOR()` | ERC20Permit, ERC6538Registry | Identical | both return EIP712Lib.domainSeparatorV4(): cut one copy |
| `0x36568abe` | `renounceRole(bytes32,address)` | AccessControl, AccessControlEnumerable, AccessControlTimed | Variant | AccessControl flavours: cut one |
| `0x3adda78e` | `getCutRecord(uint256)` | GovernedDiamondCut, GovernedSafeDiamondCut, SafeDiamondCut | Variant | cut-gate variants: cut one |
| `0x3cb747bf` | `messenger()` | L1ToL2CrossDomainMessengerGatewayAdapter, L2ToL2CrossDomainMessengerGatewayAdapter | One per diamond | OP messenger gateways: one per diamond |
| `0x402d267d` | `maxDeposit(address)` | ERC4626, VaultCore | Override | VaultCore's deposit-latch-aware cap replaces ERC4626's |
| `0x42966c68` | `burn(uint256)` | ERC20Burnable, ERC721Burnable | Incompatible | ERC-20 vs ERC-721 (standard) |
| `0x4487678f` | `freezeSelectors(bytes4[])` | GovernedDiamondCut, GovernedSafeDiamondCut, SafeDiamondCut | Variant | cut-gate variants: cut one |
| `0x4bf5d7e9` | `CLOCK_MODE()` | GovernedVault, Governor, Votes | Override | GovernedVault owns it; Governor's version reads its token's clock(), here the diamond itself |
| `0x584b153e` | `isOperationPending(bytes32)` | GovernedSafeDiamondCut, TimelockController | Incompatible | GovernedSafe cut views vs TimelockController (Lattice-chosen; 0xacb1aeb6) |
| `0x58d14c04` | `quoteFee(bytes,bytes)` | CCIPGatewayAdapter, HyperlaneGatewayAdapter, LayerZeroGatewayAdapter | One per diamond | ERC-7786 gateways: one per diamond |
| `0x5c19a95c` | `delegate(address)` | ERC20Votes, Votes | Override | ERC20Votes' balance-aware delegation replaces Votes' |
| `0x5db0cb94` | `setSafe(address)` | GovernedSafeDiamondCut, SafeDiamondCut | Variant | cut-gate variants: cut one |
| `0x610683bc` | `receiveCrossChainMessage(bytes,bytes,bytes,uint256)` | L1ToL2CrossDomainMessengerGatewayAdapter, L2ToL2CrossDomainMessengerGatewayAdapter | One per diamond | OP messenger gateways: one per diamond |
| `0x6e553f65` | `deposit(uint256,address)` | ERC4626, GovernedVault, VaultCore | Override | ERC4626 < VaultCore < GovernedVault checkpoint seam |
| `0x70a08231` | `balanceOf(address)` | ERC20, ERC721 | Incompatible | ERC-20 vs ERC-721 (standard) |
| `0x752bcf06` | `getRemoteGateway(uint256)` | CCIPGatewayAdapter, WormholeGatewayAdapter | One per diamond | ERC-7786 gateways: one per diamond |
| `0x8da5cb5b` | `owner()` | AccountSigner, OwnableFacet | Incompatible | AccountSigner's signer vs ERC-173 diamond owner (separate storage) |
| `0x8ff262e3` | `castVoteBySig(uint256,uint8,address,bytes)` | GovernedVault, Governor | Override | GovernedVault's ballot-nonce reconciliation replaces Governor's |
| `0x902d5027` | `processMessage(bytes32,bytes,bytes)` | BridgeERC20, BridgeERC7802, CrosschainTimelockHandler, ERC20Crosschain | One per diamond | ERC-7786 handlers: one per link diamond |
| `0x915d3063` | `registerFeed(bytes32,address,uint48)` | API3Adapter, ChainlinkAdapter, ChronicleAdapter | One per diamond | price adapters: one per diamond |
| `0x91d14854` | `hasRole(bytes32,address)` | AccessControl, AccessControlEnumerable, AccessControlTimed | Variant | AccessControl flavours: cut one |
| `0x91ddadf4` | `clock()` | GovernedVault, Governor, Votes | Override | GovernedVault owns it; Governor's version reads its token's clock(), here the diamond itself |
| `0x94bf804d` | `mint(uint256,address)` | ERC4626, GovernedVault, VaultCore | Override | ERC4626 < VaultCore < GovernedVault checkpoint seam |
| `0x95d89b41` | `symbol()` | ERC20, ERC721 | Incompatible | ERC-20 vs ERC-721 metadata (standard) |
| `0x997ce1f0` | `registerRemoteGateway(uint256,address)` | CCIPGatewayAdapter, WormholeGatewayAdapter | One per diamond | ERC-7786 gateways: one per diamond |
| `0xa0042526` | `getForwarder()` | ChainlinkAutomationAdapter, ChainlinkCREAdapter | Incompatible | Chainlink Automation vs CRE forwarder (Lattice-chosen) |
| `0xa22cb465` | `setApprovalForAll(address,bool)` | ERC1155, ERC721 | Incompatible | ERC-721 vs ERC-1155 over separate storage (standard) |
| `0xa9059cbb` | `transfer(address,uint256)` | ERC20, ERC20Pausable, ERC20Votes, GovernedVault | One per diamond | ERC20Pausable, ERC20Votes and GovernedVault each replace ERC20's: one per diamond (D25) |
| `0xaa982c45` | `cutCount()` | GovernedDiamondCut, GovernedSafeDiamondCut, SafeDiamondCut | Variant | cut-gate variants: cut one |
| `0xad0ddbee` | `latestAnswerRaw(bytes32)` | ChainlinkAdapter, PythAdapter | One per diamond | price adapters: one per diamond |
| `0xb460af94` | `withdraw(uint256,address,address)` | ERC4626, GovernedVault, VaultCore | Override | ERC4626 < VaultCore < GovernedVault checkpoint seam |
| `0xba087652` | `redeem(uint256,address,address)` | ERC4626, GovernedVault, VaultCore | Override | ERC4626 < VaultCore < GovernedVault checkpoint seam |
| `0xc3cda520` | `delegateBySig(address,uint256,uint256,uint8,bytes32,bytes32)` | ERC20Votes, Votes | Override | ERC20Votes' balance-aware delegation replaces Votes' |
| `0xc3f909d4` | `getConfig()` | API3QRNGAdapter, ChainlinkVRF, GelatoAutomateAdapter, PythEntropyAdapter | Incompatible | four different return types (Lattice-chosen) |
| `0xc63d75b6` | `maxMint(address)` | ERC4626, VaultCore | Override | VaultCore's deposit-latch-aware cap replaces ERC4626's |
| `0xc83542a6` | `emergencyRemoveCut((address,uint8,bytes4[])[])` | GovernedDiamondCut, GovernedSafeDiamondCut, SafeDiamondCut | Variant | cut-gate variants: cut one |
| `0xc8d8e114` | `isSelectorFrozen(bytes4)` | GovernedDiamondCut, GovernedSafeDiamondCut, SafeDiamondCut | Variant | cut-gate variants: cut one |
| `0xcdfe7f5c` | `sendMessage(bytes,bytes,bytes[])` | AxelarGatewayAdapter, CCIPGatewayAdapter, CrosschainLink, ERC7786OpenBridge, HyperbridgeGatewayAdapter, HyperlaneGatewayAdapter, L1ToL2CrossDomainMessengerGatewayAdapter, L2ToL2CrossDomainMessengerGatewayAdapter, LayerZeroGatewayAdapter, WormholeGatewayAdapter, ZetaChainGatewayAdapter | One per diamond | ERC-7786 senders: one per diamond |
| `0xd45c4435` | `getTimestamp(bytes32)` | GovernedSafeDiamondCut, TimelockController | Incompatible | GovernedSafe cut views vs TimelockController (Lattice-chosen; 0xacb1aeb6) |
| `0xd547741f` | `revokeRole(bytes32,address)` | AccessControl, AccessControlEnumerable, AccessControlTimed | Variant | AccessControl flavours: cut one |
| `0xdc680a0f` | `supportsAttribute(bytes4)` | AxelarGatewayAdapter, CCIPGatewayAdapter, ERC7786OpenBridge, HyperbridgeGatewayAdapter, HyperlaneGatewayAdapter, L1ToL2CrossDomainMessengerGatewayAdapter, L2ToL2CrossDomainMessengerGatewayAdapter, LayerZeroGatewayAdapter, WormholeGatewayAdapter, ZetaChainGatewayAdapter | One per diamond | ERC-7786 gateways: one per diamond |
| `0xdd1e2651` | `getUserKey(uint256)` | ChainlinkVRF, GelatoVRFAdapter | One per diamond | VRF providers: one per diamond |
| `0xe985e9c5` | `isApprovedForAll(address,address)` | ERC1155, ERC721 | Incompatible | ERC-721 vs ERC-1155 over separate storage (standard) |
| `0xfc0c546a` | `token()` | BridgeERC20, BridgeERC7802, Governor | Incompatible | Governor's voting token vs the bridges' bridged token (one bridge per diamond) |

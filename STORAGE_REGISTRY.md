# Storage Registry

This file is the **canonical registry** of every Lattice module's ERC-7201 namespaced
storage slot and ERC-165 interface-support map slot. Each module follows the stateless
**facet + library with ERC-7201 namespaced storage** pattern, so every module must occupy a
**globally unique** storage slot to be composable into a single EIP-2535 Diamond proxy
without collisions, and every registered interface must map to a unique ERC-165 support slot.

Slots are derived as:

- **ERC-7201 storage slot:**
  `keccak256(abi.encode(uint256(keccak256(<namespace>)) - 1)) & ~bytes32(uint256(0xff))`
- **ERC-165 map slot:**
  `keccak256(abi.encode(<interfaceId>, ERC165_STORAGE_LOCATION))`
  where `ERC165_STORAGE_LOCATION = 0x9ca7f3e2e2bfb15fdf072b85dde92837cddacee6cf2f6b38cd06c9457c1c4200`
  (the ERC-7201 slot of namespace `diamond.lib.storage.ERC165`, shared by all modules).

This registry is **verified automatically** by
[`test/unit/StorageSlotVerificationTest.t.sol`](test/unit/StorageSlotVerificationTest.t.sol),
which re-derives every slot from first principles, asserts it equals the declared constant in
the module library, and proves that **all storage slots are mutually unique** and **all
ERC-165 map slots are mutually unique**. When you add a module, add its slot constants there
and a row here.

> **CI:** the test suite `StorageSlotVerificationTest` MUST be run on every change
> (`forge test --match-contract StorageSlotVerificationTest`). A failure means a slot constant
> is wrong (would collide with another module) and is a release blocker.

## Notes on interface IDs

- `interfaceId` is `type(I<Module>).interfaceId` computed from the Lattice interface, **except**
  where noted:
  - **ERC721** registers the canonical EIP-721 id `0x80ac58cd` and **ERC1155** registers the
    canonical EIP-1155 id `0xd9b67a26`. The Lattice `IERC721`/`IERC1155` interfaces bundle
    metadata/receiver selectors, so their raw `type().interfaceId` (`0xdbf24b52` / `0xd73f4e3a`)
    differs from the standard; external ERC-165 callers query the canonical ids, so those are
    what the modules register.
  - **ERC721 (metadata)** `0x5b5e139f`, **ERC1155 (metadata URI)** `0x0e89341c`, and the
    **ERC721URIStorage** entry's **ERC-4906** `0x49064906` are standard EIP ids with no
    standalone Lattice interface type.
  - **ReentrancyGuard** `IReentrancyGuard` has no functions (only an error), so its
    `interfaceId` is `0x00000000`.
  - **ERC4626** / **VaultCore** ids are the XOR of their vault-specific selectors only
    (inherited `IERC20` excluded), as declared in the Lattice interfaces.
- **GovernedDiamondCut** exposes only `diamondCut`, so `type(IGovernedDiamondCut).interfaceId == 0x1f931c1c`,
  identical to `IDiamondCut`. It reuses diamond-lib's `ERC165_MAP_ICUT_SLOT`
  (`0xa0f80413692945aab97c6ef0328381ebb94e4b17a84d11ebf6b61f73435b6d7e`) — already registered by
  `DiamondLib.registerInterface()` — rather than minting a new ERC-165 map slot. It therefore has a
  unique ERC-7201 storage slot but **no** standalone ERC-165 row in the uniqueness arrays. Its
  frozen-selector protection layer (`IFrozenSelectors`: `freezeSelectors` / `isSelectorFrozen` /
  `frozenSelectors` / `previewCut` / `verifyInterfaceRegistered`) and the append-only upgrade registry
  (`IUpgradeRegistry`) are plain facet admin/view functions sharing this same ERC-7201 slot — they add
  **no** new ERC-165 id (the pinned `0x1f931c1c` is unchanged) and **no** new storage slot (the
  `_frozenSelectors` set is APPENDED to the existing `GovernedDiamondCutStorage`, leaving the namespace
  string and slot untouched).
- **SafeDiamondCut** is the multisig-gated analogue of GovernedDiamondCut: it pins a Gnosis Safe address
  as the cut authority instead of a self-held role. Like GovernedDiamondCut it exposes only the canonical
  cut selector `diamondCut` (`0x1f931c1c` == `IDiamondCut`) for ERC-165 purposes, so it likewise **reuses**
  diamond-lib's `ERC165_MAP_ICUT_SLOT` (`0xa0f80413692945aab97c6ef0328381ebb94e4b17a84d11ebf6b61f73435b6d7e`)
  — already registered by `DiamondLib.registerInterface()` — and adds a unique ERC-7201 storage slot but
  **no** new ERC-165 row. Its Safe-authority surface (`ISafeDiamondCut`/`ISafeAuthority`: `setSafe` /
  `safe`) plus the frozen-selector / registry / emergency surfaces are plain facet functions sharing the
  same ERC-7201 slot — they add no ERC-165 id and no new storage slot (`_safe` and the registry/frozen
  fields live in the single `SafeDiamondCutStorage`).
- **GovernedSafeDiamondCut** is the Safe-gated, built-in-timelock variant. Unlike SafeDiamondCut it does
  **not** serve a synchronous cut at `0x1f931c1c` (every cut travels schedule → delay → execute), so its
  scheduling surface is a genuinely **new** interface, `IGovernedSafeDiamondCut` (`0xacb1aeb6`), which mints
  its **own** ERC-165 map slot (`0xe71618ea5c7977b34866901ace6d6c6585c16253798f12024e30133e7fb7b675`). It
  therefore adds one ERC-7201 storage slot and one new ERC-165 map slot. Its shared Safe-authority /
  registry / frozen / emergency surfaces are plain facet functions sharing the same ERC-7201 slot.
- Utility libraries that hold no own ERC-7201 storage slot (`EnumerableSet`, `TimelockLib`) and
  token-extension libraries that declare no `*_STORAGE_SLOT` (`ERC20Burnable`, `ERC20Permit`,
  `ERC20Votes`) are intentionally **not** listed here. (`ERC20Permit`, `ERC20Votes`, and
  `ERC20Burnable` do register ERC-165 ids but reuse the underlying `ERC20`/`Votes`/`Nonces`
  storage, so they have no row of their own.)
- **ERC5564Announcer** is a stateless ERC-5564 announcer (it only emits `Announcement`), so it has
  **no** ERC-7201 storage slot and **no** row in the storage-uniqueness array — only an ERC-165 map slot
  for `IERC5564Announcer` (`0x4d1f9583`). Its function/event ABI is byte-identical to the canonical
  ERC-5564 announcer. **ERC6538Registry** matches the canonical ERC-6538 reference ABI exactly
  (address-keyed registrant in the event/getter/nonce, single `registerKeysOnBehalf(address,...)`,
  `Erc6538RegistryEntry` EIP-712 entry, `ERC6538Registry__InvalidSignature` error), so `type(IERC6538Registry).interfaceId`
  is the conformant `0x7b1f57cb`. It keeps its `ERC6538RegistryStorage` (the stealth-meta-address map plus
  a **registry-local** per-registrant nonce — independent of the diamond-wide `Nonces` module, matching the
  canonical per-registry nonce semantics) at a unique ERC-7201 slot, and reuses only the shared `EIP712`
  domain for typed-data hashing. CONFORMANCE CAVEAT: as a Diamond facet the EIP-712 `verifyingContract`
  is the host diamond, so relayers/wallets must read the live domain via `DOMAIN_SEPARATOR()` /
  `eip712Domain()` rather than a fixed singleton address. Together the two stealth-address modules add
  **one** ERC-7201 storage slot and **two** ERC-165 map slots.
- **CommitReveal** is a generic commit–reveal primitive (sealed bids / auctions / MEV mitigation) — no ZK
  / circuits, just keccak256. The commitment binds the committer's address, so only the bound committer can
  reveal it (front-run-proof). It keeps its `CommitRevealStorage` (the commitment map) at a unique ERC-7201
  slot and mints `ICommitReveal` (`0xe371e8b7`); it is permissionless (no role gating). It is the
  circuit-free first deliverable of the privacy-track part 2 (#10); the remaining ZK-dependent modules
  (shielded transfers, private voting, Semaphore membership, ZK verifiers, Merkle/nullifier lib) await the
  proving-system decision.
- **Groth16Verifier** is a stateless, generic Groth16 proof verifier over BN254 (alt_bn128) — the
  verifying key is a parameter, so one deployment verifies proofs for any circuit. The verification logic
  generalizes the audited snarkjs (iden3) verifier template (PR#36 hardening: public inputs `< r`, proof
  coordinates `< q`) and evaluates the pairing check with the BN254 precompiles. It holds **no** ERC-7201
  storage (only registers `IGroth16Verifier`, `0x6d832d8e`, for ERC-165), so it adds **zero** storage slots
  and **one** ERC-165 map slot. It is the proving-system primitive (#10, Groth16 ratified) the ZK privacy
  modules plug their circuit key into.
- **PlonkVerifier** is a stateless, generic PLONK verifier over BN254 — like {Groth16Verifier} the
  verifying key is a parameter, so one deployment verifies proofs for any PLONK circuit. It is a faithful
  port of the snarkjs (iden3) PLONK verifier (eprint 2019/953): keccak256 Fiat-Shamir transcript, Lagrange
  evaluation at xi, and the batched KZG pairing check, evaluated with the BN254 precompiles. It holds
  **no** ERC-7201 storage (only registers `IPlonkVerifier`, `0x5d484314`, for ERC-165), so it adds **zero**
  storage slots and **one** ERC-165 map slot. Provided as a reusable verifier for consumers who bring PLONK
  circuits, alongside the ratified-primary Groth16 path.
- **Semaphore** is the anonymous-membership / signaling module: members join groups (Poseidon incremental
  Merkle trees of identity commitments) and prove membership in zero knowledge while broadcasting a message
  under a scope, without revealing which member they are. It keeps its `SemaphoreStorage` (group map +
  counter + verifier address) at a unique ERC-7201 slot and mints `ISemaphore` (`0xf497879d`). Group
  membership uses the shared `IncrementalMerkleTreeLib` (Poseidon LeanIMT + recent-root history) and
  double-signaling protection uses a per-group `NullifierRegistryLib`; the Groth16 verification is delegated
  to the **audited Semaphore v4 verifier** (vendored under `lib/semaphore/`, deployed separately and set via
  `setVerifier`, gated on `DEFAULT_ADMIN_ROLE`). Each group has its own admin address (Semaphore-style, not a
  global role). It adds **one** ERC-7201 storage slot and **one** ERC-165 map slot.
- **PrivateVoting** is anonymous one-person-one-vote polling that composes the `Semaphore` module: a poll is
  bound to a Semaphore group, and a member casts an anonymous ballot with a Semaphore proof whose `scope` is
  the poll id and whose `message` is the choice. It reuses `SemaphoreLib`'s membership + audited verifier for
  the zero-knowledge check and keeps its OWN per-poll `NullifierRegistryLib` (so voting nullifiers never
  collide with general Semaphore signalling). Polls are created by the group admin; the scope-bound nullifier
  gives each member exactly one ballot per poll. It keeps its `PrivateVotingStorage` (poll map + counter) at a
  unique ERC-7201 slot and mints `IPrivateVoting` (`0xf750b661`); it adds **one** ERC-7201 storage slot and
  **one** ERC-165 map slot. 1-person-1-vote, not token-weighted (private weighted voting needs a bespoke
  circuit and is out of scope).
- **ShieldedPool** is fixed-denomination shielded (private) ERC-20 transfers (Tornado-style): a depositor
  inserts `Poseidon(nullifier, secret)` into the pool's Poseidon LeanIMT (`IncrementalMerkleTreeLib`), and a
  later withdrawal proves membership in zero knowledge and burns a one-time nullifier hash
  (`NullifierRegistryLib`) to an arbitrary recipient. The on-chain mechanics are the library's value-add;
  the withdraw CIRCUIT + its verifier are consumer-supplied per pool (5 public signals `[root,
  nullifierHash, recipient, relayer, fee]`), so the cryptography is wrapped, not hand-rolled. Withdrawals
  follow strict CEI (nullifier spent before any ERC-20 transfer). It keeps its `ShieldedPoolStorage` (pool
  map + counter) at a unique ERC-7201 slot and mints `IShieldedPool` (`0x8f5cc2c7`); pool creation is gated
  on `DEFAULT_ADMIN_ROLE`. It adds **one** ERC-7201 storage slot and **one** ERC-165 map slot. SECURITY:
  this module escrows funds and must be deployed with an audited circuit/verifier + honest trusted setup
  before any mainnet-with-funds use.
- **ENSReverseClaimer** lets a diamond claim its own primary ENS name via reverse resolution. It stores
  the configured reverse registrar + cached name in its own `ENSReverseClaimerStorage` at a unique
  ERC-7201 slot and mints `IENSReverseClaimer` (`0x84019dd8`); the identity setters are gated on
  `ENS_MANAGER_ROLE` (`keccak256("ENS_MANAGER_ROLE")`). It adds one ERC-7201 slot and one ERC-165 map slot.
- **ENSResolver** and **ENSSubnameIssuer** are the ENS-identity forward path. **ENSResolver** does on-chain
  forward resolution (registry → resolver → `addr`) and stores the configurable ENS registry at its own
  ERC-7201 slot, gated on `ENS_MANAGER_ROLE`; it mints `IENSResolver` (`0x566ec67d`). **ENSSubnameIssuer**
  mints subnames via the ENS NameWrapper, stores the configurable NameWrapper at its own ERC-7201 slot, and
  is gated on the dedicated `ENS_SUBNAME_ISSUER_ROLE` (`keccak256("ENS_SUBNAME_ISSUER_ROLE")`); it mints
  `IENSSubnameIssuer` (`0x6ead39e3`). Both vendor minimal external ENS interfaces (`IENS`, `IAddrResolver`,
  `INameWrapper`) under `interfaces/external/` and never hardcode ENS addresses. Together they add **two**
  ERC-7201 storage slots and **two** ERC-165 map slots.
- **SafeHarborAdopter** lets a diamond adopt the SEAL Whitehat Safe Harbor agreement on-chain (the legal
  half of incident response, complementing EmergencyStop). It stores the configurable SEAL registry +
  agreement factory in its own `SafeHarborAdopterStorage` at a unique ERC-7201 slot and mints
  `ISafeHarborAdopter` (`0x2a3e8e12`). The diamond calls the registry itself (`msg.sender == diamond`),
  so it is recorded as the adopter; adoption / creation are gated on the dedicated `SAFE_HARBOR_ADMIN_ROLE`
  (`keccak256("SAFE_HARBOR_ADMIN_ROLE")`) because the agreement designates the asset-recovery address.
  The vendored SEAL interfaces (`ISafeHarborRegistry`, `IAgreementFactory` + `AgreementDetails` types) live
  under `interfaces/external/`; the deployed SEAL addresses + struct ABI must be verified per chain.
- **IAdapterOperator** (`setOperator` / `operator`) is the authorized-operator surface co-implemented
  by **every** protocol adapter facet alongside `IProtocolAdapter`. It is a **separate** interface on
  purpose: adding its two functions to `IProtocolAdapter` would change that interface's pinned id
  (`0x8f7783e6`, the shared adapter ERC-165 map slot). `IAdapterOperator` is **not registered** for
  ERC-165 (no `registerInterface` write, no map slot) and adds **no** new ERC-7201 storage slot — the
  `_operator` field it reads/writes is **APPENDED** to each adapter's existing `*Storage` struct,
  leaving every namespace string and storage slot below untouched. (Errors/events added to
  `IProtocolAdapter` in the same change — `ProtocolAdapterUnauthorized`, `ProtocolAdapterInvalidRecipient`,
  `OperatorSet` — do not affect a Solidity `interfaceId`, so `0x8f7783e6` is unchanged.)

## Registry

### Access

| Module | ERC-7201 namespace | Storage slot (hex) | Interface | interfaceId | ERC-165 map slot (hex) |
|---|---|---|---|---|---|
| AccessControl | `lattice.storage.AccessControl` | `0xb914f813e2d49e02dd5aa794466aa4a74f9c100c2b1e98e29e7267020b834d00` | `IAccessControl` | `0x7965db0b` | `0xce317eb1da4e1492e501dc3f63d2206e3e9294a33442f09d99ce09cbbaaeae1f` |
| AccessControlEnumerable | `lattice.storage.AccessControlEnumerable` | `0xae7c738306b742461a657cbf6c6b56bd5351917d4cf69da559703284f7d34500` | `IAccessControlEnumerable` | `0xf92172dc` | `0xdfb0020c4bf380ed4a6e172ee8a12845bb7e78959d456aee21dd4cc4e0a60edf` |
| AccessControlTimed | `lattice.storage.AccessControlTimed` | `0xc28360e6402e1e090270be0970bdf75960435f822fc9a49d7b8c286806e6af00` | `IAccessControlTimed` | `0x55658261` | `0x6389d98b1603c26ed93ee23dd27c7d50ce87ec4985c6f5adaf89a862d65f1d7e` |
| AccessManager | `lattice.storage.AccessManager` | `0x031c2bc21c63b497895ca319b75b15a6c2f2e4b0e91bbd5327f580843bca1a00` | `IAccessManager` | `0x8fc52f86` | `0xa0825c9ce05c3e98cbd409c12bc8bdadc253d720dbb80af60f4b2f3807f3c1dd` |
| AccessManaged | `lattice.storage.AccessManaged` | `0x1d3b28af968dd6edd45cccd73c2668243fb5bd57c6ee16239765b74aa3d5e100` | `IAccessManaged` | `0xe5b444fd` | `0x18229ea668ffe17715e3d827216c081ca3411cbbb4f8a9b8908fb47aee1d7887` |

### Tokens

| Module | ERC-7201 namespace | Storage slot (hex) | Interface | interfaceId | ERC-165 map slot (hex) |
|---|---|---|---|---|---|
| ERC20 | `lattice.storage.ERC20` | `0x948387732d07f6e6ec1c3bf1559c10e90e518c5a59f5d2be5a80edb6f2494300` | `IERC20` | `0x942e8b22` | `0xc99f0f757c400475fa5e27e7e237b05409e3b11dbfd9a8930fb35692da3f3a3d` |
| ERC20Capped | `lattice.storage.ERC20Capped` | `0xf3126bfe4af748db9eb069fa2ed04557107fb53a164b5206750073586b2bc900` | `IERC20Capped` | `0x355274ea` | `0xb2089445722e0a36969fff4735cd037fb1b56a44be61c7f6c752270db855a1b7` |
| ERC721 | `lattice.storage.ERC721` | `0xb57056eaff39f17dbb7656e3d0f4bee059cc8b05a6894f946db4b85f3b03e700` | `IERC721` (EIP-721) | `0x80ac58cd` | `0x741e8246930c2bfc93c4e7042569e8d7f42e535e31e366398006f597e42d38fb` |
| ERC721 (metadata) | `lattice.storage.ERC721` | (shares ERC721 slot) | `IERC721Metadata` | `0x5b5e139f` | `0xdec0fb77ff71ebf00e30e78bd255149ae2525d6ff9925bff1ddd9a569813231d` |
| ERC721URIStorage | `lattice.storage.ERC721URIStorage` | `0xcad0a180da252dc6d7fda719c706c048d7fcfbea8301125fec9b8527feaa7700` | ERC-4906 (MetadataUpdate) | `0x49064906` | `0xf6e2df7ae707ae7f293659ac6f748c7ba27a30d8639e53e763363aebc5fa8f65` |
| ERC1155 | `lattice.storage.ERC1155` | `0xe39704fe713bf9d011ae08177a1e99cc7df74d40063bba4426aeb9d10e274c00` | `IERC1155` (EIP-1155) | `0xd9b67a26` | `0xa10754813726d67c8d4e4553f74a520d6623216a67c6c4a53860c47e2ccde594` |
| ERC1155 (metadata URI) | `lattice.storage.ERC1155` | (shares ERC1155 slot) | `IERC1155MetadataURI` | `0x0e89341c` | `0x16223e323116e54e339612437d2478d553a51948c039066bf3354fac71c5ef6c` |
| ERC2981 | `lattice.storage.ERC2981` | `0xf01000cac811e850d05bb5588943b621fb762a575809c98a87e3540df4e97a00` | `IERC2981` | `0x2a55205a` | `0x0b6e5f3aef2b5db6c8b7f9a90550b00e1bcf3efa09341feda1a90dabdea92899` |
| ERC4626 | `lattice.storage.ERC4626` | `0x748f49bc653df23655f3b413e3d5c91c1b4c965af17a32d743e995b145325100` | `IERC4626` | `0x87dfe5a0` | `0xdad016fc8af4f826152a6bfdd6ece63fb81a66a94f522cc8a79db8d6838e2732` |

### Governance

| Module | ERC-7201 namespace | Storage slot (hex) | Interface | interfaceId | ERC-165 map slot (hex) |
|---|---|---|---|---|---|
| Votes | `lattice.storage.Votes` | `0x51efe794a829d7992f137137b94eec0d37b1c5be45aa8cf9431c145ea39c0600` | `IVotes` | `0x3327c9eb` | `0x61ade9dd9a8b94d6fecab99fabf41cc4bf0b14d40172852668cf26dba0f52f49` |
| Governor | `lattice.storage.Governor` | `0x20a7901cc1c78eb01d63d9c1875355513c3dabc82d8607ad0f82e1312f750c00` | `IGovernor` | `0x220cdebb` | `0x16d0785b1b0d3d2d988cff60fd273da31ad0fc5acccec3792316ca40dcc33977` |
| TimelockController | `lattice.storage.TimelockController` | `0x87f5daf40fea2daee0a93658693902d7cd9e07fa1a4f16f2e8eb4a4e9d433000` | `ITimelockController` | `0xd826478e` | `0xc0a085cd59634eff50a01907a25e03eb6a55bd6279462a3ac6a99ce44b9c2f08` |
| GovernedDiamondCut | `lattice.storage.GovernedDiamondCut` | `0x9a46da229426897da8e8df190858c430564a988584235445fd229e2bef8a8700` | `IDiamondCut` (reused, EIP-2535) | `0x1f931c1c` | `0xa0f80413692945aab97c6ef0328381ebb94e4b17a84d11ebf6b61f73435b6d7e` (shared) |
| SafeDiamondCut | `lattice.storage.SafeDiamondCut` | `0xdfdae3ef74d2f2c31fc34cd5e60ae4b170cd90587a13d52debd5569f575e7900` | `IDiamondCut` (reused, EIP-2535) | `0x1f931c1c` | `0xa0f80413692945aab97c6ef0328381ebb94e4b17a84d11ebf6b61f73435b6d7e` (shared) |
| GovernedSafeDiamondCut | `lattice.storage.GovernedSafeDiamondCut` | `0x67b04bedb2ce49892ef6d6cc51adf679ddefc544b7aca2da8ae73f02694ff300` | `IGovernedSafeDiamondCut` | `0xacb1aeb6` | `0xe71618ea5c7977b34866901ace6d6c6585c16253798f12024e30133e7fb7b675` |
| SafeHarborAdopter | `lattice.storage.SafeHarborAdopter` | `0xaaf15994f2af30ab6b279714cd625e3af0592976549136cf56b423f8b1439400` | `ISafeHarborAdopter` | `0x2a3e8e12` | `0xc27d89bdc7ce502086d0749a1bda2c210ca866065fa49ea19147ad53e8e018ad` |

### DeFi

| Module | ERC-7201 namespace | Storage slot (hex) | Interface | interfaceId | ERC-165 map slot (hex) |
|---|---|---|---|---|---|
| VaultCore | `lattice.storage.VaultCore` | `0x391c4f0f82559e85ff01d307d4b19b40f088495abd453c84d7e0fa35497de600` | `IVaultCore` | `0xa86d8962` | `0xee1c77df59bab5696d7427515bb0fba56d8719259c4cc5bc6587a3654b26bdf2` |
| StrategyManager | `lattice.storage.StrategyManager` | `0x1b00913e47c53f1d64d326bde2ad6a7904ed791d4ee4432bc133be907894ca00` | `IStrategyManager` | `0xcce4011b` | `0x3d05027e9ebc1daac4235d8ac5fc59b9acea5ece08ff307b79ab5b69ad569930` |
| AaveV3Adapter | `lattice.storage.AaveV3Adapter` | `0x78e1f0849c8352c9588d407dc28e9981715ac638a0aa753fc1ecf5191c1f8200` | `IProtocolAdapter` + `IAaveV3Adapter` | `0x8f7783e6` / `0xe0d5525d` | `0x789387b95720f4aa713e912bc377a2f999f1310b69003727d9c01b7ea1494c77` / `0x262752a3af13c9a5ddea1c5915891d611ab5f872b74fae046923437d05fcf120` |
| CompoundV3Adapter | `lattice.storage.CompoundV3Adapter` | `0x96f5f0ff446cccea8e0037b1046912f9609bac8e9b25707c9fadf78bc2d9fe00` | `IProtocolAdapter` + `ICompoundV3Adapter` | `0x8f7783e6` / `0xa01f1203` | `0x789387b95720f4aa713e912bc377a2f999f1310b69003727d9c01b7ea1494c77` / `0x02c9afc8b129398c559418de4825ac6d2670e884630d5a02557a9dcecd0b40e1` |
| ERC4626Adapter | `lattice.storage.ERC4626Adapter` | `0x8e54862d9117c02647004a257ec52ba4f4c6ce02a01e23235ed8d34a2127c500` | `IProtocolAdapter` + `IERC4626Adapter` | `0x8f7783e6` / `0x6189942b` | `0x789387b95720f4aa713e912bc377a2f999f1310b69003727d9c01b7ea1494c77` / `0x84ec7ed953664aca1f16de58454031d5ee56bdfdc133c3183893a830a7b1c08b` |
| CurveStableSwapAdapter | `lattice.storage.CurveStableSwapAdapter` | `0x9a875cb7e904ab3576fe7e6b7405b28b9f810acb5bf4def0fec57c5e754def00` | `IProtocolAdapter` + `ICurveStableSwapAdapter` | `0x8f7783e6` / `0xfa38ccb7` | `0x789387b95720f4aa713e912bc377a2f999f1310b69003727d9c01b7ea1494c77` / `0x5d7c390f2f6bf0ca6f51b6ea0940c100b21726e3e202811c94c2ff39040d4299` |
| LidoAdapter | `lattice.storage.LidoAdapter` | `0x3d4dff0246f0af54636d62603e75b921d2876c293bb97376b20bb8265ecb3900` | `IProtocolAdapter` + `ILidoAdapter` | `0x8f7783e6` / `0x83d0afd2` | `0x789387b95720f4aa713e912bc377a2f999f1310b69003727d9c01b7ea1494c77` / `0x6167b6f3924e213fbc2c85ec2d6ca3e7f5267a73935588adb9fb05f57a52b315` |
| UniswapV3Adapter | `lattice.storage.UniswapV3Adapter` | `0x6f3c1f877b0bf340477364a294f77f49bff3a5479f70012a0fb5cb2803b61e00` | `IProtocolAdapter` + `IUniswapV3Adapter` | `0x8f7783e6` / `0xf723aa17` | `0x789387b95720f4aa713e912bc377a2f999f1310b69003727d9c01b7ea1494c77` / `0x18cf2bfdc937c75408cba5cf015af2a2f8d21a881c553ac382a288bcae5dc1c8` |

### AMM

| Module | ERC-7201 namespace | Storage slot (hex) | Interface | interfaceId | ERC-165 map slot (hex) |
|---|---|---|---|---|---|
| ConstantProduct | `lattice.storage.ConstantProduct` | `0xf3baf196a9957c5a93606e180cd873c83f4d725c3513c9295ef6ca05f13a2200` | `IConstantProduct` | `0x8098801f` | `0xe179134a78bc5c2b2530eee9483cf7fd81654d9311d88e7b22e0fa63d02f43cf` |

### Oracles

| Module | ERC-7201 namespace | Storage slot (hex) | Interface | interfaceId | ERC-165 map slot (hex) |
|---|---|---|---|---|---|
| ChainlinkAdapter | `lattice.storage.ChainlinkAdapter` | `0xdbb02d424081d7fb4c59a631e74d23250f514b627bc328ad0ec973d94b228000` | `IChainlinkAdapter` | `0x364fdec9` | `0x65e721c748691ae5a9544827b82a8602440249a42e1438a441599564727a3bd2` |
| PythAdapter | `lattice.storage.PythAdapter` | `0x4f06923ad9b02e8a3ff8edafe956de2290e9ad8f87494c6f70ad4259b24ff100` | `IPythAdapter` | `0x3839468c` | `0x8285166a3f9489792233ccce4dfcee0aa88473267c0fab1b647d041fceb112c6` |
| API3Adapter | `lattice.storage.API3Adapter` | `0xdedf34315ce34cb136d15a8f1bef434dfd97b5e1960d065caa42769bce24e700` | `IAPI3Adapter` | `0xfa98111e` | `0x21168d66e590ee042a818ed855046fa88c4c6601cbf29cfcb9e870d054a8cb77` |
| ChronicleAdapter | `lattice.storage.ChronicleAdapter` | `0xfc08f646a4b61c410e914db3efd5dca6935b089749eb55e38d0c450dddbb7600` | `IChronicleAdapter` | `0x278f5b6a` | `0xfbb4f19de9230b60c572e8ff078c06c8112306947245c1d5058d08359436c1ca` |
| DIAAdapter | `lattice.storage.DIAAdapter` | `0x96676e4e566fe60ae3185e7bd982de2eb1f4d0f9b85c8e29200af4e575d6c400` | `IDIAAdapter` | `0xec319d60` | `0xac3b2e96bffda1d6525b62f471f6722940d02b7c74a1e8090cae939120be2443` |
| BandAdapter | `lattice.storage.BandAdapter` | `0xf5012e750700459bfafa131fc1c12ce6e9c0f0209cb29cbc1f960c4760a00a00` | `IBandAdapter` | `0xebdf87c5` | `0xc004cf02eead1d879bc806deefbe1f4228491d4cea98d16c38bf22274d73f5ac` |
| TellorAdapter | `lattice.storage.TellorAdapter` | `0xf830cd05b050ba9ecf73559ef9b50793eb6cd90a674e3621847f667a1210d100` | `ITellorAdapter` | `0xddc762ca` | `0xd0880994b1b91b07c905771aa510c46b61d48fe80d33acc431dc49f1cf7b22c5` |
| RedStoneAdapter | `lattice.storage.RedStoneAdapter` | `0x6c77ff7037fedb1e7737bf925fac4c87e7cc2c960916dee7790d2d73271bc700` | `IRedStoneAdapter` | `0xd5afaecd` | `0x48fa637c6327d1b003860a80c88da58028cdc6c0ad566c17cfe6e68792096327` |
| ChainlinkVRF | `lattice.storage.ChainlinkVRF` | `0x296a09c3f1dda7c7057a0d3e9cfd88b1666f0f2ebdcbdc2f576bbcf22db0d200` | `IChainlinkVRF` | `0xed74ccf3` | `0x5e805972aa7ebffe06f2b61cc9d80c103d549fa32d030cc2918893026547c07e` |
| TWAPOracle | `lattice.storage.TWAPOracle` | `0xc2bcc163613aea761b734a9692ad3548aab9088be29b53e03facf6a2a351df00` | `ITWAPOracle` | `0xd1baebe0` | `0x3edcb012a40cef5fed8aba3a5816c3233af9ecd91b8a1965a2b67b8940a0f49f` |

### Crosschain

| Module | ERC-7201 namespace | Storage slot (hex) | Interface | interfaceId | ERC-165 map slot (hex) |
|---|---|---|---|---|---|
| CrosschainLink | `lattice.storage.CrosschainLink` | `0x018a2157cdb5adbb1b39e614b18b4d8eae2cba40cdae1a4ba3100cc857e64900` | `ICrosschainLink` | `0xe1805ff8` | `0x9ddc11a88c7ecd9ccccbcd59cd7f34c709ebe70b4507cbaed74ad8b1267235ef` |
| BridgeERC20 | `lattice.storage.BridgeERC20` | `0x0e9006c16c4f5fe9e0e3215c8af601bd97024c6bebdfa0efe51c092276cd7c00` | `IBridgeFungible` | `0x28dcc8d8` | `0xc98ec5eb76ed7701e7884a55fd8dcc6ba54f192d7f68011281537265c16215d4` |
| BridgeERC7802 | `lattice.storage.BridgeERC7802` | `0x9d1b234db7644d1f76207933d92c2e89140027741ab600a4ff4b12a8d51e4b00` | `IBridgeFungible` | `0x28dcc8d8` | `0xc98ec5eb76ed7701e7884a55fd8dcc6ba54f192d7f68011281537265c16215d4` |

### Security

| Module | ERC-7201 namespace | Storage slot (hex) | Interface | interfaceId | ERC-165 map slot (hex) |
|---|---|---|---|---|---|
| Pausable | `lattice.storage.Pausable` | `0x1484a55ae2f6de193138ed7f3a9f9b3307c3701783002d2a375beb8271f96200` | `IPausable` | `0xe78a39d8` | `0xad8c21edea54b0e7ec01d18544e806e752f64eb497d475cd8353c0c8726b4d3d` |
| ReentrancyGuard | `lattice.storage.ReentrancyGuard` | `0xd4429f8db30ab6cbe40e0e5546854bc12f64b5d4a4cfb0ec3f5b16a895cd0c00` | `IReentrancyGuard` | `0x00000000` | `0xfb939cb1ca033f66389071014066e3ba51464fd8ec15c96518ea9663d9c0f494` |
| RateLimiter | `lattice.storage.RateLimiter` | `0xb9ee9c1434713ac0213faa3d41a1dd3c78042ad8ee2d7f6e110f73cd6f19bd00` | `IRateLimiter` | `0x9afe0493` | `0x58fa1bc4807b27651ddeaa1871a010e28c99455295cf3f3424edd8a3f6c6db45` |
| CircuitBreaker | `lattice.storage.CircuitBreaker` | `0xd8788de4a058793385dd8cf230dd9182ee7825c114e097c68b1e086af1ccbe00` | `ICircuitBreaker` | `0x7462bdca` | `0x9f65a04bbf27ebfd1338d2e0d1c8a9eeb3234866269ee27f320faed8bab02aec` |
| EmergencyStop | `lattice.storage.EmergencyStop` | `0x06261d2148a76026572818ff69ded6332eb2830e669ce15f15f286b1d91c5800` | `IEmergencyStop` | `0x9e464da9` | `0x59d8ae278aff771bb9e56436652ef8f684d37f52855acb66dfe58a5a44c4d9de` |
| InvariantChecker | `lattice.storage.InvariantChecker` | `0x6d7e4fbc04e31fa71f6fa52aa22270dd459ba0a3bd079c75a4fa29fd0ddbc200` | `IInvariantChecker` | `0x24e34e52` | `0x1aa8e25c37e7f12aeead6e76f9ac394d6db559f39dd1228f00e20ba394b198e1` |

### Utils

| Module | ERC-7201 namespace | Storage slot (hex) | Interface | interfaceId | ERC-165 map slot (hex) |
|---|---|---|---|---|---|
| EIP712 | `lattice.storage.EIP712` | `0x20a66479672b0fb14805a3bad8d1d6c2fa26c98d9118036fcaf73a0900bc5a00` | `IEIP712` | `0x84b0196e` | `0xce8419fc9d1331d080c55682cb17490a04c7d4f800e9d81986c2db7a5e912f84` |
| Nonces | `lattice.storage.Nonces` | `0x2b93a5a8782d382c0f6890e7e2d77ba67ed77675c16cc334b45b931317d4de00` | `INonces` | `0x7ecebe00` | `0x7a551986b45870996296121343257817091920bfbe333333c5198eab95eb2fa2` |
| VestingWallet | `lattice.storage.VestingWallet` | `0x6d3272be2f02b6d92080037a80b8780ee2896be455de43b32ab08d8adbdbbe00` | `IVestingWallet` | `0x1c3a25a8` | `0x30594729cb8d6a49998656680a715012a3392034ab2a6e4f69a94bf6b0450af9` |

### Privacy

| Module | ERC-7201 namespace | Storage slot (hex) | Interface | interfaceId | ERC-165 map slot (hex) |
|---|---|---|---|---|---|
| ERC5564Announcer | (stateless — no ERC-7201 storage) | — | `IERC5564Announcer` (ERC-5564) | `0x4d1f9583` | `0xa57260aa5166ddbfa7edd847f707bbf0762a8707401140e29b2073d6dfc88e2e` |
| ERC6538Registry | `lattice.storage.ERC6538Registry` | `0x77e72c5973ed8cfb58126100bfd525d25949aa328155f37334e51548cdc80100` | `IERC6538Registry` (ERC-6538) | `0x7b1f57cb` | `0xba3bf91c60e936a8bb7a4c2729c74c6ef842a655f3dff9707765ac926778cd2e` |
| CommitReveal | `lattice.storage.CommitReveal` | `0xd3109411a8705fe8e8868eda2607aae4e6b37bb0d383a8a9e1c55c78e6853e00` | `ICommitReveal` | `0xe371e8b7` | `0xdc9ba0d500a620df2dabeedf359873cda3ecd1229c8cb91b5b30ae80ec382462` |
| Groth16Verifier | (stateless — no ERC-7201 storage) | — | `IGroth16Verifier` | `0x6d832d8e` | `0x65fb5f0c2dd2a1b03fcdcf008584d060b7a7596bbc510b7022310e4dbd7682a9` |
| PlonkVerifier | (stateless — no ERC-7201 storage) | — | `IPlonkVerifier` | `0x5d484314` | `0xb1e78a1a6e11f30e01de857f602d74246da41ae3318d8e6afc2b73cc1cbe0ede` |
| Semaphore | `lattice.storage.Semaphore` | `0x9014b6f2f89a94726c6607d3b9e5562f77c44e9f80791dbbfea2ef3de33d0300` | `ISemaphore` | `0xf497879d` | `0xf2439559430b40518d710e6342516a19266235963e7106afd03350497fe51040` |
| PrivateVoting | `lattice.storage.PrivateVoting` | `0x366a7e9d1ddfe6eaa85ec4e6a71a0be592797e3e9ab0151a827465f6ed6bb900` | `IPrivateVoting` | `0xf750b661` | `0xd7a71e51b42fc01807cbfbb5db7d2ead6dbf4db6187d1c815fc074c4ac95ba7c` |
| ShieldedPool | `lattice.storage.ShieldedPool` | `0xa961220e87963afb8adc0f7621a90ce1922bf3bb438109c43cc7dacbc8e06600` | `IShieldedPool` | `0x8f5cc2c7` | `0x584247a1f67e966ee8f18e29a93dbcead963401775336064ffc8d6a343c2a4df` |

### ENS

| Module | ERC-7201 namespace | Storage slot (hex) | Interface | interfaceId | ERC-165 map slot (hex) |
|---|---|---|---|---|---|
| ENSReverseClaimer | `lattice.storage.ENSReverseClaimer` | `0x4490f19c91eeff7574cc9707696b972040b89f54488ef7fa354afe94a194c100` | `IENSReverseClaimer` | `0x84019dd8` | `0x3c859ae3ba58f26576821324787594a5249343bb61f3f7c4054b439dbc4eff8c` |
| ENSResolver | `lattice.storage.ENSResolver` | `0x33f26d8db6499021a25127a427a9f060956987880daa3f7db97807f377225300` | `IENSResolver` | `0x566ec67d` | `0x79535b2b28365a4b28deff1d36dfc239871172c80dcc5e494674d846366975cb` |
| ENSSubnameIssuer | `lattice.storage.ENSSubnameIssuer` | `0xecd97908615d460a8806be2f460463395b75373d406444064e9704ed5d892e00` | `IENSSubnameIssuer` | `0x6ead39e3` | `0x19f98b1c052723a0f45e31ccce192390fdd3867a76366f19df750eb883381f60` |

---

**Counts:** 55 storage-bearing modules (55 unique ERC-7201 slots) and 59 ERC-165 interface
map slots (the privacy track adds the stateful `ERC6538Registry` — one ERC-7201 slot and one
`IERC6538Registry` ERC-165 slot — plus the stateless `ERC5564Announcer` — no ERC-7201 slot, one
`IERC5564Announcer` ERC-165 slot — and the stateless `Groth16Verifier` — no ERC-7201 slot, one
`IGroth16Verifier` (`0x6d832d8e`) ERC-165 slot — and the stateless `PlonkVerifier` — no ERC-7201 slot,
one `IPlonkVerifier` (`0x5d484314`) ERC-165 slot — and the stateful `Semaphore` membership module — one
ERC-7201 slot and one `ISemaphore` (`0xf497879d`) ERC-165 slot — and the stateful `PrivateVoting` module
— one ERC-7201 slot and one `IPrivateVoting` (`0xf750b661`) ERC-165 slot — and the stateful `ShieldedPool`
module — one ERC-7201 slot and one `IShieldedPool` (`0x8f5cc2c7`) ERC-165 slot; GovernedDiamondCut reuses IDiamondCut's `0x1f931c1c` ERC-165 slot, so it adds an
ERC-7201 slot but no new ERC-165 map slot; SafeDiamondCut likewise reuses IDiamondCut's
`0x1f931c1c` ERC-165 slot, so it adds an ERC-7201 slot but no new ERC-165 map slot;
GovernedSafeDiamondCut serves no synchronous cut selector and registers its own
`IGovernedSafeDiamondCut` (`0xacb1aeb6`) interface, so it adds one ERC-7201 slot AND one new
ERC-165 map slot; AaveV3Adapter registers two interfaces —
the generic `IProtocolAdapter` plus its protocol-specific `IAaveV3Adapter` — so it adds two
ERC-165 map slots; CompoundV3Adapter reuses the shared `IProtocolAdapter` map slot and only
adds its protocol-specific `ICompoundV3Adapter` slot — so it adds one ERC-7201 slot and one
new ERC-165 map slot; ERC4626Adapter likewise reuses the shared `IProtocolAdapter` map slot and
adds only its protocol-specific `IERC4626Adapter` slot — one ERC-7201 slot and one new ERC-165
map slot; CurveStableSwapAdapter likewise reuses the shared `IProtocolAdapter` map slot and adds
only its protocol-specific `ICurveStableSwapAdapter` slot — one ERC-7201 slot and one new ERC-165
map slot; LidoAdapter likewise reuses the shared `IProtocolAdapter` map slot and adds only its
protocol-specific `ILidoAdapter` slot — one ERC-7201 slot and one new ERC-165 map slot;
UniswapV3Adapter likewise reuses the shared `IProtocolAdapter` map slot and adds only its
protocol-specific `IUniswapV3Adapter` slot — one ERC-7201 slot and one new ERC-165 map slot).

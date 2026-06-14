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
  unique ERC-7201 storage slot but **no** standalone ERC-165 row in the uniqueness arrays.
- Utility libraries that hold no own ERC-7201 storage slot (`EnumerableSet`, `TimelockLib`) and
  token-extension libraries that declare no `*_STORAGE_SLOT` (`ERC20Burnable`, `ERC20Permit`,
  `ERC20Votes`) are intentionally **not** listed here. (`ERC20Permit`, `ERC20Votes`, and
  `ERC20Burnable` do register ERC-165 ids but reuse the underlying `ERC20`/`Votes`/`Nonces`
  storage, so they have no row of their own.)

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

### DeFi

| Module | ERC-7201 namespace | Storage slot (hex) | Interface | interfaceId | ERC-165 map slot (hex) |
|---|---|---|---|---|---|
| VaultCore | `lattice.storage.VaultCore` | `0x391c4f0f82559e85ff01d307d4b19b40f088495abd453c84d7e0fa35497de600` | `IVaultCore` | `0xa86d8962` | `0xee1c77df59bab5696d7427515bb0fba56d8719259c4cc5bc6587a3654b26bdf2` |
| StrategyManager | `lattice.storage.StrategyManager` | `0x1b00913e47c53f1d64d326bde2ad6a7904ed791d4ee4432bc133be907894ca00` | `IStrategyManager` | `0xcce4011b` | `0x3d05027e9ebc1daac4235d8ac5fc59b9acea5ece08ff307b79ab5b69ad569930` |

### AMM

| Module | ERC-7201 namespace | Storage slot (hex) | Interface | interfaceId | ERC-165 map slot (hex) |
|---|---|---|---|---|---|
| ConstantProduct | `lattice.storage.ConstantProduct` | `0xf3baf196a9957c5a93606e180cd873c83f4d725c3513c9295ef6ca05f13a2200` | `IConstantProduct` | `0x8098801f` | `0xe179134a78bc5c2b2530eee9483cf7fd81654d9311d88e7b22e0fa63d02f43cf` |

### Oracles

| Module | ERC-7201 namespace | Storage slot (hex) | Interface | interfaceId | ERC-165 map slot (hex) |
|---|---|---|---|---|---|
| ChainlinkAdapter | `lattice.storage.ChainlinkAdapter` | `0xdbb02d424081d7fb4c59a631e74d23250f514b627bc328ad0ec973d94b228000` | `IChainlinkAdapter` | `0x364fdec9` | `0x65e721c748691ae5a9544827b82a8602440249a42e1438a441599564727a3bd2` |
| ChainlinkVRF | `lattice.storage.ChainlinkVRF` | `0x296a09c3f1dda7c7057a0d3e9cfd88b1666f0f2ebdcbdc2f576bbcf22db0d200` | `IChainlinkVRF` | `0xed74ccf3` | `0x5e805972aa7ebffe06f2b61cc9d80c103d549fa32d030cc2918893026547c07e` |
| TWAPOracle | `lattice.storage.TWAPOracle` | `0xc2bcc163613aea761b734a9692ad3548aab9088be29b53e03facf6a2a351df00` | `ITWAPOracle` | `0xd1baebe0` | `0x3edcb012a40cef5fed8aba3a5816c3233af9ecd91b8a1965a2b67b8940a0f49f` |

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

---

**Counts:** 31 storage-bearing modules (31 unique ERC-7201 slots) and 32 ERC-165 interface
map slots (GovernedDiamondCut reuses IDiamondCut's `0x1f931c1c` ERC-165 slot, so it adds an
ERC-7201 slot but no new ERC-165 map slot).

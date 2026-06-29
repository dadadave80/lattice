# Lattice

Lattice is a Solidity library of modular contract modules built on top of the
[`diamond-lib`](https://github.com/dadadave80/diamond-lib) EIP-2535 Diamond Standard
framework. Most modules ship as a **stateless facet + a library with ERC-7201 namespaced
storage**, so they can be cut into a single Diamond proxy without storage collisions.

The core is an OpenZeppelin Contracts v5-style module set ported into the Diamond facet
pattern. The current tree also includes smart-account, cross-chain, DeFi adapter, oracle,
ENS, marketplace, privacy/ZK, and upgrade-governance modules. It is a Foundry project
consumed as a Forge dependency; there is no application or canonical deployment of its own.

## Status / disclaimer

> **Unaudited. Use at your own risk.** Lattice re-implements OpenZeppelin and adapts
> external protocol interfaces, account standards, bridge/oracle integrations, and ZK/privacy
> primitives. It has **not** been audited and carries no warranty. It has not received the
> review that the upstream libraries it mirrors or composes with have. Do not deploy it to
> mainnet with funds at risk without your own independent audit, especially modules that
> custody assets, verify proofs, bridge messages, or authorize upgrades. Licensed under MIT.

## Modules

| Area | Modules |
|------|---------|
| `access/` | `AccessControl`, `AccessControlEnumerable`, `AccessControlTimed`, `AccessManager` (+ `AccessManaged`, `AccessManagerStandalone`), `Ownable` |
| `accounts/` | Diamond smart-account building blocks — two modular-account flavors ([see below](#smart-account-flavors-erc-7579-and-erc-6900)), each in its own subfolder. **`accounts/erc7579/`:** `AccountDiamond`, `Account7702Diamond`, `AccountFactory`, `AccountInit`, `AccountSigner`, `ERC7821Executor`, `ERC7579ModuleConfig`. **`accounts/erc6900/`:** `ModularAccount6900`, `AccountFactory6900`, `AccountInit6900`, `ERC6900ModuleManager`, `ERC6900Executor`, `ERC6900Validation`, `ERC6900Signature`, `ERC6900AccountView` (+ reference modules `modules/SingleSignerValidation`, `modules/SpendingLimit`). **Shared base + standalone account types (`accounts/`):** `ERC4337Validation`, `ERC1271Signature` (the ERC-4337/1271 base both flavors build on), plus the single-facet standalone types `ERC6551Account` (token-bound) and `SessionKey` |
| `amm/` | `ConstantProduct` |
| `crosschain/` | `AxelarGatewayAdapter`, `BridgeERC20`, `BridgeERC7802`, `CCIPGatewayAdapter`, `CrosschainLink`, `CrosschainTimelockHandler`, `ERC7786OpenBridge`, `WormholeGatewayAdapter` |
| `defi/` | `AaveV3Adapter`, `CompoundV3Adapter`, `CurveStableSwapAdapter`, `ERC4626Adapter`, `LidoAdapter`, `StrategyManager`, `UniswapV3Adapter`, `VaultCore` |
| `ens/` | `ENSResolver`, `ENSReverseClaimer`, `ENSSubnameIssuer` |
| `governance/` | `Governor` (+ `GovernorStandalone`), `TimelockController` (+ `TimelockControllerStandalone`), `Votes`, `GovernedDiamondCut`, `SafeDiamondCut`, `GovernedSafeDiamondCut`, `SafeHarborAdopter` |
| `oracles/` | `API3Adapter`, `API3QRNGAdapter`, `BandAdapter`, `ChainlinkAdapter`, `ChainlinkAutomationAdapter`, `ChainlinkCREAdapter`, `ChainlinkVRF`, `ChronicleAdapter`, `DIAAdapter`, `GelatoAutomateAdapter`, `GelatoVRFAdapter`, `PythAdapter`, `PythEntropyAdapter`, `RedStoneAdapter`, `TWAPOracle`, `TellorAdapter` |
| `privacy/` | `CommitReveal`, `ERC5564Announcer`, `ERC6538Registry`, `Groth16Verifier`, `PlonkVerifier`, `PrivateVoting`, `Semaphore`, `ShieldedPool` |
| `security/` | `Pausable`, `ReentrancyGuard`, `RateLimiter`, `CircuitBreaker`, `EmergencyStop`, `InvariantChecker` |
| `tokens/` | One subfolder per standard (base + extensions flat inside, `<std>/libraries/` for logic). **`tokens/ERC20/`:** `ERC20` (+ `Burnable`, `Capped`, `Crosschain`, `Permit`, `Votes`). **`tokens/ERC721/`:** `ERC721` (+ `URIStorage`). **`tokens/ERC1155/`**, **`tokens/ERC2981/`**, **`tokens/ERC4626/`**, **`tokens/ERC7802/`**. `MarketplaceZone` sits at the `tokens/` root (a Seaport zone enforcing the issuer's own token policy, not a token standard) |
| `utils/` | `EIP712`, `Multicall`, `Nonces`, `VestingWallet` (+ `VestingWalletStandalone`) |

**Utility libraries** (`src/utils/libraries/`) — pure logic with no own storage, facet,
or interface: `Base64`, `Bytes`, `Calldata`, `Checkpoints`, `ECDSA`, `EnumerableSet`,
`InterestRate`, `InteroperableAddress`, `P256`, `Panic`, `ShortStrings`,
`SignatureChecker`, `Strings`, `TimelockLib`, `UniswapV3FullRangeMath`, `WebAuthn`, plus
module helpers such as `EIP712Lib`, `MulticallLib`, `NoncesLib`, and `VestingWalletLib`.

`src/interfaces/external/` vendors minimal third-party ABIs used by adapters and standards
integrations. The canonical storage/interface registry is
[`STORAGE_REGISTRY.md`](STORAGE_REGISTRY.md), and
`test/unit/StorageSlotVerificationTest.t.sol` re-derives every registered slot and checks
global uniqueness.

## Smart-account flavors: ERC-7579 and ERC-6900

Lattice ships **two modular smart-account flavors**, both built on the shared Diamond core
(DiamondCut / Loupe / ERC-165 / AccessControl). They are **separate blueprints** — you pick one
per account; the two facet sets are never cut into the same Diamond. Both target ERC-4337 and
ERC-1271, and both are written fresh in the three-layer facet pattern (the ERC-6900 reference
implementation is GPL and is **not** a dependency — only minimal interfaces are vendored into
`src/interfaces/external/`).

- **ERC-7579** (`AccountDiamond` proxy) — the four fixed module types (validator 1, executor 2,
  fallback 3, hook 4). A per-op validator is selected by the top 20 bytes of `userOp.nonce`; one
  global hook wraps execution; a fallback registry is layered under the facet map.
- **ERC-6900** (`ModularAccount6900` proxy) — inspired by EIP-2535 itself, so it maps onto the
  Diamond most naturally. Validation is a richer `ModuleEntity` (`address ‖ uint32 entityId`)
  with per-validation pre-validation hooks and per-selector pre/post execution hooks — the
  standardized form of a session-key permission. Execution modules are dispatched by **CALL** (so
  they run in their own storage), layered under the facet map.

| Dimension | ERC-7579 | ERC-6900 |
|---|---|---|
| Proxy | `AccountDiamond` | `ModularAccount6900` |
| Factory / init | `AccountFactory` / `AccountInit` | `AccountFactory6900` / `AccountInit6900` |
| Module identity | module address (per type) | `ModuleEntity` = `address ‖ uint32 entityId` |
| Module kinds | 4 fixed types | validation / validation-hook / execution / execution-hook modules |
| userOp validator selection | top 20 bytes of `userOp.nonce` | first 24 bytes of `userOp.signature` |
| Validation scope | by module type | global (per-selector opt-in) **or** a per-selector allowlist |
| Hooks | one global pre/post hook | per-validation pre-validation hooks + per-selector pre/post exec hooks |
| Execution extension | fallback handlers (CALL or DELEGATECALL) | execution-function registry, dispatched by CALL (own storage) |
| Session-key permissions | `SessionKey` library (ad hoc) | a validation + attached hooks (standardized) |
| Introspection | `DiamondLoupe` | `IERC6900AccountView` (`getExecutionData` / `getValidationData`) |
| Config authority | account-self or admin | account-self or admin (config is admin-gated, not validation-gated) |

The ERC-6900 facets: `ERC6900ModuleManager` (install/uninstall validations + executions),
`ERC6900Executor` (`execute` / `executeBatch` / `executeWithRuntimeValidation` plus the proxy's
execution-module dispatch), `ERC6900Validation` (ERC-4337 `validateUserOp`), `ERC6900Signature`
(ERC-1271, ERC-7739-bound to the account's domain so signatures can't be replayed across
accounts), and `ERC6900AccountView` (the loupe). Reference modules `SingleSignerValidation` and
`SpendingLimit` demonstrate the validation and execution-hook module shapes.

## Architecture: three-layer facet pattern

Diamond facets must be **stateless** — proxy state lives in the Diamond, not the facet —
so facet modules are split into three files with strict responsibilities:

```
src/interfaces/<area>/IFoo.sol # ABI, custom errors, events. Wide pragma (>=0.8.4)
        ▲                       # interfaces mirror the module's <area> folder
src/<area>/libraries/FooLib.sol # ALL logic + ERC-7201 storage + __Foo_init(...)
        ▲                       # storage read via a single FooStorage() -> hardcoded slot
src/<area>/Foo.sol              # stateless facet: virtual fns that forward to FooLib
```

```solidity
// src/<area>/Foo.sol — facet: no state, no logic, just delegation
contract Foo is IFoo {
    function bar(uint256 x) external virtual returns (uint256) {
        return FooLib.bar(x);
    }
}
```

A handful of **utility libraries** (see above) skip this split: they are pure logic with
no own ERC-7201 slot, no interface file, and no facet — the consuming module owns any
storage struct they operate on. A few contracts are standalone rather than facets where the
standard or deployment model requires it, for example `AccountFactory`, `GovernorStandalone`,
`TimelockControllerStandalone`, `AccessManagerStandalone`, and `VestingWalletStandalone`.

## Install / usage

Install as a Forge dependency:

```sh
forge install dadadave80/lattice
git submodule update --init --recursive   # diamond-lib + forge-std submodules
```

Add the remappings (mirror of this repo's `remappings.txt` / `foundry.toml`):

```
@lattice/=lib/lattice/src/
@diamond/=lib/diamond-lib/src/
forge-std/=lib/forge-std/src/
```

Because facets have no constructors, proxy state is set up through `diamond-lib`'s
`InitializableLib` with a three-call dance the consumer performs once per module:

```solidity
import {AccessControlLib} from "@lattice/access/libraries/AccessControlLib.sol";
import {InitializableLib} from "@diamond/.../InitializableLib.sol";

function initialize(address _admin) external {
    bytes32 s = InitializableLib.initializableSlot();
    InitializableLib.preInitializer(s);              // set initializing flag, check version
    AccessControlLib.__AccessControl_init(_admin);   // module init (gated by checkInitializing)
    InitializableLib.postInitializer(s);             // clear flag, emit Initialized
}
```

When adding new modules, be deliberate about caller semantics. Some existing modules use
`msg.sender` directly because they authenticate protocol callbacks, Safe calls, EntryPoint
calls, or Diamond self-dispatch. If a module is intended to support forwarded calls, use the
project's established caller-resolution pattern consistently through the library layer.

## Build & test

```sh
forge build                                    # compile
forge test                                     # run all tests
forge test --match-contract AccessControl -vvv # verbose, by contract
forge test --match-contract StorageSlotVerificationTest # verify ERC-7201/ERC-165 slots
forge fmt                                       # format (CI runs `forge fmt --check`)
forge snapshot                                  # gas snapshots
```

The suite currently includes unit, integration, fork, fuzz, invariant, and gas tests. CI
runs with `FOUNDRY_PROFILE=ci` (`optimizer_runs = 1_000_000`, `via_ir = false`). A green
local `forge test` does not guarantee CI passes if optimizer behavior diverges — run
`FOUNDRY_PROFILE=ci forge build --sizes` before pushing if you touch hot paths.

## Layout

```
src/
├── access/        # AccessControl(+Enumerable,+Timed), AccessManager(+Managed,+Standalone), Ownable
├── accounts/      # Diamond smart accounts — erc7579/ & erc6900/ flavor subfolders + shared (ERC-4337/1271/6551, session keys)
├── amm/           # ConstantProduct
├── crosschain/    # CCIP, Axelar, Wormhole, ERC-7786, bridge tokens, cross-chain timelock
├── defi/          # Aave, Compound, Curve, Lido, Uniswap V3, ERC4626 adapters, vault/strategy modules
├── ens/           # ENS resolver, reverse claimer, subname issuer
├── governance/    # Governor, timelock, governed/Safe diamond cuts, Safe Harbor adoption
├── oracles/       # Chainlink, Pyth, RedStone, Chronicle, DIA, API3, Band, Tellor, Gelato, TWAP
├── privacy/       # Commit-reveal, stealth address standards, Groth16/PLONK, Semaphore, shielded pool
├── security/      # Pausable, ReentrancyGuard, RateLimiter, CircuitBreaker, EmergencyStop, InvariantChecker
├── tokens/        # per-standard subfolders ERC20/ ERC721/ ERC1155/ ERC2981/ ERC4626/ ERC7802/ (base+extensions); MarketplaceZone at root
├── utils/         # EIP712, Multicall, Nonces, VestingWallet(+Standalone)
│   └── libraries/ # Crypto, encoding, strings, checkpoints, math, multicall/nonces/vesting helpers
└── interfaces/    # I<Module>.sol mirrored into per-<area> subfolders; external/ for third-party ABIs
```

Each `<area>/` also contains a `libraries/` subfolder holding the `<Module>Lib.sol`
logic libraries for that area.

## License

MIT

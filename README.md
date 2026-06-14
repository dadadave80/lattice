# Lattice

Lattice is a Solidity library of modular contract modules built on top of the
[`diamond-lib`](https://github.com/dadadave80/diamond-lib) EIP-2535 Diamond Standard
framework. Each module ships as a **stateless facet + a library with ERC-7201 namespaced
storage**, so any combination of modules can be cut into a single Diamond proxy without
storage collisions. Functionally it is a re-implementation of OpenZeppelin Contracts
v5.1.0 — with a few Solady primitives and adaptations of Uniswap V2 and Yearn V3 — ported
into the Diamond facet pattern. It is a Foundry project consumed as a Forge dependency;
there is no application or deployment of its own.

## Status / disclaimer

> **Unaudited. Use at your own risk.** Lattice re-implements OpenZeppelin (and adapts
> other) contracts; it has **not** been audited and carries no warranty. It has not
> received the review that the upstream libraries it mirrors have. Do not deploy it to
> mainnet with funds at risk without your own independent audit. Licensed under MIT.

## Modules

| Area | Modules |
|------|---------|
| `access/` | `AccessControl`, `AccessControlEnumerable`, `AccessControlTimed`, `AccessManager` (+ `AccessManaged`, `AccessManagerStandalone`), `Ownable` |
| `tokens/` | `ERC20` (+ `Burnable`, `Capped`, `Permit`, `Votes`), `ERC721` (+ `URIStorage`), `ERC1155`, `ERC2981`, `ERC4626` |
| `governance/` | `Governor` (+ `GovernorStandalone`), `TimelockController` (+ `TimelockControllerStandalone`), `Votes` |
| `defi/` | `VaultCore`, `StrategyManager` |
| `amm/` | `ConstantProduct` |
| `oracles/` | `ChainlinkAdapter`, `ChainlinkVRF`, `TWAPOracle` |
| `security/` | `Pausable`, `ReentrancyGuard`, `RateLimiter`, `CircuitBreaker`, `EmergencyStop`, `InvariantChecker` |
| `utils/` | `EIP712`, `Multicall`, `Nonces`, `VestingWallet` (+ `VestingWalletStandalone`) |

**Utility libraries** (`src/utils/libraries/`) — pure logic with no own storage, facet,
or interface: `ECDSA`, `SignatureChecker`, `ShortStrings`, `Checkpoints`,
`EnumerableSet`, `TimelockLib`, `InterestRate`, `VestingWalletLib`, `MulticallLib`,
`NoncesLib`.

## Architecture: three-layer facet pattern

Diamond facets must be **stateless** — proxy state lives in the Diamond, not the facet —
so every module is split into three files with strict responsibilities:

```
src/interfaces/IFoo.sol        # ABI, custom errors, events. Wide pragma (>=0.8.4)
        ▲
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
storage struct they operate on.

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

Inside library code, use `ContextLib.msgSender()` (from `diamond-lib`) rather than
`msg.sender` so modules stay compatible with meta-transaction / trusted-forwarder setups.

## Build & test

```sh
forge build                                    # compile
forge test                                     # run all tests
forge test --match-contract AccessControl -vvv # verbose, by contract
forge fmt                                       # format (CI runs `forge fmt --check`)
forge snapshot                                  # gas snapshots
```

CI runs with `FOUNDRY_PROFILE=ci` (`optimizer_runs = 1_000_000`, `via_ir = false`). A
green local `forge test` does not guarantee CI passes if optimizer behavior diverges —
run `FOUNDRY_PROFILE=ci forge build --sizes` before pushing if you touch hot paths.

## Layout

```
src/
├── access/        # AccessControl(+Enumerable,+Timed), AccessManager(+Managed,+Standalone), Ownable
├── tokens/        # ERC20(+Burnable,Capped,Permit,Votes), ERC721(+URIStorage), ERC1155, ERC2981, ERC4626
├── governance/    # Governor(+Standalone), TimelockController(+Standalone), Votes
├── defi/          # VaultCore, StrategyManager
├── amm/           # ConstantProduct
├── oracles/       # ChainlinkAdapter, ChainlinkVRF, TWAPOracle
├── security/      # Pausable, ReentrancyGuard, RateLimiter, CircuitBreaker, EmergencyStop, InvariantChecker
├── utils/         # EIP712, Multicall, Nonces, VestingWallet(+Standalone)
│   └── libraries/ # ECDSA, SignatureChecker, ShortStrings, Checkpoints, EnumerableSet,
│                  #   TimelockLib, InterestRate, VestingWalletLib, MulticallLib, NoncesLib
└── interfaces/    # I<Module>.sol per module; external/ for third-party ABIs
```

Each `<area>/` also contains a `libraries/` subfolder holding the `<Module>Lib.sol`
logic libraries for that area.

## License

MIT

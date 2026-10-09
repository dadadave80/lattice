# 0006. Diamonds are created and initialized atomically through `LatticeFactory`

- **Status:** Accepted
- **Date:** [#182](https://github.com/dadadave80/lattice/pull/182) (2026-09-11); recorded 2026-10-09

## Context

[`Lattice.initialize`](../../src/Lattice.sol) applies the initial cut and runs the init `delegatecall`. It
is first-caller-wins: whoever calls it first chooses every facet of the diamond, including its upgrade
path. Recipe scripts used to send the proxy creation and `initialize` as two transactions, so anyone
watching the mempool could initialize the proxy in between.

## Options considered

From the design comparison in #182:

1. **Deployer-gated `initialize`.** Rejected: an immutable deployer check breaks generic CREATE2
   deployers and atomic ERC-4337 and ERC-7702 flows, and under 7702 delegation or behind a proxy the
   "deployer" would be the implementation's.
2. **Initialization in the constructor.** Rejected: constructor arguments change the initcode, which
   breaks the factory's constant CREATE2 derivation, and account implementations must stay uninitialized.
3. **A new `LatticeDeployer` helper.** Atomic, but it duplicates the factory path, adds a deployment per
   diamond and gives no caller-bound address prediction.
4. **The existing `LatticeFactory`.** Chosen: one atomic path with caller-bound CREATE2 addresses and
   factory-level recipe checks.

## Decision

- Every diamond is created and initialized in one transaction. `LatticeFactory.deploy` creates the proxy
  with CREATE2 and calls `initialize` in the same call.
- The CREATE2 salt is `keccak256(abi.encode(msg.sender, salt))`, so only the caller can occupy its
  addresses. The proxy has no constructor arguments, so its initcode hash is constant.
- A recipe's broadcasting `run()` deploys through `BaseDeploy._assemble`, which calls the factory and
  refuses an occupied address instead of taking the factory's idempotent return.
  `DeployGovernedVault.deployAtomic` calls `factory.deploy` directly and does take the idempotent return,
  so its caller must pass a fresh salt per recipe. No script creates a `Lattice` and initializes it
  separately.
- Smart accounts use their own factories (`AccountFactory`, `AccountFactory6900`), which follow the same
  rule.

## Consequences

- No mempool window exists between creation and initialization.
- The diamond address commits to the caller and salt, not to the recipe. A repeat `deploy` with the same
  caller and salt returns the existing diamond and ignores the new recipe, so callers use one salt per
  recipe. #176 weighs a strict mode that reverts instead.
- The factory is the caller of `initialize`, so an init that grants `msg.sender` a role grants it to the
  factory. No shipped init does this; `test_Finding_InitGrantingMsgSenderGrantsTheFactory` pins the
  behaviour.
- Hand-written deployments outside `BaseDeploy` must keep creation and initialization atomic themselves.

## Confirmation

- `make check-atomic-deploy` fails when any `script/` Solidity file contains `new Lattice` or an
  `.initialize(` call. It then broadcasts a recipe to Anvil and asserts one factory `deploy`, no standalone
  `initialize`, an initialized diamond, salt-reuse rejection and reuse of a configured factory.
- `BaseDeployTest` covers `_assemble` (`test_AssembleDeploysAndInitializesThroughFactory`,
  `test_AssembleRevertsWhenAddressAlreadyDeployed`).
- The [add-a-module checklist](../../CONTRIBUTING.md#adding-a-module) forbids `new Lattice` or a separate
  `initialize` call in `script/`.

## References

- [#182](https://github.com/dadadave80/lattice/pull/182) (the design comparison and gas measurements)
- [`LatticeFactory.sol`](../../src/LatticeFactory.sol), [`BaseDeploy.s.sol`](../../script/base/BaseDeploy.s.sol)
- [Registry and factory threat model](../security/registry-factory-threat-model.md)
- [#176](https://github.com/dadadave80/lattice/issues/176)

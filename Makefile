# Lattice — developer entry points.
#
# Every target mirrors a real workflow (the CI gates in .github/workflows/test.yml, the
# storage-layout guard, the fork suites, the demo loops) — `make ci` locally is the same
# sequence CI runs. This Makefile deliberately does NOT source .env: forge/cast auto-load
# it themselves, and it holds keystore settings (ETH_KEYSTORE_ACCOUNT) that must not leak
# into recipe environments.
#
# Common knobs:
#   make test MATCH=CCTPBridgeAdapter     # filter by contract name
#   make test-path PATH_GLOB=test/fork/CCTPUSDCDemoFork.t.sol
#   make demo-cctp ARGS='arc 0xYourActor' FORGE_AUTH='--account daveKey'

.DEFAULT_GOAL := help

MATCH ?=
PATH_GLOB ?=
ARGS ?=

# ---------------------------------------------------------------- build & test

.PHONY: build
build: ## Compile the project
	forge build

.PHONY: test
test: ## Run the test suite (MATCH=<Contract> to filter)
ifeq ($(strip $(MATCH)),)
	forge test
else
	forge test --match-contract $(MATCH)
endif

.PHONY: test-v
test-v: ## Verbose test run (MATCH=<Contract> to filter)
ifeq ($(strip $(MATCH)),)
	forge test -vvv
else
	forge test --match-contract $(MATCH) -vvv
endif

.PHONY: test-path
test-path: ## Run tests by path (PATH_GLOB=test/fork/Foo.t.sol)
	forge test --match-path '$(PATH_GLOB)'

.PHONY: test-fork
test-fork: ## Run the fork suites (env-gated: SEPOLIA/BASE_SEPOLIA/ARC_TESTNET/MAINNET _RPC_URL; unset lanes skip cleanly)
	forge test --match-path 'test/fork/*'

.PHONY: snapshot
snapshot: ## Regenerate gas snapshots
	forge snapshot

.PHONY: clean
clean: ## Remove build artifacts (do this before trusting any gate after agents/tools touched the tree)
	forge clean

# ---------------------------------------------------------------------- format

.PHONY: fmt
fmt: ## Format Solidity sources
	forge fmt

.PHONY: fmt-check
fmt-check: ## Formatting gate (what CI runs)
	forge fmt --check

# ------------------------------------------------------------------- CI mirror
# The same gates as .github/workflows/test.yml, in the same configuration
# (FOUNDRY_PROFILE=ci: optimizer_runs=1_000_000, via_ir=false).

.PHONY: sizes
sizes: ## EIP-170 size gate under the CI profile (skips test/script)
	FOUNDRY_PROFILE=ci forge build --sizes --skip test script

.PHONY: via-ir
via-ir: ## IR-pipeline parity build (catches stack-too-deep / IR-only errors)
	forge build --via-ir --skip test script

.PHONY: storage-check
storage-check: ## ERC-7201 append-only storage-layout guard
	./script/upgrades/check-storage-layout.sh

.PHONY: storage-update
storage-update: ## Regenerate the storage-layout baseline (review the diff — appends only!)
	./script/upgrades/check-storage-layout.sh --update

.PHONY: test-ci
test-ci: ## Full test suite under the CI profile
	FOUNDRY_PROFILE=ci forge test

.PHONY: ci
ci: fmt-check sizes via-ir storage-check test-ci ## All CI gates, locally, in CI order

.PHONY: slither
slither: ## Static analysis (advisory, mirrors CI's slither job; needs slither installed)
	@command -v slither >/dev/null 2>&1 || { echo "slither not installed (pip install slither-analyzer)"; exit 1; }
	slither .

# ----------------------------------------------------------------------- demos
# Both loops read their own env (FORGE_AUTH etc.) and document their CLI in their
# headers; ARGS is passed through verbatim so this file never chases their flags.
#   make demo-governance ARGS='<vault> <ens-name> <actor>' FORGE_AUTH='--account <ks>'
#   make demo-cctp       ARGS='<loop args>'                FORGE_AUTH='--account <ks>'

.PHONY: demo-governance
demo-governance: ## Governance demo crank loop (see script/config/governance-demo-loop.sh -h)
	script/config/governance-demo-loop.sh $(ARGS)

.PHONY: demo-cctp
demo-cctp: ## CCTP USDC demo crank loop (see script/config/cctp-usdc-demo-loop.sh -h)
	script/config/cctp-usdc-demo-loop.sh $(ARGS)

# ------------------------------------------------------------------------ help

.PHONY: help
help: ## List targets
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

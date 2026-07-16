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
#   make demo-cctp deplKey ~/.demo.pw     # keystore name + optional password file

.DEFAULT_GOAL := help

MATCH ?=
PATH_GLOB ?=
ARGS ?=
SCRIPT ?=
SIG ?= run()
ANVIL_PORT ?= 8545
# Well-known Anvil dev account #0. LOCAL NODE ONLY — publicly known, never a real network.
# Overridable, but the default is intentionally this throwaway key so `deploy-local` needs no secret.
ANVIL_KEY ?= 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# ------------------------------------------------------------------ dependencies

.PHONY: install
install: ## Fetch dependencies (git submodules: diamond-lib, forge-std, …)
	git submodule update --init --recursive

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

# -------------------------------------------------------------- docs & coverage

.PHONY: doc
doc: ## Build the module reference (forge doc → docs/, gitignored)
	forge doc

.PHONY: doc-serve
doc-serve: ## Build and serve the docs locally (http://localhost:4000)
	forge doc --serve --port 4000

.PHONY: coverage
coverage: ## Coverage summary (slow; add --ir-minimum via ARGS if a suite hits stack-too-deep)
	forge coverage --report summary $(ARGS)

# --------------------------------------------------------------------- local node
# `deploy-local` signs with the well-known Anvil key (ANVIL_KEY) against the local
# node ONLY. Pass the script and, if its entrypoint isn't run(), its signature/args:
#   make deploy-local SCRIPT=script/base/security/DeployEmergencyStop.s.sol
#   make deploy-local SCRIPT=path SIG='run(address)' ARGS='0xabc…'

.PHONY: anvil
anvil: ## Start a local Anvil node
	anvil --port $(ANVIL_PORT)

.PHONY: deploy-local
deploy-local: ## Deploy SCRIPT to local Anvil (SCRIPT=… [SIG='run()'] [ARGS='…'])
	@test -n '$(SCRIPT)' || { echo "set SCRIPT=<path/to/Deploy*.s.sol> (and SIG/ARGS if run() takes params)"; exit 2; }
	forge script $(SCRIPT) --sig '$(SIG)' $(ARGS) \
		--rpc-url http://localhost:$(ANVIL_PORT) --private-key $(ANVIL_KEY) --broadcast

# ----------------------------------------------------------------------- demos
# demo-cctp takes POSITIONAL args:  make demo-cctp <keystore-name> [password-file]
#   e.g.  make demo-cctp deplKey ~/.demo.pw
# It builds FORGE_AUTH='--account <name> [--password-file <file>]' and runs the Arc-hub loop, which
# derives the signer address from the keystore and drives BOTH destinations (Sepolia + Base Sepolia).
# Pass the tilde path UNQUOTED so your shell expands ~ before make sees it (or give an absolute path).
# Make treats those bare words as goals, so when demo-cctp is the goal we capture them from MAKECMDGOALS
# and register them as no-op targets -- scoped to this invocation only, so other targets are unaffected.
#   demo-governance keeps the ARGS/FORGE_AUTH form (its CLI takes vault/ens-name/actor, not just a key).
ifeq (demo-cctp,$(firstword $(MAKECMDGOALS)))
  DEMO_KEY := $(word 2,$(MAKECMDGOALS))
  DEMO_PW  := $(word 3,$(MAKECMDGOALS))
  DEMO_EXTRA := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
  ifneq ($(strip $(DEMO_EXTRA)),)
    $(eval $(DEMO_EXTRA):;@:)
  endif
endif

.PHONY: demo-governance
demo-governance: ## Governance demo crank loop (ARGS='<vault> <ens> <actor>' FORGE_AUTH='--account <ks>')
	script/config/governance-demo-loop.sh $(ARGS)

.PHONY: demo-cctp
demo-cctp: ## CCTP demo: make demo-cctp <keystore-name> [password-file]  (e.g. deplKey ~/.demo.pw)
	@key='$(DEMO_KEY)'; pw='$(DEMO_PW)'; auth='$(FORGE_AUTH)'; \
	if [ -n "$$key" ]; then auth="--account $$key"; [ -n "$$pw" ] && auth="$$auth --password-file $$pw"; fi; \
	if [ -z "$$auth" ]; then \
	  echo "usage: make demo-cctp <keystore-name> [password-file]   (e.g. make demo-cctp deplKey ~/.demo.pw)"; \
	  echo "       (or set FORGE_AUTH='--account <name> [--password-file <file>]')"; exit 2; \
	fi; \
	FORGE_AUTH="$$auth" script/config/cctp-usdc-demo-loop.sh $(ARGS)

# ------------------------------------------------------------------------ help

.PHONY: help
help: ## List targets
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

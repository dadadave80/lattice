# Lattice — developer entry points.
#
# Every target mirrors a real workflow (the CI gates in .github/workflows/test.yml, the
# storage-layout guard, the fork suites, the demo loops) — `make ci` locally is the same
# sequence CI runs. This Makefile deliberately does NOT source .env: forge/cast auto-load
# it themselves, and its secrets (API keys, keyed RPC URLs) must not leak into recipe
# environments.
#
# Common knobs:
#   make test MATCH=CCTPBridgeAdapter     # filter by contract name
#   make test-path PATH_GLOB=test/fork/CCTPUSDCDemoFork.t.sol
#   make demo-cctp-hook KEYSTORE=deplKey              # unattended; password from the macOS Keychain
#   make demo-cctp-hook PRIVATE_KEY=0x<testnet-key>   # any OS; raw testnet key

.DEFAULT_GOAL := help

MATCH ?=
PATH_GLOB ?=
ARGS ?=
SCRIPT ?=
SIG ?= run()
# Script target contract; defaults to the file's basename (DeployX.s.sol -> DeployX). Needed because
# recipe files also hold their recipe-local '*RecipeInit' contract, so forge cannot infer the target.
TC ?= $(notdir $(basename $(basename $(SCRIPT))))
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
# node ONLY, promptless. (Keep keystore settings like ETH_KEYSTORE_ACCOUNT out of .env —
# forge auto-loads it and an ambient keystore hijacks vm.startBroadcast away from
# --private-key.) Pass the script and, if its entrypoint isn't run(), its signature/args:
#   make deploy-local SCRIPT=script/base/security/DeployEmergencyStop.s.sol
#   make deploy-local SCRIPT=path SIG='run(address)' ARGS='0xabc…'

.PHONY: anvil
anvil: ## Start a local Anvil node
	anvil --port $(ANVIL_PORT)

.PHONY: deploy-local
deploy-local: ## Deploy SCRIPT to local Anvil (SCRIPT=… [SIG='run()'] [ARGS='…'])
	@test -n '$(SCRIPT)' || { echo "set SCRIPT=<path/to/Deploy*.s.sol> (and SIG/ARGS if run() takes params)"; exit 2; }
	forge script $(SCRIPT) --tc '$(TC)' --sig '$(SIG)' $(ARGS) \
		--rpc-url http://localhost:$(ANVIL_PORT) --private-key $(ANVIL_KEY) --broadcast

# ----------------------------------------------------------------------- demos
# Every demo target takes keystore auth either way:
#   KEYSTORE=<name>              foundry keystore, ANY OS. On macOS the password is fetched from
#                                the Keychain item 'foundry-<name>' into a 0600 temp file deleted
#                                on exit — UNATTENDED, zero prompts. One-time setup per keystore:
#                                  security add-generic-password -a "$USER" -s foundry-<name> -w
#                                On other OSes it runs ATTENDED: forge/cast prompt for the
#                                keystore password at each signing step.
#   PRIVATE_KEY=0x<key>          ANY OS, unattended: forwarded as FORGE_AUTH='--private-key …'.
#                                Testnet keys only — the key is visible in local process args.
#   FORGE_AUTH='--account <ks>'  ATTENDED: forwarded verbatim; forge prompts per signing step.
#                                (Add --password-file <f> yourself for a manual unattended run.)
#   make demo-governance  KEYSTORE=<name> ARGS='<vault> <ens-name> <actor>'
#   make demo-cctp        KEYSTORE=<name>      # Arc-hub loop: both destinations; ARGS='<dest>' filters
#   make demo-cctp-hook   KEYSTORE=<name>      # hook showcase; ARGS='<actor> <beneficiary>' optional
#   make demo-cctp-receipt KEYSTORE=<name>     # direct USDC delivery + position-style receipt NFT
#   make demo-cctp-roundtrip KEYSTORE=<name>   # USDC Arc -> Base -> Arc; ARGS='<actor>' optional
#   make deploy-cctp      KEYSTORE=<name>      # deploy your OWN stack — serves ALL CCTP demos
# The hook demo (Arc -> Base Sepolia) showcases CCTP v2 HOOKS: one attested message both moves USDC
# and auto-credits a beneficiary in a CCTPHookVault; the round trip moves USDC Arc -> Base -> Arc
# through Lattice diamonds on both ends. Deployment is SEPARATE from the demos: anyone with a funded
# signer can run them against the canonical live stack (README evidence contracts; round-trip-ready);
# deploy-cctp deploys ONE fresh stack (Arc hub registered for BOTH destinations + Base diamond with
# the Arc return leg + vault) that all three CCTP demos then run against.

# Expands to the auth wrapper: the keystore helper when KEYSTORE is set, else FORGE_AUTH built from
# PRIVATE_KEY, else nothing (an ambient FORGE_AUTH passes through) — every demo recipe is then a
# single `$(AUTH_WRAP) <script> $(ARGS)` line and new demos cannot drift from the pattern.
# PRIVATE_KEY counts ONLY when given on the make command line: GNU make imports shell-exported env
# vars as make variables, and an ambient `export PRIVATE_KEY=…` (common for other EVM tooling, and
# possibly a MAINNET key) must never silently become the signer — the same ambient-auth hijack class
# the header bans for ETH_KEYSTORE_ACCOUNT. Precedence: KEYSTORE > PRIVATE_KEY > your FORGE_AUTH.
CLI_PRIVATE_KEY = $(if $(filter command line,$(origin PRIVATE_KEY)),$(PRIVATE_KEY))
AUTH_WRAP = $(if $(KEYSTORE),script/config/keychain-auth.sh "$(KEYSTORE)",$(if $(CLI_PRIVATE_KEY),FORGE_AUTH='--private-key $(CLI_PRIVATE_KEY)',))

# Grant walkthrough: RPC accepts a Foundry alias or URL. Local time travel is explicit.
RPC ?= http://127.0.0.1:$(ANVIL_PORT)
LOCAL ?= 0
VERIFY ?= 1
VERIFIER ?= etherscan
VERIFIER_URL ?=
POLL_INTERVAL ?= 5
WAIT_TIMEOUT ?= 3600
example: export RPC_URL = $(RPC)
example: export LOCAL := $(LOCAL)
example: export VERIFY := $(VERIFY)
example: export VERIFIER := $(VERIFIER)
example: export VERIFIER_URL := $(VERIFIER_URL)
example: export POLL_INTERVAL := $(POLL_INTERVAL)
example: export WAIT_TIMEOUT := $(WAIT_TIMEOUT)

.PHONY: example test-grant-runner
example: ## Deploy and run the complete example: RPC=<alias|URL> KEYSTORE=<name> (LOCAL=1 for Anvil)
	@$(AUTH_WRAP) examples/governance-upgradeable-diamond/run.sh

test-grant-runner: ## Check M2 runner authentication, RPC timing, and transaction failures
	@bash examples/governance-upgradeable-diamond/test-run.sh

.PHONY: demo-governance
demo-governance: ## Governance demo loop — KEYSTORE=/PRIVATE_KEY= ARGS='<vault> <ens> <actor>'
	@$(AUTH_WRAP) script/config/governance-demo-loop.sh $(ARGS)

.PHONY: demo-cctp
demo-cctp: ## CCTP Arc-hub demo loop — KEYSTORE=/PRIVATE_KEY=; ARGS='<dest>' filters
	@$(AUTH_WRAP) script/config/cctp-usdc-demo-loop.sh $(ARGS)

.PHONY: deploy-cctp
deploy-cctp: ## Deploy ONE CCTP demo stack (Arc hub + Base diamond + vault) serving all three CCTP demos — KEYSTORE=/PRIVATE_KEY=
	@$(AUTH_WRAP) script/config/cctp-hook-demo.sh --deploy-only $(ARGS)

.PHONY: demo-cctp-hook
demo-cctp-hook: ## CCTP v2 hook demo vs the live stack (Arc->Base auto-credit) — KEYSTORE=/PRIVATE_KEY=
	@$(AUTH_WRAP) script/config/cctp-hook-demo.sh $(ARGS)

.PHONY: deploy-cctp-receipt
deploy-cctp-receipt: ## Deploy a receipt NFT against an existing Base CCTP diamond — KEYSTORE=/PRIVATE_KEY=
	@$(AUTH_WRAP) script/config/cctp-hook-receipt-demo.sh --deploy-only $(ARGS)

.PHONY: demo-cctp-receipt
demo-cctp-receipt: ## CCTP receipt NFT demo — Arc->Base USDC delivery + on-chain receipt
	@$(AUTH_WRAP) script/config/cctp-hook-receipt-demo.sh $(ARGS)

.PHONY: demo-cctp-roundtrip
demo-cctp-roundtrip: ## USDC round trip Arc -> Base -> Arc through Lattice diamonds both ways — KEYSTORE=/PRIVATE_KEY=
	@$(AUTH_WRAP) script/config/cctp-roundtrip-demo.sh $(ARGS)

.PHONY: demo
demo: ## Interactive CCTP demo tester — pick direction, amount, auth (KEYSTORE=/PRIVATE_KEY= pre-seed the auth)
	@$(AUTH_WRAP) script/config/cctp-demo-interactive.sh

# ------------------------------------------------------------------------ help

.PHONY: help
help: ## List targets
	@grep -hE '^[a-zA-Z0-9_-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

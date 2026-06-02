# ==============================================================================
# Makefile for Foundry Smart Contract Project
# ==============================================================================
#
# Requirements:
#   - Foundry (forge, cast) >= 0.2.0
#   - Slither >= 0.10.0
#   - Node.js >= 20 (for solhint)
#   - solhint (npm install -g solhint)
#   - yq >= 4.0 (for TOML parsing: brew install yq)
#
# ==============================================================================

# Core commands
.PHONY: all build clean test format lint analyze check install update sizes remove check-headers
.PHONY: coverage snapshot gas-report help

# CREATE2 factory deployment
.PHONY: fund-arachnid-factory-deployer deploy-arachnid-factory fund-den-factory-deployer fund-mls-contracts-deployer deploy-den-factory

# Safe 1.4.1 deployment
.PHONY: deploy-safe-infra deploy-safe-infra-dry-run deploy-safe-multisigs deploy-safe-multisigs-dry-run fund-safe-owners

# Guardian Safe Executor Module
.PHONY: deploy-batched-transaction
.PHONY: deploy-guardian-safe-module guardian-safe-add-module guardian-safe-remove-module check-guardian-module-status

# Platform deployment
.PHONY: deploy-independent-libs deploy-dependent-libs deploy-libraries deploy-contracts deploy-platform validate-signer-vars
.PHONY: deploy-independent-libs-dry-run deploy-dependent-libs-dry-run deploy-libraries-dry-run deploy-contracts-dry-run deploy-platform-dry-run

# Implementation Whitelist
.PHONY: whitelist-implementations unwhitelist-implementations check-whitelist-status is-implementation-whitelisted

# Utilities
.PHONY: check-factory check-all-factories check-deployment check-all-deployments compute-addresses compute-all-addresses verify verify-all find-proxy verify-proxies

# ==============================================================================
# Help
# ==============================================================================

help:
	@echo "Usage: make <target> [VARIABLE=value ...]"
	@echo ""
	@echo "Core Commands:"
	@echo "  all            Clean, reinstall dependencies, and build (default)"
	@echo "  build          Compile contracts"
	@echo "  test           Run tests"
	@echo "  check          Run all checks (format, lint, analyze, sizes, test)"
	@echo "  format         Fix code formatting"
	@echo "  lint           Check code style (no fixes)"
	@echo "  check-headers  Verify SPDX license and copyright headers"
	@echo "  analyze        Run Slither static analysis"
	@echo "  sizes          Show contract sizes"
	@echo "  coverage       Generate test coverage report"
	@echo "  snapshot       Generate gas snapshot"
	@echo "  gas-report     Run tests with gas reporting"
	@echo "  clean          Remove build artifacts"
	@echo "  remove         Remove dependencies (lib/)"
	@echo "  install        Install dependencies"
	@echo "  update         Update dependencies"
	@echo ""
	@echo "Safe 1.4.1 Deployment:"
	@echo "  deploy-safe-infra              Deploy Safe 1.4.1 infrastructure contracts"
	@echo "  deploy-safe-infra-dry-run      Simulate Safe infrastructure deployment (no broadcast)"
	@echo "  deploy-safe-multisigs          Deploy Guardian and Admin Safe multisigs"
	@echo "  deploy-safe-multisigs-dry-run  Simulate Safe multisig deployment (no broadcast)"
	@echo "  fund-safe-owners               Fund the prod/nonprod Safe owners (uses FUND_ENV, FUND_AMOUNT)"
	@echo ""
	@echo "Guardian Safe Executor Module:"
	@echo "  deploy-batched-transaction        Deploy BatchedTransaction contract"
	@echo "  deploy-guardian-safe-module       Deploy SafeExecutorModule for the Guardian Safe"
	@echo "  guardian-safe-add-module          Approve adding the module to Guardian Safe (owner operation)"
	@echo "  guardian-safe-remove-module       Approve removing the module from Guardian Safe (owner operation)"
	@echo "  check-guardian-module-status      Check approval status for Guardian Safe module transaction"
	@echo ""
	@echo "Platform Deployment:"
	@echo "  deploy-independent-libs   Deploy independent libraries via CREATE2"
	@echo "  deploy-dependent-libs     Deploy dependent libraries (Init, AccountSig) via CREATE2"
	@echo "  deploy-libraries          Deploy all platform libraries (both stages)"
	@echo "  deploy-contracts          Deploy platform contracts with library linking"
	@echo "  deploy-platform           Full deployment (libraries + contracts)"
	@echo "  deploy-libraries-dry-run  Simulate all library deployment (no broadcast)"
	@echo "  deploy-contracts-dry-run  Simulate contract deployment (no broadcast)"
	@echo "  deploy-platform-dry-run   Simulate full deployment (no broadcast)"
	@echo ""
	@echo "Implementation Whitelist (deployed by deploy-contracts; seeded via Admin Safe txs):"
	@echo "  whitelist-implementations    Approve whitelisting one or more implementations (Admin Safe owner operation)"
	@echo "  unwhitelist-implementations  Approve removing one or more implementations from the whitelist (owner operation)"
	@echo "  check-whitelist-status       Check approval status for an implementation whitelist transaction"
	@echo "  is-implementation-whitelisted  Read whether an implementation is currently whitelisted (exits non-zero if not)"
	@echo ""
	@echo "CREATE2 Factory Deployment:"
	@echo "  fund-arachnid-factory-deployer  Fund the Arachnid CREATE2 factory deployer EOA"
	@echo "  deploy-arachnid-factory         Deploy the Arachnid CREATE2 factory"
	@echo "  fund-den-factory-deployer       Fund the Den CREATE2 factory deployer EOA (requires DEN_FACTORY_DEPLOYER_ADDRESS)"
	@echo "  fund-mls-contracts-deployer     Fund the EOA that deploys the MLS contracts via a factory (requires MLS_CONTRACTS_DEPLOYER_ADDRESS)"
	@echo "  deploy-den-factory              Deploy the Den Singleton Factory"
	@echo ""
	@echo "Utilities:"
	@echo "  check-factory             Check if a factory is deployed"
	@echo "  check-all-factories       Check all factories on a network"
	@echo "  check-deployment          Check all contracts for a factory are deployed (pretty-printed bytecode check)"
	@echo "  check-all-deployments     Check all contracts for all factories on a network"
	@echo "  compute-addresses         Compute all CREATE2 addresses for a factory"
	@echo "  compute-all-addresses     Compute all CREATE2 addresses for all factories"
	@echo "  verify                    Verify a single contract (CONTRACT_ADDRESS, CONTRACT_NAME; honors VERIFIER, CONSTRUCTOR_ARGS, GUESS_CONSTRUCTOR_ARGS, LIBRARIES)"
	@echo "  verify-all                Verify all platform contracts for a factory/env (uses FACTORY, NETWORK, ENV, VERIFIER)"
	@echo "  find-proxy                Discover a representative proxy instance from creation events (TYPE=org|account, NETWORK)"
	@echo "  verify-proxies            Discover + verify one OrganizationProxy and one AccountProxy instance on a chain (NETWORK, ENV, VERIFIER)"
	@echo ""
	@echo "Configuration Variables:"
	@echo "  NETWORK   Target network: local, mainnet, sepolia, polygon, etc. (default: local)"
	@echo "  SIGNER    Signing method: account or ledger (default: account)"
	@echo "  ACCOUNT   Foundry keystore account name (required for SIGNER=account)"
	@echo "  SENDER    EOA address (auto-derived from ACCOUNT, required for ledger)"
	@echo "  FACTORY   CREATE2 factory: arachnid, den-prod, den-nonprod (default: arachnid)"
	@echo "  HD_PATH   Ledger HD derivation path (default: m/44'/60'/0'/0/0)"
	@echo "  VERBOSITY Forge verbosity level (default: $(VERBOSITY))"
	@echo "  EXECUTOR  Guardian Executor EOA address (for deploy-guardian-safe-module)"
	@echo "  EXECUTE   Execute transaction if threshold met: true or false (for *-module and *-implementations targets)"
	@echo "  ACTION    Action to check status for: add or remove (for check-guardian-module-status)"
	@echo "  ORG_IMPLEMENTATIONS      Organization impls as a forge address[] literal, e.g. '[0xabc,0xdef]' (default [])"
	@echo "  ACCOUNT_IMPLEMENTATIONS  Account impls as a forge address[] literal, e.g. '[0xabc]' (default [])"
	@echo "  IS_WHITELIST   For check-whitelist-status: true (whitelist/add) or false (unwhitelist/remove)"
	@echo "  CONTRACT_TYPE  organization or account (for is-implementation-whitelisted)"
	@echo "  IMPLEMENTATION Implementation address (for is-implementation-whitelisted)"
	@echo "  WHITELIST_ENV  Safe config env to resolve the whitelist proxy: nonprod or prod (default nonprod)"
	@echo "  ENV            For check-deployment/check-all-deployments: which env gates the summary: auto, nonprod, prod, both (default auto, derived from chain id)"
	@echo "  FUND_ENV       For fund-safe-owners: prod or nonprod (default nonprod)"
	@echo "  FUND_AMOUNT    For fund-safe-owners/fund-mls-contracts-deployer: ETH amount to send, e.g. 0.1ether (default $(FUND_AMOUNT))"
	@echo "  DEN_FACTORY_DEPLOYER_ADDRESS    Den factory deployer EOA to fund (for fund-den-factory-deployer)"
	@echo "  MLS_CONTRACTS_DEPLOYER_ADDRESS  EOA that deploys the MLS contracts, to fund (for fund-mls-contracts-deployer)"
	@echo "  VERIFIER       For verify-all: block explorer verifier: etherscan (default), sourcify, blockscout, custom"
	@echo "  VERIFIER_URL   For verify-all: optional --verifier-url (required for sourcify/blockscout/custom)"
	@echo "  ETHERSCAN_API_KEY  For verify/verify-all (one Etherscan V2 key covers ETH/OP/Base/Arb/Sepolia); verify-all also reads it from .env"
	@echo "  VERIFIER_API_KEY   For verify-all on key-gated non-etherscan explorers (oklink/custom); also read from .env (sourcify/blockscout need none)"
	@echo ""
	@echo "Examples:"
	@echo "  make deploy-libraries NETWORK=sepolia ACCOUNT=my-deployer"
	@echo "  make deploy-platform FACTORY=arachnid NETWORK=mainnet SIGNER=ledger SENDER=0x..."
	@echo "  make check-all-factories NETWORK=mainnet"
	@echo "  make check-deployment FACTORY=arachnid NETWORK=mainnet"
	@echo "  make check-all-deployments NETWORK=sepolia"
	@echo "  make fund-safe-owners FUND_ENV=nonprod FUND_AMOUNT=0.1ether NETWORK=sepolia ACCOUNT=my-deployer"
	@echo "  make fund-mls-contracts-deployer MLS_CONTRACTS_DEPLOYER_ADDRESS=0x.. FUND_AMOUNT=1ether NETWORK=sepolia ACCOUNT=my-funder"
	@echo "  make deploy-guardian-safe-module EXECUTOR=0x... NETWORK=sepolia ACCOUNT=my-deployer"
	@echo "  make guardian-safe-add-module EXECUTE=true NETWORK=sepolia ACCOUNT=safe-owner"
	@echo "  make whitelist-implementations ORG_IMPLEMENTATIONS='[0x..]' ACCOUNT_IMPLEMENTATIONS='[0x..]' EXECUTE=true ACCOUNT=admin-safe-owner"
	@echo "  ETHERSCAN_API_KEY=xxx make verify-all FACTORY=arachnid NETWORK=mainnet ENV=prod"

# ==============================================================================
# Core Commands
# ==============================================================================

# "make" (all)
# Cleans artifacts, removes old submodules, installs deps, updates them, and builds
# This guarantees a fresh working state
all: clean remove install update build

# Clean: Removes build artifacts/cache
clean:
	forge clean

# Remove: Removes the `lib` folder (dependencies) to ensure a clean slate
# (Crucial if submodules get out of sync)
remove:
	rm -rf .git/modules/*
	rm -rf lib

# Install: Installs dependencies
install:
	forge install

# Update: Updates dependencies to the commit specified in gitmodules
update:
	forge update

# Build: Compiles the contracts
build:
	forge build

# Test: Runs Foundry tests
test:
	forge test

# Format: Fixes code style
format:
	forge fmt

# Check Headers: Verify SPDX license and copyright headers in all .sol files
check-headers:
	@./script/sh/check-headers.sh

# Lint: Checks code style (no fixes)
lint: check-headers
	forge fmt --check
	forge lint

	# Run solhint linter on our core source contracts
	# This will automatically use our core config, located at `.solhint.json`.
	npx solhint 'src/**/*.sol'

	# Run solhint linter on our scripts
	# Uses script-specific config that disables rules not applicable to scripts
	# (e.g., compiler-version, gas-custom-errors, no-console, ordering)
	npx solhint -c script/.solhint.json 'script/**/*.sol'

# Analyze: Static Analysis (Slither)
analyze:
	slither src/
	slither --config-file slither.script.config.json script/ 

# Sizes: Checks the sizes of the contracts
sizes:
	forge build --sizes src

# Check: The "CI Mode" - Runs everything
# This is what you run before pushing code.
check: format lint analyze sizes test

# Coverage: Generates test coverage report
coverage:
	forge coverage --ir-minimum

# Snapshot: Generates gas snapshot for regression testing
snapshot:
	forge snapshot

# Gas Report: Runs tests with gas reporting
gas-report:
	forge test --gas-report

# ==============================================================================
# Deployment Configuration
# ==============================================================================
#
# All deployment addresses are read from deployment.toml using yq.
# This is the single source of truth for all hardcoded addresses.
#
# Configuration Variables (override via command line):
#   NETWORK  - Target network: local, mainnet, polygon, arbitrum, optimism, base (default: local)
#   SIGNER   - Signing method: account or ledger (default: account)
#   ACCOUNT  - Foundry keystore account name (required when SIGNER=account)
#   SENDER   - EOA address (auto-derived from ACCOUNT, required for ledger)
#   FACTORY  - CREATE2 factory: arachnid, den-prod, den-nonprod (default: arachnid)
#   HD_PATH  - Ledger HD derivation path (default: m/44'/60'/0'/0/0)
#
# Example usage:
#   make deploy-libraries NETWORK=sepolia ACCOUNT=my-deployer
#   make deploy-contracts NETWORK=mainnet SIGNER=ledger SENDER=0x1234...
#   make deploy-platform FACTORY=arachnid NETWORK=local ACCOUNT=test

# ------------------------------------------------------------------------------
# Default Configuration Values
# ------------------------------------------------------------------------------
NETWORK ?= local
SIGNER ?= account
FACTORY ?= arachnid
HD_PATH ?= m/44'/60'/0'/0/0
VERBOSITY ?= -vvvv

# Implementation whitelist arrays (forge address[] literals, e.g. ORG_IMPLEMENTATIONS='[0xabc,0xdef]').
# Default to empty arrays so callers only need to pass the type(s) they want to change.
ORG_IMPLEMENTATIONS ?= []
ACCOUNT_IMPLEMENTATIONS ?= []

# For check-whitelist-status: whether to check a whitelist (add) or unwhitelist (remove) transaction
IS_WHITELIST ?= true

# Environment (Safe config: prod vs nonprod) used to resolve env-dependent addresses in pure-cast
# read targets such as is-implementation-whitelisted. Defaults to nonprod (local/testnet).
# NOTE: deployment scripts derive this from the chain ID; this is only for the cast-based read targets.
WHITELIST_ENV ?= nonprod

# Environment selector for check-deployment / check-all-deployments. Controls which
# environment (prod vs nonprod) is counted toward the pass/fail summary and exit code.
# Both environments are always displayed; only the active one gates the result.
#   auto    - derive from the chain id (mirrors DeploymentConfig._isProductionChain)
#   nonprod - count the nonprod env (treat prod as reference-only)
#   prod    - count the prod env (treat nonprod as reference-only)
#   both    - count both environments
ENV ?= auto

# Environment selector for fund-safe-owners. Must be prod or nonprod. Selects which
# Safe owner set ([safe.prod] vs [safe.nonprod]) to fund.
FUND_ENV ?= nonprod

# Amount of ETH to send each Safe owner in fund-safe-owners (any cast-parseable value,
# e.g. 0.1ether, 1ether, 50000000000000000).
FUND_AMOUNT ?= 0.1ether

# Block explorer verifier for verify-all. etherscan (default) uses the Etherscan V2
# API (one ETHERSCAN_API_KEY covers ETH/OP/Base/Arb/Sepolia). For non-Etherscan
# chains, use VERIFIER=blockscout|sourcify|custom with VERIFIER_URL.
VERIFIER ?= etherscan
VERIFIER_URL ?=

# Proxy instance type for find-proxy (org or account).
TYPE ?= org

# Export verification inputs so the verify/verify-all scripts pick them up when passed
# as make variables. The scripts also read the API keys from the shell env or a .env
# file. ETHERSCAN_API_KEY is used by the etherscan verifier; VERIFIER_API_KEY by
# key-gated non-etherscan verifiers (oklink/custom). CONSTRUCTOR_ARGS / LIBRARIES are
# optional inputs to the single-contract verify.
#
# IMPORTANT: export only when set. A bare `export VAR` for an undefined variable
# exports it as an EMPTY string; forge binds ETHERSCAN_API_KEY/VERIFIER_API_KEY as env
# defaults for its key args, and an empty value breaks verifier resolution
# ("ETHERSCAN_API_KEY must be set ...") even when a real key is passed on the CLI.
# `ifdef` is false for empty/undefined variables, so this never exports an empty value.
ifdef ETHERSCAN_API_KEY
export ETHERSCAN_API_KEY
endif
ifdef VERIFIER_API_KEY
export VERIFIER_API_KEY
endif
ifdef CONSTRUCTOR_ARGS
export CONSTRUCTOR_ARGS
endif
ifdef GUESS_CONSTRUCTOR_ARGS
export GUESS_CONSTRUCTOR_ARGS
endif
ifdef LIBRARIES
export LIBRARIES
endif
# find-proxy tuning knobs (so `make find-proxy CHUNK=... FROM_BLOCK=...` reaches the script).
ifdef ORG
export ORG
endif
ifdef FROM_BLOCK
export FROM_BLOCK
endif
ifdef CHUNK
export CHUNK
endif
ifdef MAX_CHUNKS
export MAX_CHUNKS
endif

# ------------------------------------------------------------------------------
# Validate FACTORY value (must be done before generating variables)
# ------------------------------------------------------------------------------
ifneq ($(FACTORY),arachnid)
ifneq ($(FACTORY),den-prod)
ifneq ($(FACTORY),den-nonprod)
    $(error Invalid FACTORY value '$(FACTORY)'. Use: arachnid, den-prod, or den-nonprod)
endif
endif
endif

# ------------------------------------------------------------------------------
# Generated Deployment Variables (from deployment.toml)
# ------------------------------------------------------------------------------
# This include file is auto-generated from deployment.toml via the shared config library.
# It provides: FACTORY_ADDRESS, library addresses, library paths, and linking flags.
# Regenerates when deployment.toml or config scripts change, or when FACTORY changes.
-include .make-deploy-vars.mk

# Check if the FACTORY in the generated file matches current FACTORY
# If not, we need to regenerate even if file timestamps are current
CURRENT_FACTORY_IN_FILE := $(shell grep -m1 'Factory:' .make-deploy-vars.mk 2>/dev/null | cut -d' ' -f3)
ifneq ($(CURRENT_FACTORY_IN_FILE),$(FACTORY))
    # Force regeneration by making the file depend on a phony target
    .make-deploy-vars.mk: FORCE
endif

# Write to a temp file and rename atomically so an interrupted `make` (e.g. killed
# mid-generation) can never leave a half-written/corrupt include file on disk, which
# would break every subsequent `make` invocation with a parse error.
.make-deploy-vars.mk: deployment.toml script/sh/lib/generate_make_vars.sh script/sh/lib/deployment_config.sh
	@./script/sh/lib/generate_make_vars.sh $(FACTORY) > $@.tmp && mv -f $@.tmp $@

.PHONY: FORCE
FORCE:

# ------------------------------------------------------------------------------
# RPC URL Resolution (based on NETWORK variable)
# ------------------------------------------------------------------------------
ifeq ($(NETWORK),local)
    RPC_URL ?= http://127.0.0.1:8545
else
    # Use foundry.toml [rpc_endpoints] alias
    RPC_URL ?= $(NETWORK)
endif

# ------------------------------------------------------------------------------
# Auto-derive SENDER from ACCOUNT (for Foundry managed accounts)
# If ACCOUNT is provided but SENDER is not, derive it using cast wallet address.
# Uses immediate evaluation (:=) so the shell command only runs once.
# ------------------------------------------------------------------------------
ifdef ACCOUNT
    ifndef SENDER
        SENDER := $(shell \
            echo "" >&2 && \
            echo "========================================" >&2 && \
            echo "Deriving address for account: $(ACCOUNT)" >&2 && \
            echo "Enter your keystore password below." >&2 && \
            echo "(This is for --sender flag, not to broadcast)" >&2 && \
            echo "========================================" >&2 && \
            cast wallet address --account $(ACCOUNT))
    endif
endif

# ------------------------------------------------------------------------------
# Signer Flags (based on SIGNER variable)
# ------------------------------------------------------------------------------
ifeq ($(SIGNER),ledger)
    SIGNER_FLAGS = --ledger --hd-paths "$(HD_PATH)" --sender $(SENDER)
    # cast uses different flag names than forge (--from instead of --sender,
    # --mnemonic-derivation-path instead of --hd-paths).
    CAST_SIGNER_FLAGS = --ledger --mnemonic-derivation-path "$(HD_PATH)" --from $(SENDER)
else ifeq ($(SIGNER),account)
    SIGNER_FLAGS = --account $(ACCOUNT) --sender $(SENDER)
    CAST_SIGNER_FLAGS = --account $(ACCOUNT) --from $(SENDER)
else
    SIGNER_FLAGS = $(error Invalid SIGNER value '$(SIGNER)'. Use: account or ledger)
endif

# Validation target - use as dependency for targets that require signing
validate-signer-vars:
ifeq ($(SIGNER),ledger)
ifndef SENDER
	$(error SENDER is required for Ledger. Set SENDER=<your-address>)
endif
else ifeq ($(SIGNER),account)
ifndef ACCOUNT
	$(error ACCOUNT is required. Set ACCOUNT=<keystore-name>)
endif
ifeq ($(SENDER),)
	$(error Failed to derive SENDER address from ACCOUNT '$(ACCOUNT)'. Does this account exist in your Foundry keystore? Run 'cast wallet list' to see available accounts)
endif
endif

# ==============================================================================
# CREATE2 Factory Deployment Commands
# ==============================================================================

# Fund Arachnid Factory Deployer: Sends ETH to the Arachnid CREATE2 factory deployer EOA
# This is required before deploying the Arachnid factory on a new chain.
#
# Example:
#   make fund-arachnid-factory-deployer NETWORK=sepolia ACCOUNT=my-deployer SENDER=0x1234...
fund-arachnid-factory-deployer: validate-signer-vars
	@echo "Funding Arachnid factory deployer..."
	@echo "  Network: $(NETWORK)"
	@echo "  Target: $(ARACHNID_FACTORY_DEPLOYER_ADDRESS)"
	forge script script/DeployArachnidFactory.s.sol:DeployArachnidFactory \
		--sig "fundDeployer()" \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Deploy Arachnid Factory: Deploys the Arachnid Deterministic Deployment Proxy
# Requires: The deployer address must be funded first (use fund-arachnid-factory-deployer)
#
# Example:
#   make deploy-arachnid-factory NETWORK=sepolia ACCOUNT=my-deployer SENDER=0x1234...
deploy-arachnid-factory: validate-signer-vars
	@echo "Deploying Arachnid CREATE2 factory..."
	@echo "  Network: $(NETWORK)"
	@echo "  Expected address: $(ARACHNID_FACTORY_ADDRESS)"
	CONFIRM_DEPLOYMENT=true forge script script/DeployArachnidFactory.s.sol:DeployArachnidFactory \
		--sig "run()" \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Fund Den Factory Deployer: Sends ETH to the Den Singleton Factory deployer EOA
# The target address depends on whether you're using the prod or non-prod deployer.
# Pass DEN_FACTORY_DEPLOYER_ADDRESS to specify the target.
#
# Example:
#   make fund-den-factory-deployer DEN_FACTORY_DEPLOYER_ADDRESS=0xE1CB04A0fA36DdD16a06ea828007E35e1a3cBC37 NETWORK=sepolia ACCOUNT=my-deployer SENDER=0x1234...
fund-den-factory-deployer: validate-signer-vars
ifndef DEN_FACTORY_DEPLOYER_ADDRESS
	$(error DEN_FACTORY_DEPLOYER_ADDRESS is required. Set DEN_FACTORY_DEPLOYER_ADDRESS=<deployer-address>)
endif
	@echo "Funding Den Singleton Factory deployer..."
	@echo "  Network: $(NETWORK)"
	@echo "  Target: $(DEN_FACTORY_DEPLOYER_ADDRESS)"
	forge script script/DeployDenSingletonFactory.s.sol:DeployDenSingletonFactory \
		--sig "fundDeployer(address)" $(DEN_FACTORY_DEPLOYER_ADDRESS) \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Fund MLS Contracts Deployer: Sends ETH to the EOA that will deploy the MLS platform contracts
# (libraries, implementations, Safe infra, OrganizationFactory, whitelist, BatchedTransaction, module)
# THROUGH an already-deployed CREATE2 factory.
#
# This is distinct from a *factory* deployer (which deploys the CREATE2 factory itself at nonce 0):
# the contracts deployer deploys via the factory, so its nonce does not affect any deterministic
# address. Sends FUND_AMOUNT from SENDER via a cast value transfer.
#
# Example:
#   make fund-mls-contracts-deployer MLS_CONTRACTS_DEPLOYER_ADDRESS=0x1234... FUND_AMOUNT=1ether NETWORK=sepolia ACCOUNT=my-funder
fund-mls-contracts-deployer: validate-signer-vars
ifndef MLS_CONTRACTS_DEPLOYER_ADDRESS
	$(error MLS_CONTRACTS_DEPLOYER_ADDRESS is required. Set MLS_CONTRACTS_DEPLOYER_ADDRESS=<deployer-address>)
endif
	@echo "Funding MLS contracts deployer..."
	@echo "  Network: $(NETWORK)"
	@echo "  Target:  $(MLS_CONTRACTS_DEPLOYER_ADDRESS)"
	@echo "  Amount:  $(FUND_AMOUNT)"
	@echo "  Funder:  $(SENDER)"
	cast send $(MLS_CONTRACTS_DEPLOYER_ADDRESS) --value $(FUND_AMOUNT) --rpc-url $(RPC_URL) $(CAST_SIGNER_FLAGS)

# Deploy Den Factory: Deploys the Den Singleton Factory
# IMPORTANT: Must be run from the correct deployer EOA at nonce 0 for deterministic address.
# The deployer must be funded first (use fund-den-factory-deployer).
#
# Example:
#   make deploy-den-factory NETWORK=sepolia ACCOUNT=den-deployer SENDER=0xE1CB04A0fA36DdD16a06ea828007E35e1a3cBC37
deploy-den-factory: validate-signer-vars
	@echo "Deploying Den Singleton Factory..."
	@echo "  Network: $(NETWORK)"
	@echo "  Deployer: $(SENDER)"
	CONFIRM_DEPLOYMENT=true forge script script/DeployDenSingletonFactory.s.sol:DeployDenSingletonFactory \
		--sig "run()" \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# ==============================================================================
# Safe 1.4.1 Deployment Commands
# ==============================================================================
#
# Safe 1.4.1 deployment is split into two steps for security:
# 1. deploy-safe-infra: Deploys infrastructure (singleton, proxy factory, handlers)
# 2. deploy-safe-multisigs: Deploys Guardian and Admin Safes (verifies infra first)
#
# This two-step process prevents deploying Safe proxies without the Singleton,
# which could allow attackers to front-run initialization.
#
# Uses Solidity 0.7.6 via FOUNDRY_PROFILE=safe for deterministic addresses.
#
# IMPORTANT: Safe deployment only needs to be done ONCE per chain per factory.
# After deployment, update addresses in deployment.toml.

# Deploy Safe Infrastructure: Deploys Safe 1.4.1 infrastructure contracts
# IMPORTANT: This uses FOUNDRY_PROFILE=safe which compiles with Solidity 0.7.6.
# Run this BEFORE deploy-safe-multisigs.
#
# Example:
#   make deploy-safe-infra NETWORK=sepolia ACCOUNT=my-deployer
#   make deploy-safe-infra FACTORY=den-nonprod NETWORK=mainnet SIGNER=ledger SENDER=0x1234...
deploy-safe-infra: validate-signer-vars
	@echo "Deploying Safe 1.4.1 infrastructure..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	@echo "  Profile: safe (Solidity 0.7.6)"
	FOUNDRY_PROFILE=safe forge script script/safe/DeploySafeInfrastructure.s.sol:DeploySafeInfrastructure \
		--sig "run(address)" $(FACTORY_ADDRESS) \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Deploy Safe Infrastructure Dry-Run: Simulates Safe infrastructure deployment without broadcasting
#
# Example:
#   make deploy-safe-infra-dry-run NETWORK=sepolia
deploy-safe-infra-dry-run:
	@echo "Simulating Safe 1.4.1 infrastructure deployment (dry-run)..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	@echo "  Profile: safe (Solidity 0.7.6)"
	FOUNDRY_PROFILE=safe forge script script/safe/DeploySafeInfrastructure.s.sol:DeploySafeInfrastructure \
		--sig "run(address)" $(FACTORY_ADDRESS) \
		--rpc-url $(RPC_URL) \
		$(VERBOSITY)

# Deploy Safe Multisigs: Deploys Guardian and Admin Safe multisig wallets
# IMPORTANT: Safe infrastructure must be deployed first (use deploy-safe-infra).
# This script verifies that the Safe Singleton is deployed before proceeding.
#
# Example:
#   make deploy-safe-multisigs NETWORK=sepolia ACCOUNT=my-deployer
#   make deploy-safe-multisigs FACTORY=den-nonprod NETWORK=mainnet SIGNER=ledger SENDER=0x1234...
deploy-safe-multisigs: validate-signer-vars
	@echo "Deploying Safe multisigs (Guardian and Admin Safes)..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	@echo "  Profile: safe (Solidity 0.7.6)"
	FOUNDRY_PROFILE=safe forge script script/safe/DeploySafeMultisigs.s.sol:DeploySafeMultisigs \
		--sig "run(address)" $(FACTORY_ADDRESS) \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Deploy Safe Multisigs Dry-Run: Simulates Safe multisig deployment without broadcasting
#
# Example:
#   make deploy-safe-multisigs-dry-run NETWORK=sepolia
deploy-safe-multisigs-dry-run:
	@echo "Simulating Safe multisig deployment (dry-run)..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	@echo "  Profile: safe (Solidity 0.7.6)"
	FOUNDRY_PROFILE=safe forge script script/safe/DeploySafeMultisigs.s.sol:DeploySafeMultisigs \
		--sig "run(address)" $(FACTORY_ADDRESS) \
		--rpc-url $(RPC_URL) \
		$(VERBOSITY)

# Fund Safe Owners: Sends ETH to every Safe owner (Guardian + Admin) for the selected
# environment ([safe.prod] or [safe.nonprod] in deployment.toml), so the owners can pay gas
# for their Safe transactions (e.g. whitelisting implementations, adding the Guardian module).
# Funds whichever owner_1/2/3 keys are present (1 each for nonprod, 3 each for prod).
#
# FUND_ENV selects the owner set (prod or nonprod); FUND_AMOUNT is the ETH sent to each owner.
# Uses `cast send` value transfers from SENDER.
#
# Example:
#   make fund-safe-owners FUND_ENV=nonprod NETWORK=sepolia ACCOUNT=my-deployer
#   make fund-safe-owners FUND_ENV=prod FUND_AMOUNT=0.25ether NETWORK=mainnet SIGNER=ledger SENDER=0x...
fund-safe-owners: validate-signer-vars
	@case "$(FUND_ENV)" in \
		prod|nonprod) ;; \
		*) echo "Error: FUND_ENV must be 'prod' or 'nonprod' (got '$(FUND_ENV)')"; exit 1 ;; \
	esac; \
	echo "Funding $(FUND_ENV) Safe owners ($(FUND_AMOUNT) each) from $(SENDER) on $(NETWORK)..."; \
	funded=0; \
	for key in guardian_safe_owner_1 guardian_safe_owner_2 guardian_safe_owner_3 \
	           admin_safe_owner_1 admin_safe_owner_2 admin_safe_owner_3; do \
		owner=$$(yq -r ".safe.$(FUND_ENV).$$key" deployment.toml 2>/dev/null); \
		if [ -z "$$owner" ] || [ "$$owner" = "null" ]; then continue; fi; \
		printf '  %-22s %s ... ' "$$key" "$$owner"; \
		if cast send "$$owner" --value $(FUND_AMOUNT) --rpc-url $(RPC_URL) $(CAST_SIGNER_FLAGS) >/dev/null 2>&1; then \
			echo "funded"; \
		else \
			echo "FAILED"; \
			echo "  ERROR: cast send failed funding $$key ($$owner)"; exit 1; \
		fi; \
		funded=$$((funded + 1)); \
	done; \
	if [ "$$funded" -eq 0 ]; then \
		echo "Error: no Safe owners found for env '$(FUND_ENV)' in deployment.toml"; exit 1; \
	fi; \
	echo "Funded $$funded $(FUND_ENV) Safe owner(s)."

# ==============================================================================
# BatchedTransaction Deployment Commands
# ==============================================================================
#
# BatchedTransaction is a security-focused batched transaction contract that must be
# deployed BEFORE SafeExecutorModules. It provides:
# - No ETH transfers (value hardcoded to 0)
# - msg.sender validation (blocks calls to Safe when delegatecalled)
# - Efficient transaction encoding

# Deploy BatchedTransaction: Deploys the BatchedTransaction contract via CREATE2
# IMPORTANT: Must be deployed BEFORE deploying SafeExecutorModules.
#
# Example:
#   make deploy-batched-transaction NETWORK=sepolia ACCOUNT=my-deployer
#   make deploy-batched-transaction FACTORY=den-nonprod NETWORK=mainnet SIGNER=ledger SENDER=0x...
deploy-batched-transaction: validate-signer-vars
	@echo "Deploying BatchedTransaction..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	forge script script/safe-module/DeployBatchedTransaction.s.sol:DeployBatchedTransaction \
		--sig "run(address)" $(FACTORY_ADDRESS) \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# ==============================================================================
# Guardian Safe Executor Module Commands
# ==============================================================================
#
# The SafeExecutorModule allows a designated EOA (the "Guardian Executor EOA") to execute
# contract calls on behalf of the Guardian Safe multisig. These commands handle deployment
# and Guardian Safe owner operations for adding/removing the module.
#
# IMPORTANT: BatchedTransaction must be deployed BEFORE deploying the Guardian SafeExecutorModule.
# After module deployment, Guardian Safe owners must approve adding the module via guardian-safe-add-module.

# Deploy Guardian Safe Module: Deploys the SafeExecutorModule for the Guardian Safe via CREATE2
# The Guardian Safe must be deployed first. The Guardian Executor EOA address is validated against deployment.toml.
#
# Example:
#   make deploy-guardian-safe-module EXECUTOR=0x1234... NETWORK=sepolia ACCOUNT=my-deployer
#   make deploy-guardian-safe-module EXECUTOR=0x5678... FACTORY=den-nonprod NETWORK=mainnet SIGNER=ledger SENDER=0x...
deploy-guardian-safe-module: validate-signer-vars
ifndef EXECUTOR
	$(error EXECUTOR is required. Set EXECUTOR=<guardian-executor-eoa-address>)
endif
	@echo "Deploying Guardian SafeExecutorModule..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	@echo "  Guardian Executor EOA: $(EXECUTOR)"
	forge script script/safe-module/DeployGuardianSafeModule.s.sol:DeployGuardianSafeModule \
		--sig "run(address,address)" $(FACTORY_ADDRESS) $(EXECUTOR) \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Add Module to Guardian Safe: Approve adding the module to Guardian Safe (owner operation)
# Each Guardian Safe owner runs this command to approve. When threshold is met and EXECUTE=true,
# the transaction is automatically executed.
#
# Example:
#   make guardian-safe-add-module EXECUTE=true NETWORK=sepolia ACCOUNT=safe-owner
#   make guardian-safe-add-module EXECUTE=false FACTORY=den-nonprod NETWORK=mainnet SIGNER=ledger SENDER=0x...
guardian-safe-add-module: validate-signer-vars
ifndef EXECUTE
	$(error EXECUTE is required. Set EXECUTE=true or EXECUTE=false)
endif
	@echo "Adding module to Guardian Safe (approve transaction)..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	@echo "  Execute if ready: $(EXECUTE)"
	forge script script/safe-module/ManageGuardianSafeModule.s.sol:ManageGuardianSafeModule \
		--sig "addModule(address,bool)" $(FACTORY_ADDRESS) $(EXECUTE) \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Remove Module from Guardian Safe: Approve removing the module from Guardian Safe (owner operation)
# Each Guardian Safe owner runs this command to approve. When threshold is met and EXECUTE=true,
# the transaction is automatically executed.
#
# Example:
#   make guardian-safe-remove-module EXECUTE=true NETWORK=sepolia ACCOUNT=safe-owner
#   make guardian-safe-remove-module EXECUTE=false FACTORY=den-nonprod NETWORK=mainnet SIGNER=ledger SENDER=0x...
guardian-safe-remove-module: validate-signer-vars
ifndef EXECUTE
	$(error EXECUTE is required. Set EXECUTE=true or EXECUTE=false)
endif
	@echo "Removing module from Guardian Safe (approve transaction)..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	@echo "  Execute if ready: $(EXECUTE)"
	forge script script/safe-module/ManageGuardianSafeModule.s.sol:ManageGuardianSafeModule \
		--sig "removeModule(address,bool)" $(FACTORY_ADDRESS) $(EXECUTE) \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Check Guardian Module Status: Check approval status for a Guardian Safe module transaction
# Shows how many approvals exist and who has approved.
#
# Example:
#   make check-guardian-module-status ACTION=add NETWORK=sepolia
#   make check-guardian-module-status ACTION=remove FACTORY=den-nonprod NETWORK=mainnet
check-guardian-module-status:
ifndef ACTION
	$(error ACTION is required. Set ACTION=add or ACTION=remove)
endif
	@echo "Checking Guardian Safe module transaction status..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	@echo "  Action: $(ACTION)"
	forge script script/safe-module/ManageGuardianSafeModule.s.sol:ManageGuardianSafeModule \
		--sig "checkStatus(address,string)" $(FACTORY_ADDRESS) $(ACTION) \
		--rpc-url $(RPC_URL)

# ==============================================================================
# Platform Deployment Commands
# ==============================================================================

# Deploy Independent Libraries: Deploys Policy, Admin, Members, Groups, TxRecovery, GuardianRecovery via CREATE2
# These libraries have no dependencies on other platform libraries.
# Run this BEFORE deploy-dependent-libs.
#
# Example:
#   make deploy-independent-libs NETWORK=sepolia ACCOUNT=my-deployer SENDER=0x1234...
#   make deploy-independent-libs FACTORY=den-prod NETWORK=mainnet SIGNER=ledger SENDER=0x1234...
deploy-independent-libs: validate-signer-vars
	@echo "Deploying independent platform libraries via CREATE2..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	forge script script/DeployLibraries.s.sol:DeployLibraries \
		--sig "runDeployIndependentLibs(address)" $(FACTORY_ADDRESS) \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Deploy Dependent Libraries: Deploys Init and AccountSig libraries via CREATE2
# These libraries depend on Stage 1 libraries being deployed and linked.
# IMPORTANT: Run deploy-independent-libs first. Uses --libraries flags.
#
# Example:
#   make deploy-dependent-libs NETWORK=sepolia ACCOUNT=my-deployer SENDER=0x1234...
#   make deploy-dependent-libs FACTORY=den-prod NETWORK=mainnet SIGNER=ledger SENDER=0x1234...
deploy-dependent-libs: validate-signer-vars
	@echo "Deploying dependent platform libraries (Init, AccountSig) via CREATE2..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	@echo "  Linked Policy: $(LIB_ORG_POLICY_ADDRESS)"
	@echo "  Linked Admin: $(LIB_ORG_ADMIN_ADDRESS)"
	@echo "  Linked Members: $(LIB_ORG_MEMBERS_ADDRESS)"
	@echo "  Linked Groups: $(LIB_ORG_GROUPS_ADDRESS)"
	@echo "  Linked TxRecovery: $(LIB_ORG_TX_RECOVERY_ADDRESS)"
	@echo "  Linked GuardianRecovery: $(LIB_ORG_GUARDIAN_RECOVERY_ADDRESS)"
	forge script script/DeployLibraries.s.sol:DeployLibraries \
		--sig "runDeployDependentLibs(address)" $(FACTORY_ADDRESS) \
		$(INDEPENDENT_LIBRARIES_FLAGS) \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Deploy Libraries: Convenience target that deploys all platform libraries (both stages)
# This runs deploy-independent-libs followed by deploy-dependent-libs.
#
# Example:
#   make deploy-libraries NETWORK=sepolia ACCOUNT=my-deployer SENDER=0x1234...
#   make deploy-libraries FACTORY=den-prod NETWORK=mainnet SIGNER=ledger SENDER=0x1234...
deploy-libraries: deploy-independent-libs deploy-dependent-libs
	@echo "All platform libraries deployed!"
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY)"

# Deploy Contracts: Deploys all platform contracts with library linking
# IMPORTANT: Libraries must be deployed first (use deploy-libraries).
# Uses --libraries flags with addresses from deployment.toml.
#
# Example:
#   make deploy-contracts NETWORK=sepolia ACCOUNT=my-deployer SENDER=0x1234...
#   make deploy-contracts FACTORY=den-prod NETWORK=mainnet SIGNER=ledger SENDER=0x1234...
deploy-contracts: validate-signer-vars
	@echo "Deploying platform contracts with library linking..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	@echo "  Libraries: from deployment.toml"
	forge script script/DeployContracts.s.sol:DeployContracts \
		--sig "run(address)" $(FACTORY_ADDRESS) \
		$(ALL_LIBRARIES_FLAGS) \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Deploy Platform: Full deployment of Safe, libraries, and contracts
# This is a convenience target that runs deploy-safe-infra, deploy-safe-multisigs, deploy-libraries, then deploy-contracts.
# Safe deployment is idempotent (skips already deployed contracts).
#
# NOTE: deploy-contracts deploys the ImplementationWhitelist (impl + proxy) but does NOT whitelist any
# implementations. After deployment, Admin Safe owners must whitelist the Organization and Account
# implementations via `make whitelist-implementations` (an owner multisig operation).
#
# Example:
#   make deploy-platform NETWORK=sepolia ACCOUNT=my-deployer SENDER=0x1234...
#   make deploy-platform FACTORY=arachnid NETWORK=mainnet SIGNER=ledger SENDER=0x1234...
deploy-platform: deploy-safe-infra deploy-safe-multisigs deploy-libraries deploy-contracts
	@echo "Platform deployment complete!"
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY)"

# ------------------------------------------------------------------------------
# Dry-Run (Simulation) Targets
# These run without --broadcast to simulate deployment without sending transactions.
# ------------------------------------------------------------------------------

# Deploy Independent Libraries Dry-Run: Simulates independent library deployment
#
# Example:
#   make deploy-independent-libs-dry-run NETWORK=sepolia
deploy-independent-libs-dry-run:
	@echo "Simulating independent library deployment (dry-run)..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	forge script script/DeployLibraries.s.sol:DeployLibraries \
		--sig "runDeployIndependentLibs(address)" $(FACTORY_ADDRESS) \
		--rpc-url $(RPC_URL) \
		$(VERBOSITY)

# Deploy Dependent Libraries Dry-Run: Simulates dependent library deployment
#
# Example:
#   make deploy-dependent-libs-dry-run NETWORK=sepolia
deploy-dependent-libs-dry-run:
	@echo "Simulating dependent library deployment (dry-run)..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	@echo "  Linked Policy: $(LIB_ORG_POLICY_ADDRESS)"
	@echo "  Linked Admin: $(LIB_ORG_ADMIN_ADDRESS)"
	@echo "  Linked Members: $(LIB_ORG_MEMBERS_ADDRESS)"
	@echo "  Linked Groups: $(LIB_ORG_GROUPS_ADDRESS)"
	@echo "  Linked TxRecovery: $(LIB_ORG_TX_RECOVERY_ADDRESS)"
	@echo "  Linked GuardianRecovery: $(LIB_ORG_GUARDIAN_RECOVERY_ADDRESS)"
	forge script script/DeployLibraries.s.sol:DeployLibraries \
		--sig "runDeployDependentLibs(address)" $(FACTORY_ADDRESS) \
		$(INDEPENDENT_LIBRARIES_FLAGS) \
		--rpc-url $(RPC_URL) \
		$(VERBOSITY)

# Deploy Libraries Dry-Run: Simulates all library deployment (both stages)
#
# Example:
#   make deploy-libraries-dry-run NETWORK=sepolia
deploy-libraries-dry-run: deploy-independent-libs-dry-run deploy-dependent-libs-dry-run
	@echo "All library deployment simulations complete!"
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY)"

# Deploy Contracts Dry-Run: Simulates contract deployment
#
# Example:
#   make deploy-contracts-dry-run NETWORK=sepolia
deploy-contracts-dry-run:
	@echo "Simulating contract deployment (dry-run)..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	@echo "  Libraries: from deployment.toml"
	forge script script/DeployContracts.s.sol:DeployContracts \
		--sig "run(address)" $(FACTORY_ADDRESS) \
		$(ALL_LIBRARIES_FLAGS) \
		--rpc-url $(RPC_URL) \
		$(VERBOSITY)

# Deploy Platform Dry-Run: Simulates full platform deployment
#
# Example:
#   make deploy-platform-dry-run NETWORK=sepolia
deploy-platform-dry-run: deploy-libraries-dry-run deploy-contracts-dry-run
	@echo "Platform deployment simulation complete!"
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY)"

# ==============================================================================
# Implementation Whitelist Commands
# ==============================================================================
#
# The ImplementationWhitelist (implementation + proxy) is deployed by deploy-contracts. The proxy is
# deployed with NO whitelisted implementations and is owned by the Admin Safe. Whitelisting the
# Organization and Account implementations (and any future upgrade targets) is done afterward via
# Admin Safe transactions.
#
# IMPORTANT: The whitelist proxy's address depends on the Admin Safe (its owner) but NOT on which
# implementations are whitelisted, so whitelisting never changes the proxy address.

# Whitelist Implementations: Approve whitelisting one or more implementations (Admin Safe owner operation)
# Pass Organization and/or Account implementations as forge address[] literals. At least one must be
# non-empty. When both are provided, they are batched into a single atomic Admin Safe transaction.
# Each Admin Safe owner runs this command to approve. When threshold is met and EXECUTE=true,
# the transaction is automatically executed.
#
# Example:
#   make whitelist-implementations ORG_IMPLEMENTATIONS='[0xabc]' ACCOUNT_IMPLEMENTATIONS='[0xdef]' EXECUTE=true NETWORK=sepolia ACCOUNT=admin-safe-owner
#   make whitelist-implementations ORG_IMPLEMENTATIONS='[0xabc,0x123]' EXECUTE=false FACTORY=den-nonprod NETWORK=mainnet SIGNER=ledger SENDER=0x...
whitelist-implementations: validate-signer-vars
ifndef EXECUTE
	$(error EXECUTE is required. Set EXECUTE=true or EXECUTE=false)
endif
	@echo "Whitelisting implementations (approve transaction)..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	@echo "  Organization implementations: $(ORG_IMPLEMENTATIONS)"
	@echo "  Account implementations: $(ACCOUNT_IMPLEMENTATIONS)"
	@echo "  Execute if ready: $(EXECUTE)"
	forge script script/ManageImplementationWhitelist.s.sol:ManageImplementationWhitelist \
		--sig "whitelistImplementations(address,address[],address[],bool)" $(FACTORY_ADDRESS) "$(ORG_IMPLEMENTATIONS)" "$(ACCOUNT_IMPLEMENTATIONS)" $(EXECUTE) \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Unwhitelist Implementations: Approve removing one or more implementations from the whitelist (owner operation)
# Same array shape as whitelist-implementations. When both types are provided, they are batched atomically.
# Each Admin Safe owner runs this command to approve. When threshold is met and EXECUTE=true,
# the transaction is automatically executed.
#
# Example:
#   make unwhitelist-implementations ORG_IMPLEMENTATIONS='[0xabc]' ACCOUNT_IMPLEMENTATIONS='[0xdef]' EXECUTE=true NETWORK=sepolia ACCOUNT=admin-safe-owner
unwhitelist-implementations: validate-signer-vars
ifndef EXECUTE
	$(error EXECUTE is required. Set EXECUTE=true or EXECUTE=false)
endif
	@echo "Unwhitelisting implementations (approve transaction)..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	@echo "  Organization implementations: $(ORG_IMPLEMENTATIONS)"
	@echo "  Account implementations: $(ACCOUNT_IMPLEMENTATIONS)"
	@echo "  Execute if ready: $(EXECUTE)"
	forge script script/ManageImplementationWhitelist.s.sol:ManageImplementationWhitelist \
		--sig "unwhitelistImplementations(address,address[],address[],bool)" $(FACTORY_ADDRESS) "$(ORG_IMPLEMENTATIONS)" "$(ACCOUNT_IMPLEMENTATIONS)" $(EXECUTE) \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Check Whitelist Status: Check approval status for an implementation whitelist transaction
# Shows how many approvals exist and who has approved. Use the SAME arrays you passed (or will pass)
# to whitelist-implementations / unwhitelist-implementations, and set IS_WHITELIST to match.
#
# Example:
#   make check-whitelist-status ORG_IMPLEMENTATIONS='[0xabc]' ACCOUNT_IMPLEMENTATIONS='[0xdef]' IS_WHITELIST=true NETWORK=sepolia
#   make check-whitelist-status ORG_IMPLEMENTATIONS='[0xabc]' IS_WHITELIST=false FACTORY=den-nonprod NETWORK=mainnet
check-whitelist-status:
	@echo "Checking implementation whitelist transaction status..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	@echo "  Organization implementations: $(ORG_IMPLEMENTATIONS)"
	@echo "  Account implementations: $(ACCOUNT_IMPLEMENTATIONS)"
	@echo "  Is whitelist (add): $(IS_WHITELIST)"
	forge script script/ManageImplementationWhitelist.s.sol:ManageImplementationWhitelist \
		--sig "checkStatus(address,address[],address[],bool)" $(FACTORY_ADDRESS) "$(ORG_IMPLEMENTATIONS)" "$(ACCOUNT_IMPLEMENTATIONS)" $(IS_WHITELIST) \
		--rpc-url $(RPC_URL)

# Is Implementation Whitelisted: Read-only check of whether a single implementation is currently
# whitelisted (queries the deployed ImplementationWhitelist proxy via cast). Prints WHITELISTED or
# NOT WHITELISTED and exits non-zero when it is NOT whitelisted, so it can gate scripts/CI.
#
# Resolves the whitelist proxy from deployment.toml using FACTORY + WHITELIST_ENV (default nonprod).
# Set WHITELIST_ENV=prod when querying a production-chain deployment.
#
# Example:
#   make is-implementation-whitelisted CONTRACT_TYPE=organization IMPLEMENTATION=0xabc NETWORK=sepolia
#   make is-implementation-whitelisted CONTRACT_TYPE=account IMPLEMENTATION=0xdef FACTORY=den-nonprod WHITELIST_ENV=prod NETWORK=mainnet
is-implementation-whitelisted:
ifndef CONTRACT_TYPE
	$(error CONTRACT_TYPE is required. Set CONTRACT_TYPE=organization or CONTRACT_TYPE=account)
endif
ifndef IMPLEMENTATION
	$(error IMPLEMENTATION is required. Set IMPLEMENTATION=<implementation-address>)
endif
	@whitelist_proxy=$$(yq -r '.factory["$(FACTORY)"].env.$(WHITELIST_ENV).whitelist_proxy' deployment.toml); \
	if [ -z "$$whitelist_proxy" ] || [ "$$whitelist_proxy" = "null" ]; then \
		echo "Error: whitelist_proxy not found in deployment.toml for factory '$(FACTORY)' env '$(WHITELIST_ENV)'"; exit 1; \
	fi; \
	case "$(CONTRACT_TYPE)" in \
		organization) type_id=1 ;; \
		account) type_id=0 ;; \
		*) echo "Error: CONTRACT_TYPE must be 'organization' or 'account' (got '$(CONTRACT_TYPE)')"; exit 1 ;; \
	esac; \
	echo "Checking whitelist status..."; \
	echo "  Network: $(NETWORK)"; \
	echo "  Factory: $(FACTORY) (env: $(WHITELIST_ENV))"; \
	echo "  ImplementationWhitelist: $$whitelist_proxy"; \
	echo "  Contract type: $(CONTRACT_TYPE) (enum $$type_id)"; \
	echo "  Implementation: $(IMPLEMENTATION)"; \
	result=$$(env -u ETH_PASSWORD -u ETH_KEYSTORE -u ETH_KEYSTORE_ACCOUNT \
		cast call $$whitelist_proxy "isImplementationWhitelisted(uint8,address)(bool)" $$type_id $(IMPLEMENTATION) --rpc-url $(RPC_URL)) || { \
		echo "  ERROR: cast call failed (is the whitelist proxy deployed at $$whitelist_proxy on $(NETWORK)?)"; exit 1; \
	}; \
	if [ "$$result" = "true" ]; then \
		echo "  WHITELISTED"; \
	else \
		echo "  NOT WHITELISTED (cast returned: $$result)"; \
		exit 1; \
	fi

# ==============================================================================
# Deployment Utility Commands
# ==============================================================================

# Check Factory: Verifies if a specific CREATE2 factory is deployed on the target network
# Uses the FACTORY variable to select which factory to check.
#
# Example:
#   make check-factory FACTORY=arachnid NETWORK=sepolia
#   make check-factory FACTORY=den-prod NETWORK=mainnet
check-factory:
	@echo "$(FACTORY) Factory ($(FACTORY_ADDRESS)):"
	@code=$$(cast code $(FACTORY_ADDRESS) --rpc-url $(RPC_URL) 2>/dev/null) && \
		if [ "$$code" != "0x" ] && [ -n "$$code" ]; then \
			echo "  DEPLOYED"; \
		else \
			echo "  NOT DEPLOYED"; \
		fi || echo "  ERROR: Could not check"

# Check All Factories: Verifies if all CREATE2 factories are deployed on the target network
#
# Example:
#   make check-all-factories NETWORK=sepolia
#   make check-all-factories NETWORK=mainnet
check-all-factories:
	@echo "Checking for CREATE2 factories on $(NETWORK)..."
	@echo ""
	@$(MAKE) --no-print-directory check-factory FACTORY=arachnid NETWORK=$(NETWORK)
	@echo ""
	@$(MAKE) --no-print-directory check-factory FACTORY=den-prod NETWORK=$(NETWORK)
	@echo ""
	@$(MAKE) --no-print-directory check-factory FACTORY=den-nonprod NETWORK=$(NETWORK)

# Check Deployment: Verifies that every platform contract (and the factory) for a
# factory is deployed on the target network via a simple bytecode-nonzero check.
# Pretty-prints all expected addresses (from deployment.toml) grouped by section and
# by environment (nonprod/prod). The active environment is derived from the chain id
# (override with ENV=nonprod|prod|both). Exits non-zero if any active-scope contract
# is missing, so it can gate scripts/CI. Safe to run before, during, and after deploys.
#
# Example:
#   make check-deployment FACTORY=arachnid NETWORK=mainnet
#   make check-deployment FACTORY=den-nonprod NETWORK=sepolia
#   make check-deployment FACTORY=arachnid NETWORK=local ENV=nonprod
check-deployment:
	@./script/sh/check_deployment_status.sh $(FACTORY) "$(RPC_URL)" "$(NETWORK)" "$(ENV)"

# Check All Deployments: Runs check-deployment for all three factories on a network.
# Continues even if a factory is incomplete; exits non-zero if any factory has missing
# contracts in its active scope.
#
# Example:
#   make check-all-deployments NETWORK=sepolia
#   make check-all-deployments NETWORK=mainnet
check-all-deployments:
	@echo "Checking deployment status for all factories on $(NETWORK)..."
	@overall=0; \
	for f in arachnid den-nonprod den-prod; do \
		./script/sh/check_deployment_status.sh $$f "$(RPC_URL)" "$(NETWORK)" "$(ENV)" || overall=1; \
		echo ""; \
	done; \
	exit $$overall

# Compute Addresses: Computes all CREATE2 addresses for a specific factory
# This runs the compute_all_addresses.sh script which orchestrates calls to all
# deployment scripts' computeAddresses() functions and handles library linking correctly.
#
# Example:
#   make compute-addresses FACTORY=arachnid
#   make compute-addresses FACTORY=den-nonprod
#   make compute-addresses FACTORY=den-prod
compute-addresses:
	@./script/sh/compute_all_addresses.sh $(FACTORY)

# Compute All Addresses: Computes all CREATE2 addresses for all three factories
# Continues even if a factory computation fails.
#
# Example:
#   make compute-all-addresses
compute-all-addresses:
	@echo "Computing all addresses for all factories..."
	@echo ""
	-@./script/sh/compute_all_addresses.sh arachnid
	@echo ""
	-@./script/sh/compute_all_addresses.sh den-nonprod
	@echo ""
	-@./script/sh/compute_all_addresses.sh den-prod

# Verify: Verifies a single deployed contract on a block explorer.
# Requires CONTRACT_ADDRESS and CONTRACT_NAME variables.
#
# Uses the same verifier/API-key handling as verify-all (shared lib/verifier.sh):
# VERIFIER (default etherscan), VERIFIER_URL, and ETHERSCAN_API_KEY / VERIFIER_API_KEY
# from the shell environment, a make variable, or a .env file. NETWORK is the --chain
# value. For contracts with constructor args or linked libraries, pass CONSTRUCTOR_ARGS
# (ABI-encoded hex) and/or LIBRARIES (raw forge --libraries flags). DRY_RUN=1 prints only.
#
# GUESS_CONSTRUCTOR_ARGS=1 extracts args from the on-chain creation tx (uses an RPC) —
# only works for contracts created by a top-level tx (EOA-deployed), NOT for factory-created
# contracts. To verify the factory-deployed proxies (OrganizationProxy / AccountProxy), use
# `make verify-proxies` (it computes the constructor args), or pass CONSTRUCTOR_ARGS yourself.
#
# Examples:
#   ETHERSCAN_API_KEY=xxx make verify CONTRACT_ADDRESS=0x1234... CONTRACT_NAME=src/account/AccountImplementation.sol:AccountImplementation NETWORK=mainnet
#   make verify CONTRACT_ADDRESS=0xabc... CONTRACT_NAME=src/safe-module/BatchedTransaction.sol:BatchedTransaction NETWORK=<network> VERIFIER=blockscout
#   # OrganizationProxy by hand (arg = the whitelist proxy address):
#   make verify CONTRACT_ADDRESS=<org-instance> CONTRACT_NAME=src/organization/OrganizationProxy.sol:OrganizationProxy NETWORK=mainnet CONSTRUCTOR_ARGS=$$(cast abi-encode "c(address)" <whitelist_proxy>)
verify:
ifndef CONTRACT_ADDRESS
	$(error CONTRACT_ADDRESS is required. Set CONTRACT_ADDRESS=<deployed-contract-address>)
endif
ifndef CONTRACT_NAME
	$(error CONTRACT_NAME is required. Set CONTRACT_NAME=<contract-name-or-path>)
endif
	@./script/sh/verify_contract.sh "$(CONTRACT_ADDRESS)" "$(CONTRACT_NAME)" "$(NETWORK)" "$(VERIFIER)" "$(VERIFIER_URL)"

# Verify All: Verifies every platform contract for a factory/env on a block explorer.
# Reads addresses, library link addresses, and constructor-arg inputs from
# deployment.toml and runs `forge verify-contract` for each (libraries linked and
# constructor args ABI-encoded automatically). Unlike `verify`, this does NOT require
# CONTRACT_ADDRESS/CONTRACT_NAME and handles the library-linked and constructor-arg
# contracts that `verify` cannot.
#
# It recompiles from source. You MUST run it
# from the exact commit that was deployed so the recompiled bytecode matches on-chain.
# Tip: run `make check-deployment` first to confirm parity.
#
# Set ETHERSCAN_API_KEY (one Etherscan V2 key covers ETH/OP/Base/Arb/Sepolia). It can
# be exported in your shell or placed in a .env file at the repo root (the shell value
# wins). For a Blockscout explorer, just VERIFIER=blockscout (no key needed) — the
# verifier URL is auto-derived from the explorer origin in explorers.toml as
# "<origin>/api/" (pass VERIFIER_URL only to override). For other non-Etherscan chains,
# pass VERIFIER=blockscout|sourcify|oklink|custom (with VERIFIER_URL for sourcify/custom),
# and VERIFIER_API_KEY for the ones that require a key (oklink/custom/key-gated explorers).
#
# Variables: FACTORY (default arachnid), NETWORK (the --chain value), ENV (auto|prod|nonprod),
#            VERIFIER (default etherscan), VERIFIER_URL (optional). DRY_RUN=1 prints commands only.
# Keys: ETHERSCAN_API_KEY / VERIFIER_API_KEY (shell env, make var, or .env).
#
# Examples:
#   ETHERSCAN_API_KEY=xxx make verify-all FACTORY=arachnid NETWORK=mainnet ENV=prod
#   ETHERSCAN_API_KEY=xxx make verify-all FACTORY=arachnid NETWORK=base
#   make verify-all FACTORY=arachnid NETWORK=<network> ENV=prod VERIFIER=blockscout
#   VERIFIER_API_KEY=xxx make verify-all FACTORY=arachnid NETWORK=<id> ENV=prod VERIFIER=oklink VERIFIER_URL=<url>
verify-all:
	@./script/sh/verify_contracts.sh $(FACTORY) "$(NETWORK)" "$(ENV)" "$(VERIFIER)" "$(VERIFIER_URL)"

# Find Proxy: Discovers a representative factory-deployed proxy instance
# (OrganizationProxy or AccountProxy) from its on-chain creation event, so you can verify
# it without hunting for an address. Needs a working RPC for NETWORK (resolved via
# foundry.toml [rpc_endpoints]). Prints the address and a ready `make verify` command.
#
# Variables: TYPE (org|account, default org), NETWORK, ENV (auto|prod|nonprod), FACTORY.
# Tuning env: FROM_BLOCK, CHUNK, MAX_CHUNKS, ORG (restrict account lookup to one org).
#
# Examples:
#   make find-proxy TYPE=org NETWORK=mainnet ENV=prod
#   make find-proxy TYPE=account NETWORK=ronin
find-proxy:
	@./script/sh/find_proxy_instance.sh "$(TYPE)" "$(NETWORK)" "$(ENV)"

# Verify Proxies: Discovers one OrganizationProxy and one AccountProxy instance on a chain
# and verifies each (using GUESS_CONSTRUCTOR_ARGS so per-instance constructor args are
# pulled from the on-chain creation tx). Verifying one instance per type is enough —
# explorers auto-match the rest by bytecode. Honors VERIFIER/VERIFIER_URL like verify-all.
#
# Examples:
#   make verify-proxies NETWORK=mainnet ENV=prod
#   make verify-proxies NETWORK=ronin ENV=prod VERIFIER=blockscout
verify-proxies:
	@./script/sh/verify_proxies.sh "$(NETWORK)" "$(ENV)" "$(VERIFIER)" "$(VERIFIER_URL)"

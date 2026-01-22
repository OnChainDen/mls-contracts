# ==============================================================================
# Makefile for Foundry Smart Contract Project
# ==============================================================================
#
# Requirements:
#   - Foundry (forge, cast) >= 0.2.0
#   - Slither >= 0.10.0
#   - Node.js >= 18 (for solhint)
#   - solhint (npm install -g solhint)
#
# ==============================================================================

# Core commands
.PHONY: all build clean test format lint analyze check install update sizes remove
.PHONY: coverage snapshot gas-report help

# CREATE2 factory deployment
.PHONY: fund-arachnid-deployer deploy-arachnid-factory fund-safe-deployer deploy-safe-factory

# Platform deployment
.PHONY: deploy-libraries deploy-contracts deploy-platform validate-signer-vars
.PHONY: deploy-libraries-dry-run deploy-contracts-dry-run deploy-platform-dry-run

# Utilities
.PHONY: check-factory check-all-factories compute-lib-addresses compute-all-lib-addresses verify

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
	@echo "Platform Deployment:"
	@echo "  deploy-libraries          Deploy platform libraries via CREATE2"
	@echo "  deploy-contracts          Deploy platform contracts with library linking"
	@echo "  deploy-platform           Full deployment (libraries + contracts)"
	@echo "  deploy-libraries-dry-run  Simulate library deployment (no broadcast)"
	@echo "  deploy-contracts-dry-run  Simulate contract deployment (no broadcast)"
	@echo "  deploy-platform-dry-run   Simulate full deployment (no broadcast)"
	@echo ""
	@echo "CREATE2 Factory Deployment:"
	@echo "  fund-arachnid-deployer    Fund the Arachnid factory deployer"
	@echo "  deploy-arachnid-factory   Deploy the Arachnid CREATE2 factory"
	@echo "  fund-safe-deployer        Fund the Safe factory deployer"
	@echo "  deploy-safe-factory       Deploy the Safe Singleton Factory"
	@echo ""
	@echo "Utilities:"
	@echo "  check-factory             Check if a factory is deployed"
	@echo "  check-all-factories       Check all factories on a network"
	@echo "  compute-lib-addresses     Compute expected library addresses"
	@echo "  compute-all-lib-addresses Compute library addresses for all factories"
	@echo "  verify                    Verify a contract on Etherscan"
	@echo ""
	@echo "Configuration Variables:"
	@echo "  NETWORK   Target network: local, mainnet, sepolia, polygon, etc. (default: local)"
	@echo "  SIGNER    Signing method: account or ledger (default: account)"
	@echo "  ACCOUNT   Foundry keystore account name (required for SIGNER=account)"
	@echo "  SENDER    EOA address (auto-derived from ACCOUNT, required for ledger)"
	@echo "  FACTORY   CREATE2 factory: arachnid, safe-prod, safe-nonprod (default: arachnid)"
	@echo "  HD_PATH   Ledger HD derivation path (default: m/44'/60'/0'/0/0)"
	@echo "  VERBOSITY Forge verbosity level (default: $(VERBOSITY))"
	@echo ""
	@echo "Examples:"
	@echo "  make deploy-libraries NETWORK=sepolia ACCOUNT=my-deployer"
	@echo "  make deploy-platform FACTORY=arachnid NETWORK=mainnet SIGNER=ledger SENDER=0x..."
	@echo "  make check-all-factories NETWORK=mainnet"

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

# Lint: Checks code style (no fixes)
lint:
	forge fmt --check
	forge lint

	# Run solhint linter on our core source contracts
	# This will automatically use our core config, located at `.solhint.json`.
	npx solhint 'src/**/*.sol'

	# Run solhint linter on our scripts
	# This will automatically use our script-specific config, located at `script/.solhint.json`. 
	# This config "inherits" from our core config, but overrides rules that shouldn't apply to scripts.
	npx solhint 'script/**/*.sol'

# Analyze: Static Analysis (Slither)
analyze:
	slither src/
	slither --config-file slither.script.config.json script/ 

# Sizes: Checks the sizes of the contracts
sizes:
	forge build --sizes

# Check: The "CI Mode" - Runs everything
# This is what you run before pushing code.
check: format lint analyze sizes test

# Coverage: Generates test coverage report
coverage:
	forge coverage

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
# Configuration Variables (override via command line):
#   NETWORK  - Target network: local, mainnet, polygon, arbitrum, optimism, base (default: local)
#   SIGNER   - Signing method: account or ledger (default: account)
#   ACCOUNT  - Foundry keystore account name (required when SIGNER=account)
#   SENDER   - EOA address (auto-derived from ACCOUNT, required for ledger)
#   FACTORY  - CREATE2 factory: arachnid, safe-prod, safe-nonprod (default: arachnid)
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

# ------------------------------------------------------------------------------
# CREATE2 Factory Addresses
# ------------------------------------------------------------------------------
ARACHNID_FACTORY_ADDRESS := 0x4e59b44847b379578588920cA78FbF26c0B4956C
# TODO: Fill in after deploying Safe Singleton Factory from prod deployer
SAFE_PROD_FACTORY_ADDRESS := 0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7
SAFE_NONPROD_FACTORY_ADDRESS := 0xC6123B1C95825f98939C76c8cBCEFDBB1C0D94db

# Arachnid deployer address (for funding)
ARACHNID_DEPLOYER_ADDRESS := 0x3fAB184622Dc19b6109349B94811493BF2a45362

# ------------------------------------------------------------------------------
# Factory Address Selection (based on FACTORY variable)
# Library addresses are now configured in foundry.toml profiles.
# ------------------------------------------------------------------------------
ifeq ($(FACTORY),arachnid)
    FACTORY_ADDRESS := $(ARACHNID_FACTORY_ADDRESS)
else ifeq ($(FACTORY),safe-prod)
    FACTORY_ADDRESS := $(SAFE_PROD_FACTORY_ADDRESS)
else ifeq ($(FACTORY),safe-nonprod)
    FACTORY_ADDRESS := $(SAFE_NONPROD_FACTORY_ADDRESS)
else
    $(error Invalid FACTORY value '$(FACTORY)'. Use: arachnid, safe-prod, or safe-nonprod)
endif

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
# User will be prompted for their keystore password.
# Uses deferred evaluation (=) so the shell command only runs when SENDER is needed.
# ------------------------------------------------------------------------------
ifdef ACCOUNT
    ifndef SENDER
        SENDER = $(shell \
            echo "" >&2 && \
            echo "========================================" >&2 && \
            echo "Deriving address for account: $(ACCOUNT)" >&2 && \
            echo "Enter your keystore password below." >&2 && \
            echo "(This is to get the --sender address, not to broadcast transactions)" >&2 && \
            echo "========================================" >&2 && \
            cast wallet address --account $(ACCOUNT))
    endif
endif

# ------------------------------------------------------------------------------
# Signer Flags (based on SIGNER variable)
# ------------------------------------------------------------------------------
ifeq ($(SIGNER),ledger)
    SIGNER_FLAGS = --ledger --hd-paths "$(HD_PATH)" --sender $(SENDER)
else ifeq ($(SIGNER),account)
    SIGNER_FLAGS = --account $(ACCOUNT) --sender $(SENDER)
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

# Fund Arachnid Deployer: Sends ETH to the Arachnid factory deployer address
# This is required before deploying the Arachnid factory on a new chain.
#
# Example:
#   make fund-arachnid-deployer NETWORK=sepolia ACCOUNT=my-deployer SENDER=0x1234...
fund-arachnid-deployer: validate-signer-vars
	@echo "Funding Arachnid factory deployer..."
	@echo "  Network: $(NETWORK)"
	@echo "  Target: $(ARACHNID_DEPLOYER_ADDRESS)"
	forge script script/DeployArachnidFactory.s.sol:DeployArachnidFactory \
		--sig "fundDeployer()" \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Deploy Arachnid Factory: Deploys the Arachnid Deterministic Deployment Proxy
# Requires: The deployer address must be funded first (use fund-arachnid-deployer)
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

# Fund Safe Deployer: Sends ETH to the Safe Singleton Factory deployer address
# The target address depends on whether you're using prod or non-prod deployer.
# Pass SAFE_DEPLOYER_ADDRESS to specify the target.
#
# Example:
#   make fund-safe-deployer SAFE_DEPLOYER_ADDRESS=0xE1CB04A0fA36DdD16a06ea828007E35e1a3cBC37 NETWORK=sepolia ACCOUNT=my-deployer SENDER=0x1234...
fund-safe-deployer: validate-signer-vars
ifndef SAFE_DEPLOYER_ADDRESS
	$(error SAFE_DEPLOYER_ADDRESS is required. Set SAFE_DEPLOYER_ADDRESS=<deployer-address>)
endif
	@echo "Funding Safe Singleton Factory deployer..."
	@echo "  Network: $(NETWORK)"
	@echo "  Target: $(SAFE_DEPLOYER_ADDRESS)"
	forge script script/DeploySafeSingletonFactory.s.sol:DeploySafeSingletonFactory \
		--sig "fundDeployer(address)" $(SAFE_DEPLOYER_ADDRESS) \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Deploy Safe Factory: Deploys the Safe Singleton Factory
# IMPORTANT: Must be run from the correct deployer EOA at nonce 0 for deterministic address.
# The deployer must be funded first (use fund-safe-deployer).
#
# Example:
#   make deploy-safe-factory NETWORK=sepolia ACCOUNT=safe-deployer SENDER=0xE1CB04A0fA36DdD16a06ea828007E35e1a3cBC37
deploy-safe-factory: validate-signer-vars
	@echo "Deploying Safe Singleton Factory..."
	@echo "  Network: $(NETWORK)"
	@echo "  Deployer: $(SENDER)"
	CONFIRM_DEPLOYMENT=true forge script script/DeploySafeSingletonFactory.s.sol:DeploySafeSingletonFactory \
		--sig "run()" \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# ==============================================================================
# Platform Deployment Commands
# ==============================================================================

# Deploy Libraries: Deploys the 4 platform libraries via CREATE2
# These must be deployed BEFORE running deploy-contracts.
# Does NOT use --libraries flags (libraries are being deployed, not linked).
#
# Example:
#   make deploy-libraries NETWORK=sepolia ACCOUNT=my-deployer SENDER=0x1234...
#   make deploy-libraries FACTORY=safe-prod NETWORK=mainnet SIGNER=ledger SENDER=0x1234...
deploy-libraries: validate-signer-vars
	@echo "Deploying platform libraries via CREATE2..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	forge script script/DeployLibraries.s.sol:DeployLibraries \
		--sig "run(address)" $(FACTORY_ADDRESS) \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Deploy Contracts: Deploys all platform contracts with library linking
# IMPORTANT: Libraries must be deployed first (use deploy-libraries).
# Uses FOUNDRY_PROFILE to link libraries from foundry.toml profiles.
#
# Example:
#   make deploy-contracts NETWORK=sepolia ACCOUNT=my-deployer SENDER=0x1234...
#   make deploy-contracts FACTORY=safe-prod NETWORK=mainnet SIGNER=ledger SENDER=0x1234...
deploy-contracts: validate-signer-vars
	@echo "Deploying platform contracts with library linking..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	@echo "  Profile: $(FACTORY) (library addresses from foundry.toml)"
	FOUNDRY_PROFILE=$(FACTORY) forge script script/DeployContracts.s.sol:DeployContracts \
		--sig "run(address)" $(FACTORY_ADDRESS) \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(VERBOSITY)

# Deploy Platform: Full deployment of libraries and contracts
# This is a convenience target that runs deploy-libraries then deploy-contracts.
#
# Example:
#   make deploy-platform NETWORK=sepolia ACCOUNT=my-deployer SENDER=0x1234...
#   make deploy-platform FACTORY=arachnid NETWORK=mainnet SIGNER=ledger SENDER=0x1234...
deploy-platform: deploy-libraries deploy-contracts
	@echo "Platform deployment complete!"
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY)"

# ------------------------------------------------------------------------------
# Dry-Run (Simulation) Targets
# These run without --broadcast to simulate deployment without sending transactions.
# ------------------------------------------------------------------------------

# Deploy Libraries Dry-Run: Simulates library deployment
#
# Example:
#   make deploy-libraries-dry-run NETWORK=sepolia
deploy-libraries-dry-run:
	@echo "Simulating library deployment (dry-run)..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	forge script script/DeployLibraries.s.sol:DeployLibraries \
		--sig "run(address)" $(FACTORY_ADDRESS) \
		--rpc-url $(RPC_URL) \
		$(VERBOSITY)

# Deploy Contracts Dry-Run: Simulates contract deployment
#
# Example:
#   make deploy-contracts-dry-run NETWORK=sepolia
deploy-contracts-dry-run:
	@echo "Simulating contract deployment (dry-run)..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	@echo "  Profile: $(FACTORY) (library addresses from foundry.toml)"
	FOUNDRY_PROFILE=$(FACTORY) forge script script/DeployContracts.s.sol:DeployContracts \
		--sig "run(address)" $(FACTORY_ADDRESS) \
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
# Deployment Utility Commands
# ==============================================================================

# Check Factory: Verifies if a specific CREATE2 factory is deployed on the target network
# Uses the FACTORY variable to select which factory to check.
#
# Example:
#   make check-factory FACTORY=arachnid NETWORK=sepolia
#   make check-factory FACTORY=safe-prod NETWORK=mainnet
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
	@$(MAKE) --no-print-directory check-factory FACTORY=safe-prod NETWORK=$(NETWORK)
	@echo ""
	@$(MAKE) --no-print-directory check-factory FACTORY=safe-nonprod NETWORK=$(NETWORK)

# Compute Lib Addresses: Computes expected library addresses for a specific factory
# Useful to preview addresses before deployment or verify configuration.
#
# Example:
#   make compute-lib-addresses FACTORY=arachnid NETWORK=sepolia
#   make compute-lib-addresses FACTORY=safe-prod NETWORK=mainnet
compute-lib-addresses:
	@echo "Computing library addresses for factory: $(FACTORY)"
	@echo "  Factory address: $(FACTORY_ADDRESS)"
	@echo ""
	forge script script/DeployLibraries.s.sol:DeployLibraries \
		--sig "computeAddresses(address)" $(FACTORY_ADDRESS) \
		--rpc-url $(RPC_URL)

# Compute All Lib Addresses: Computes expected library addresses for all factories
# Continues even if a factory is not deployed (will show error but proceed to next).
#
# Example:
#   make compute-all-lib-addresses NETWORK=sepolia
#   make compute-all-lib-addresses NETWORK=mainnet
compute-all-lib-addresses:
	@echo "Computing library addresses for all factories on $(NETWORK)..."
	@echo ""
	-@$(MAKE) --no-print-directory compute-lib-addresses FACTORY=arachnid NETWORK=$(NETWORK)
	@echo ""
	-@$(MAKE) --no-print-directory compute-lib-addresses FACTORY=safe-prod NETWORK=$(NETWORK)
	@echo ""
	-@$(MAKE) --no-print-directory compute-lib-addresses FACTORY=safe-nonprod NETWORK=$(NETWORK)

# Verify: Verifies a deployed contract on Etherscan
# Requires CONTRACT_ADDRESS and CONTRACT_NAME variables.
#
# Example:
#   make verify CONTRACT_ADDRESS=0x1234... CONTRACT_NAME=OrganizationImplementation NETWORK=mainnet
#   make verify CONTRACT_ADDRESS=0x1234... CONTRACT_NAME=src/organization/OrganizationImplementation.sol:OrganizationImplementation NETWORK=sepolia
verify:
ifndef CONTRACT_ADDRESS
	$(error CONTRACT_ADDRESS is required. Set CONTRACT_ADDRESS=<deployed-contract-address>)
endif
ifndef CONTRACT_NAME
	$(error CONTRACT_NAME is required. Set CONTRACT_NAME=<contract-name-or-path>)
endif
	@echo "Verifying contract on $(NETWORK)..."
	@echo "  Address: $(CONTRACT_ADDRESS)"
	@echo "  Contract: $(CONTRACT_NAME)"
	forge verify-contract $(CONTRACT_ADDRESS) $(CONTRACT_NAME) \
		--chain $(NETWORK) \
		--watch
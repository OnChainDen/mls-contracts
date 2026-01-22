# ALWAYS list your targets here to prevent file conflicts
.PHONY: all build clean test format lint analyze check install update sizes
.PHONY: deploy-all deploy-dry-run
.PHONY: fund-arachnid-deployer deploy-arachnid-factory
.PHONY: fund-safe-deployer deploy-safe-factory
.PHONY: deploy-libraries deploy-contracts deploy-platform
.PHONY: check-factory compute-lib-addresses
.PHONY: validate-signer-vars

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

# ------------------------------------------------------------------------------
# CREATE2 Factory Addresses
# ------------------------------------------------------------------------------
ARACHNID_FACTORY_ADDRESS := 0x4e59b44847b379578588920cA78FbF26c0B4956C
SAFE_PROD_FACTORY_ADDRESS := 0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7
# TODO: Fill in after deploying Safe Singleton Factory from non-prod deployer
SAFE_NONPROD_FACTORY_ADDRESS := 0x0000000000000000000000000000000000000000

# Arachnid deployer address (for funding)
ARACHNID_DEPLOYER_ADDRESS := 0x3fAB184622Dc19b6109349B94811493BF2a45362

# ------------------------------------------------------------------------------
# Library Paths (constant - must match DeploymentConfig.sol)
# ------------------------------------------------------------------------------
LIB_POLICY_PATH := src/organization/libraries/LibOrganizationPolicy.sol:LibOrganizationPolicy
LIB_ADMIN_PATH := src/organization/libraries/LibOrganizationAdmin.sol:LibOrganizationAdmin
LIB_INIT_PATH := src/organization/libraries/LibOrganizationInitialization.sol:LibOrganizationInitialization
LIB_ACCSIG_PATH := src/organization/libraries/LibOrganizationAccountSignature.sol:LibOrganizationAccountSignature

# ------------------------------------------------------------------------------
# Library Addresses by Factory (must match DeploymentConfig.sol)
# ------------------------------------------------------------------------------
# Arachnid factory library addresses
ARACHNID_LIB_POLICY := 0x0c39cb4F67AA70D53ceE37d4c88f11ffDb07E314
ARACHNID_LIB_ADMIN := 0x744CaFa607273AF5664073d05BE066C6bDbf8201
ARACHNID_LIB_INIT := 0x95A9CDA2a67E48b154d8EFa3B147f31eC6e8147E
ARACHNID_LIB_ACCSIG := 0x6A6709A2c898E719A6Ee7635a3963122059655eB

# Safe prod factory library addresses (TODO: fill after deploying libraries via prod Safe factory)
SAFE_PROD_LIB_POLICY := 0x0000000000000000000000000000000000000000
SAFE_PROD_LIB_ADMIN := 0x0000000000000000000000000000000000000000
SAFE_PROD_LIB_INIT := 0x0000000000000000000000000000000000000000
SAFE_PROD_LIB_ACCSIG := 0x0000000000000000000000000000000000000000

# Safe non-prod factory library addresses (TODO: fill after deploying libraries via non-prod Safe factory)
SAFE_NONPROD_LIB_POLICY := 0x0000000000000000000000000000000000000000
SAFE_NONPROD_LIB_ADMIN := 0x0000000000000000000000000000000000000000
SAFE_NONPROD_LIB_INIT := 0x0000000000000000000000000000000000000000
SAFE_NONPROD_LIB_ACCSIG := 0x0000000000000000000000000000000000000000

# ------------------------------------------------------------------------------
# Factory Address Selection (based on FACTORY variable)
# ------------------------------------------------------------------------------
ifeq ($(FACTORY),arachnid)
    FACTORY_ADDRESS := $(ARACHNID_FACTORY_ADDRESS)
    LIB_POLICY_ADDR := $(ARACHNID_LIB_POLICY)
    LIB_ADMIN_ADDR := $(ARACHNID_LIB_ADMIN)
    LIB_INIT_ADDR := $(ARACHNID_LIB_INIT)
    LIB_ACCSIG_ADDR := $(ARACHNID_LIB_ACCSIG)
else ifeq ($(FACTORY),safe-prod)
    FACTORY_ADDRESS := $(SAFE_PROD_FACTORY_ADDRESS)
    LIB_POLICY_ADDR := $(SAFE_PROD_LIB_POLICY)
    LIB_ADMIN_ADDR := $(SAFE_PROD_LIB_ADMIN)
    LIB_INIT_ADDR := $(SAFE_PROD_LIB_INIT)
    LIB_ACCSIG_ADDR := $(SAFE_PROD_LIB_ACCSIG)
else ifeq ($(FACTORY),safe-nonprod)
    FACTORY_ADDRESS := $(SAFE_NONPROD_FACTORY_ADDRESS)
    LIB_POLICY_ADDR := $(SAFE_NONPROD_LIB_POLICY)
    LIB_ADMIN_ADDR := $(SAFE_NONPROD_LIB_ADMIN)
    LIB_INIT_ADDR := $(SAFE_NONPROD_LIB_INIT)
    LIB_ACCSIG_ADDR := $(SAFE_NONPROD_LIB_ACCSIG)
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
# ------------------------------------------------------------------------------
ifdef ACCOUNT
    ifndef SENDER
        SENDER := $(shell \
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
.PHONY: validate-signer-vars
validate-signer-vars:
ifeq ($(SIGNER),ledger)
ifndef SENDER
	$(error SENDER is required for Ledger. Set SENDER=<your-address>)
endif
else ifeq ($(SIGNER),account)
ifndef ACCOUNT
	$(error ACCOUNT is required. Set ACCOUNT=<keystore-name>)
endif
endif

# ------------------------------------------------------------------------------
# Library Flags (only used by deploy-contracts)
# ------------------------------------------------------------------------------
LIBRARIES_FLAGS := \
	--libraries $(LIB_POLICY_PATH):$(LIB_POLICY_ADDR) \
	--libraries $(LIB_ADMIN_PATH):$(LIB_ADMIN_ADDR) \
	--libraries $(LIB_INIT_PATH):$(LIB_INIT_ADDR) \
	--libraries $(LIB_ACCSIG_PATH):$(LIB_ACCSIG_ADDR)

# ==============================================================================
# Legacy Deployment Commands (using deploy_all.sh script)
# ==============================================================================

# Deploy All: Deploys the entire platform to a chain using the shell script
# Requires: PRIVATE_KEY and RPC_URL environment variables
# Optional: VERIFY=true ETHERSCAN_API_KEY=<key> for contract verification
#
# Example:
#   PRIVATE_KEY=<key> RPC_URL=<url> make deploy-all
#   PRIVATE_KEY=<key> RPC_URL=<url> VERIFY=true ETHERSCAN_API_KEY=<api> make deploy-all
deploy-all:
	@./script/sh/deploy_all.sh

# Deploy Dry Run: Simulates deployment without broadcasting transactions
# Use this to verify everything works before actual deployment
#
# Example:
#   PRIVATE_KEY=<key> RPC_URL=<url> make deploy-dry-run
deploy-dry-run:
	@DRY_RUN=true ./script/sh/deploy_all.sh

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
		-vvvv

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
		-vvvv

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
		-vvvv

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
		-vvvv

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
		-vvvv

# Deploy Contracts: Deploys all platform contracts with library linking
# IMPORTANT: Libraries must be deployed first (use deploy-libraries).
# This target uses --libraries flags to link to the deployed library addresses.
#
# Example:
#   make deploy-contracts NETWORK=sepolia ACCOUNT=my-deployer SENDER=0x1234...
#   make deploy-contracts FACTORY=safe-prod NETWORK=mainnet SIGNER=ledger SENDER=0x1234...
deploy-contracts: validate-signer-vars
	@echo "Deploying platform contracts with library linking..."
	@echo "  Network: $(NETWORK)"
	@echo "  Factory: $(FACTORY) ($(FACTORY_ADDRESS))"
	@echo "  Libraries:"
	@echo "    Policy: $(LIB_POLICY_ADDR)"
	@echo "    Admin: $(LIB_ADMIN_ADDR)"
	@echo "    Init: $(LIB_INIT_ADDR)"
	@echo "    AccSig: $(LIB_ACCSIG_ADDR)"
	forge script script/DeployContracts.s.sol:DeployContracts \
		--sig "run(address)" $(FACTORY_ADDRESS) \
		--rpc-url $(RPC_URL) \
		$(SIGNER_FLAGS) \
		--broadcast \
		$(LIBRARIES_FLAGS) \
		-vvvv

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

# ==============================================================================
# Utility Commands
# ==============================================================================

# Check Factory: Verifies if a CREATE2 factory is deployed on the target network
# Checks for both Arachnid and Safe Singleton Factory addresses.
#
# Example:
#   make check-factory NETWORK=sepolia
#   make check-factory NETWORK=mainnet
check-factory:
	@echo "Checking for CREATE2 factories on $(NETWORK)..."
	@echo ""
	@echo "Arachnid Factory ($(ARACHNID_FACTORY_ADDRESS)):"
	@cast code $(ARACHNID_FACTORY_ADDRESS) --rpc-url $(RPC_URL) > /dev/null 2>&1 && \
		(code=$$(cast code $(ARACHNID_FACTORY_ADDRESS) --rpc-url $(RPC_URL)); \
		if [ "$$code" != "0x" ] && [ -n "$$code" ]; then \
			echo "  DEPLOYED"; \
		else \
			echo "  NOT DEPLOYED"; \
		fi) || echo "  ERROR: Could not check"
	@echo ""
	@echo "Safe Singleton Factory - Prod ($(SAFE_PROD_FACTORY_ADDRESS)):"
	@cast code $(SAFE_PROD_FACTORY_ADDRESS) --rpc-url $(RPC_URL) > /dev/null 2>&1 && \
		(code=$$(cast code $(SAFE_PROD_FACTORY_ADDRESS) --rpc-url $(RPC_URL)); \
		if [ "$$code" != "0x" ] && [ -n "$$code" ]; then \
			echo "  DEPLOYED"; \
		else \
			echo "  NOT DEPLOYED"; \
		fi) || echo "  ERROR: Could not check"

# Compute Lib Addresses: Computes expected library addresses for a factory
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
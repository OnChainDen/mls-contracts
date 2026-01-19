# ALWAYS list your targets here to prevent file conflicts
.PHONY: all build clean test format lint analyze check install update sizes deploy-all deploy-dry-run

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
	npx solhint 'src/**/*.sol'

# Analyze: Static Analysis (Slither)
analyze:
	slither .

# Sizes: Checks the sizes of the contracts
sizes:
	forge build --sizes

# Check: The "CI Mode" - Runs everything
# This is what you run before pushing code.
check: format lint analyze sizes test

# ==============================================================================
# Deployment Commands
# ==============================================================================

# Deploy All: Deploys the entire platform to a chain
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
# ALWAYS list your targets here to prevent file conflicts
.PHONY: all build clean test format lint analyze check install update

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

# Check: The "CI Mode" - Runs everything
# This is what you run before pushing code.
check: format lint analyze test
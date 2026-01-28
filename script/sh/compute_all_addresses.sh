#!/bin/bash
# =============================================================================
# Compute All CREATE2 Addresses Script
# =============================================================================
# Computes all deterministic CREATE2 addresses for platform contracts for a given
# factory. Orchestrates calls to individual deployment scripts' computeAddresses()
# functions and aggregates the results.
#
# This script handles the dependency chain correctly:
# 1. Computes Safe infrastructure addresses first
# 2. Computes library addresses
# 3. Uses computed library addresses to compile platform contracts (via --libraries)
# 4. Computes platform contract addresses (needs Deployer Safe address from step 1)
# 5. Computes Safe module addresses
#
# Output is in TOML format to facilitate easy comparison with deployment.toml.
#
# Usage:
#   ./compute_all_addresses.sh <factory>
#
# Where <factory> is one of:
#   - arachnid
#   - den-nonprod
#   - den-prod
#
# =============================================================================

set -e  # Stop on first error

# =============================================================================
# Source Shared Configuration
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/deployment_config.sh"

# Validate prerequisites (deployment.toml exists, yq available)
validate_prerequisites

# =============================================================================
# Argument Validation
# =============================================================================
FACTORY="$1"
validate_factory "$FACTORY"

# Read factory address from deployment.toml
FACTORY_ADDRESS=$(get_factory_address "$FACTORY")

# Read executor EOA addresses from deployment.toml (nonprod for local/testnet computation)
GUARDIAN_EXECUTOR_ADDRESS=$(get_guardian_executor "nonprod")
DEPLOYER_EXECUTOR_ADDRESS=$(get_deployer_executor "nonprod")

# Track number of progress lines printed (for clearing later)
PROGRESS_LINES=0

# Print a progress message and track line count
print_progress() {
    echo "$1" >&2
    PROGRESS_LINES=$((PROGRESS_LINES + 1))
}

# Clear progress lines and move cursor back up
clear_progress() {
    if [[ $PROGRESS_LINES -gt 0 ]]; then
        # Move cursor up N lines and clear from cursor to end of screen
        printf "\033[%dA\033[J" "$PROGRESS_LINES" >&2
    fi
}

# =============================================================================
# Main Execution
# =============================================================================

# Print the header to stderr (progress)
echo "" >&2
echo "================================================================================" >&2
echo "  Computing addresses for $FACTORY ($FACTORY_ADDRESS)" >&2
echo "================================================================================" >&2
echo "" >&2

# -----------------------------------------------------------------------------
# Step 1: Compute Safe Infrastructure Addresses
# -----------------------------------------------------------------------------
print_progress "  Computing Safe infrastructure addresses..."
SAFE_OUTPUT=$(FOUNDRY_PROFILE=safe forge script script/safe/DeploySafe.s.sol:DeploySafe \
    --sig "computeAddresses(address)" "$FACTORY_ADDRESS" --offline 2>&1) || {
    clear_progress
    echo "Error: Failed to compute Safe addresses" >&2
    echo "$SAFE_OUTPUT" >&2
    exit 1
}

# Extract Safe addresses
SAFE_SINGLETON_ADDRESS=$(extract_address "$SAFE_OUTPUT" "GnosisSafe Singleton")
SAFE_PROXY_FACTORY_ADDRESS=$(extract_address "$SAFE_OUTPUT" "GnosisSafeProxyFactory")
SAFE_FALLBACK_HANDLER_ADDRESS=$(extract_address "$SAFE_OUTPUT" "CompatibilityFallbackHandler")
SAFE_MULTISEND_ADDRESS=$(extract_address "$SAFE_OUTPUT" "MultiSend")
SAFE_MULTISEND_CALL_ONLY_ADDRESS=$(extract_address "$SAFE_OUTPUT" "MultiSendCallOnly")
SAFE_CREATE_CALL_ADDRESS=$(extract_address "$SAFE_OUTPUT" "CreateCall")
SAFE_SIMULATE_TX_ACCESSOR_ADDRESS=$(extract_address "$SAFE_OUTPUT" "SimulateTxAccessor")
GUARDIAN_SAFE_ADDRESS=$(extract_address "$SAFE_OUTPUT" "Guardian Safe")
DEPLOYER_SAFE_ADDRESS=$(extract_address "$SAFE_OUTPUT" "Deployer Safe")

# Verify we got the critical addresses
if [[ -z "$DEPLOYER_SAFE_ADDRESS" ]]; then
    clear_progress
    echo "Error: Failed to extract Deployer Safe address from output" >&2
    echo "$SAFE_OUTPUT" >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 2: Compute Library Addresses (in dependency order)
# -----------------------------------------------------------------------------
# Library dependency chain:
#   - LibOrganizationPolicy: No deps on other deployed libraries
#   - LibOrganizationAdmin: No deps on other deployed libraries
#   - LibOrganizationInitialization: Depends on LibOrganizationAdmin
#   - LibOrganizationAccountSignature: Depends on LibOrganizationPolicy
#
# We must compute in stages because some libraries have their bytecode affected
# by the addresses of other libraries they depend on.

# Step 2a: Compute independent library addresses (Policy and Admin)
print_progress "  Computing independent library addresses (Policy, Admin)..."
LIB_OUTPUT_INDEPENDENT=$(forge script script/DeployLibraries.s.sol:DeployLibraries \
    --sig "computeIndependentAddresses(address)" "$FACTORY_ADDRESS" --offline 2>&1) || {
    clear_progress
    echo "Error: Failed to compute independent library addresses" >&2
    echo "$LIB_OUTPUT_INDEPENDENT" >&2
    exit 1
}

# Extract independent library addresses (these are correct without --libraries)
LIB_ORG_POLICY_ADDRESS=$(extract_address "$LIB_OUTPUT_INDEPENDENT" "LibOrganizationPolicy")
LIB_ORG_ADMIN_ADDRESS=$(extract_address "$LIB_OUTPUT_INDEPENDENT" "LibOrganizationAdmin")

if [[ -z "$LIB_ORG_POLICY_ADDRESS" || -z "$LIB_ORG_ADMIN_ADDRESS" ]]; then
    clear_progress
    echo "Error: Failed to extract independent library addresses from output" >&2
    echo "$LIB_OUTPUT_INDEPENDENT" >&2
    exit 1
fi

# Step 2b: Compute dependent library addresses (Init and AccountSig)
# These require --libraries flags because their bytecode contains the addresses
# of the libraries they depend on
print_progress "  Computing dependent library addresses (Init, AccountSig)..."

# Build --libraries flags for the independent libraries
DEP_LIBRARIES_FLAGS="--libraries ${LIB_ORG_POLICY_PATH}:${LIB_ORG_POLICY_ADDRESS}"
DEP_LIBRARIES_FLAGS="$DEP_LIBRARIES_FLAGS --libraries ${LIB_ORG_ADMIN_PATH}:${LIB_ORG_ADMIN_ADDRESS}"

LIB_OUTPUT_DEPENDENT=$(forge script script/DeployLibraries.s.sol:DeployLibraries \
    --sig "computeDependentAddresses(address)" "$FACTORY_ADDRESS" \
    $DEP_LIBRARIES_FLAGS --offline 2>&1) || {
    clear_progress
    echo "Error: Failed to compute dependent library addresses" >&2
    echo "$LIB_OUTPUT_DEPENDENT" >&2
    exit 1
}

# Extract dependent library addresses (these are now correct with --libraries)
LIB_ORG_INIT_ADDRESS=$(extract_address "$LIB_OUTPUT_DEPENDENT" "LibOrganizationInitialization")
LIB_ORG_ACCOUNT_SIG_ADDRESS=$(extract_address "$LIB_OUTPUT_DEPENDENT" "LibOrganizationAccountSignature")

if [[ -z "$LIB_ORG_INIT_ADDRESS" || -z "$LIB_ORG_ACCOUNT_SIG_ADDRESS" ]]; then
    clear_progress
    echo "Error: Failed to extract dependent library addresses from output" >&2
    echo "$LIB_OUTPUT_DEPENDENT" >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 3: Compute BatchedTransaction Address
# -----------------------------------------------------------------------------
print_progress "  Computing BatchedTransaction address..."
BATCHED_OUTPUT=$(forge script script/safe-module/DeployBatchedTransaction.s.sol:DeployBatchedTransaction \
    --sig "computeAddress(address)" "$FACTORY_ADDRESS" --offline 2>&1) || {
    clear_progress
    echo "Error: Failed to compute BatchedTransaction address" >&2
    echo "$BATCHED_OUTPUT" >&2
    exit 1
}

# Extract BatchedTransaction address
BATCHED_TRANSACTION_ADDRESS=$(extract_address "$BATCHED_OUTPUT" "BatchedTransaction")

if [[ -z "$BATCHED_TRANSACTION_ADDRESS" ]]; then
    clear_progress
    echo "Error: Failed to extract BatchedTransaction address from output" >&2
    echo "$BATCHED_OUTPUT" >&2
    exit 1
fi

# -----------------------------------------------------------------------------
# Step 4: Compute Platform Contract Addresses
# -----------------------------------------------------------------------------
print_progress "  Computing platform contract addresses..."

# Build --libraries flags using computed library addresses
LIBRARIES_FLAGS="--libraries ${LIB_ORG_POLICY_PATH}:${LIB_ORG_POLICY_ADDRESS}"
LIBRARIES_FLAGS="$LIBRARIES_FLAGS --libraries ${LIB_ORG_ADMIN_PATH}:${LIB_ORG_ADMIN_ADDRESS}"
LIBRARIES_FLAGS="$LIBRARIES_FLAGS --libraries ${LIB_ORG_INIT_PATH}:${LIB_ORG_INIT_ADDRESS}"
LIBRARIES_FLAGS="$LIBRARIES_FLAGS --libraries ${LIB_ORG_ACCOUNT_SIG_PATH}:${LIB_ORG_ACCOUNT_SIG_ADDRESS}"

# Run DeployContracts.computeAddresses with computed library addresses and deployer safe
CONTRACTS_OUTPUT=$(forge script script/DeployContracts.s.sol:DeployContracts \
    --sig "computeAddresses(address,address)" "$FACTORY_ADDRESS" "$DEPLOYER_SAFE_ADDRESS" \
    $LIBRARIES_FLAGS --offline 2>&1) || {
    clear_progress
    echo "Error: Failed to compute platform contract addresses" >&2
    echo "$CONTRACTS_OUTPUT" >&2
    exit 1
}

# Extract platform contract addresses
WHITELIST_IMPL_ADDRESS=$(extract_address "$CONTRACTS_OUTPUT" "ImplementationWhitelistImplementation")
ORG_IMPL_ADDRESS=$(extract_address "$CONTRACTS_OUTPUT" "OrganizationImplementation")
ACCOUNT_IMPL_ADDRESS=$(extract_address "$CONTRACTS_OUTPUT" "AccountImplementation")
ORG_FACTORY_ADDRESS=$(extract_address "$CONTRACTS_OUTPUT" "OrganizationFactory")
WHITELIST_PROXY_ADDRESS=$(extract_address "$CONTRACTS_OUTPUT" "ImplementationWhitelistProxy")

# -----------------------------------------------------------------------------
# Step 5: Compute Safe Executor Module Addresses
# -----------------------------------------------------------------------------
print_progress "  Computing Safe Executor Module addresses..."

# Guardian module - use the overloaded function that accepts Safe and BatchedTransaction addresses
# This ensures we use the computed addresses, not hardcoded ones from DeploymentConfig
GUARDIAN_MODULE_OUTPUT=$(forge script script/safe-module/DeploySafeExecutorModule.s.sol:DeploySafeExecutorModule \
    --sig "computeAddress(address,string,address,address,address)" \
    "$FACTORY_ADDRESS" "guardian" "$GUARDIAN_EXECUTOR_ADDRESS" "$GUARDIAN_SAFE_ADDRESS" "$BATCHED_TRANSACTION_ADDRESS" \
    --offline 2>&1) || {
    echo "Warning: Failed to compute Guardian module address (may need different executor address)" >&2
}
GUARDIAN_MODULE_ADDRESS=$(extract_address "$GUARDIAN_MODULE_OUTPUT" "SafeExecutorModule")

# Deployer module - use the overloaded function that accepts Safe and BatchedTransaction addresses
DEPLOYER_MODULE_OUTPUT=$(forge script script/safe-module/DeploySafeExecutorModule.s.sol:DeploySafeExecutorModule \
    --sig "computeAddress(address,string,address,address,address)" \
    "$FACTORY_ADDRESS" "deployer" "$DEPLOYER_EXECUTOR_ADDRESS" "$DEPLOYER_SAFE_ADDRESS" "$BATCHED_TRANSACTION_ADDRESS" \
    --offline 2>&1) || {
    echo "Warning: Failed to compute Deployer module address (may need different executor address)" >&2
}
DEPLOYER_MODULE_ADDRESS=$(extract_address "$DEPLOYER_MODULE_OUTPUT" "SafeExecutorModule")

# =============================================================================
# Output Results in TOML format (clear progress first)
# =============================================================================

# Clear the progress lines
clear_progress

# Print the TOML output to stdout
echo "# Computed addresses for $FACTORY ($FACTORY_ADDRESS)"
echo "# Generated by compute_all_addresses.sh"
echo "#"
echo "# Compare with deployment.toml to verify correctness."
echo ""
echo "[factory.\"$FACTORY\"]"
print_toml "factory" "$FACTORY_ADDRESS"
print_toml "factory_deployer" "$(get_factory_deployer "$FACTORY")"
echo ""
echo "# Safe 1.3.0 Infrastructure"
print_toml "safe_singleton" "${SAFE_SINGLETON_ADDRESS:-NOT_COMPUTED}"
print_toml "safe_proxy_factory" "${SAFE_PROXY_FACTORY_ADDRESS:-NOT_COMPUTED}"
print_toml "safe_fallback_handler" "${SAFE_FALLBACK_HANDLER_ADDRESS:-NOT_COMPUTED}"
print_toml "safe_multisend" "${SAFE_MULTISEND_ADDRESS:-NOT_COMPUTED}"
print_toml "safe_multisend_call_only" "${SAFE_MULTISEND_CALL_ONLY_ADDRESS:-NOT_COMPUTED}"
print_toml "safe_create_call" "${SAFE_CREATE_CALL_ADDRESS:-NOT_COMPUTED}"
print_toml "safe_simulate_tx_accessor" "${SAFE_SIMULATE_TX_ACCESSOR_ADDRESS:-NOT_COMPUTED}"
echo ""
echo "# Safe Multisigs"
print_toml "guardian_safe" "${GUARDIAN_SAFE_ADDRESS:-NOT_COMPUTED}"
print_toml "deployer_safe" "${DEPLOYER_SAFE_ADDRESS:-NOT_COMPUTED}"
echo ""
echo "# Platform Libraries"
print_toml "lib_org_policy" "${LIB_ORG_POLICY_ADDRESS:-NOT_COMPUTED}"
print_toml "lib_org_admin" "${LIB_ORG_ADMIN_ADDRESS:-NOT_COMPUTED}"
print_toml "lib_org_init" "${LIB_ORG_INIT_ADDRESS:-NOT_COMPUTED}"
print_toml "lib_org_account_sig" "${LIB_ORG_ACCOUNT_SIG_ADDRESS:-NOT_COMPUTED}"
echo ""
echo "# Platform Contracts"
print_toml "whitelist_impl" "${WHITELIST_IMPL_ADDRESS:-NOT_COMPUTED}"
print_toml "org_impl" "${ORG_IMPL_ADDRESS:-NOT_COMPUTED}"
print_toml "account_impl" "${ACCOUNT_IMPL_ADDRESS:-NOT_COMPUTED}"
print_toml "org_factory" "${ORG_FACTORY_ADDRESS:-NOT_COMPUTED}"
print_toml "whitelist_proxy" "${WHITELIST_PROXY_ADDRESS:-NOT_COMPUTED}"
echo ""
echo "# BatchedTransaction & Safe Executor Modules"
print_toml "batched_transaction" "${BATCHED_TRANSACTION_ADDRESS:-NOT_COMPUTED}"
print_toml "guardian_safe_executor_module" "${GUARDIAN_MODULE_ADDRESS:-NOT_COMPUTED}"
print_toml "deployer_safe_executor_module" "${DEPLOYER_MODULE_ADDRESS:-NOT_COMPUTED}"

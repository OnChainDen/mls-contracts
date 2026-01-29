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
# 2. Computes Safe multisig addresses for both prod and nonprod configurations
# 3. Computes library addresses
# 4. Computes BatchedTransaction address
# 5. Computes platform implementation addresses (environment-independent)
# 6. Computes platform contract addresses for both prod and nonprod configurations
#    (org_factory depends on guardian Safe, whitelist_proxy depends on admin Safe)
# 7. Computes Safe module addresses for both prod and nonprod configurations
#
# Output is in TOML format to facilitate easy comparison with deployment.toml.
# Includes both [factory.X.env.nonprod] and [factory.X.env.prod] sections.
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

# Read Guardian executor EOA addresses for both prod and nonprod configurations
GUARDIAN_EXECUTOR_NONPROD=$(get_guardian_executor "nonprod")
GUARDIAN_EXECUTOR_PROD=$(get_guardian_executor "prod")

# Helper to check if an address is zero
ZERO_ADDRESS="0x0000000000000000000000000000000000000000"

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
# Step 1: Compute Safe Infrastructure and Multisig Addresses
# -----------------------------------------------------------------------------
# Compute Safe infrastructure addresses (same for all variants)
print_progress "  Computing Safe infrastructure addresses..."
SAFE_INFRA_OUTPUT=$(FOUNDRY_PROFILE=safe forge script script/safe/DeploySafeInfrastructure.s.sol:DeploySafeInfrastructure \
    --sig "computeAddresses(address)" "$FACTORY_ADDRESS" --offline 2>&1) || {
    clear_progress
    echo "Error: Failed to compute Safe infrastructure addresses" >&2
    echo "$SAFE_INFRA_OUTPUT" >&2
    exit 1
}

# Extract Safe infrastructure addresses
SAFE_SINGLETON_ADDRESS=$(extract_address "$SAFE_INFRA_OUTPUT" "GnosisSafe Singleton")
SAFE_PROXY_FACTORY_ADDRESS=$(extract_address "$SAFE_INFRA_OUTPUT" "GnosisSafeProxyFactory")
SAFE_FALLBACK_HANDLER_ADDRESS=$(extract_address "$SAFE_INFRA_OUTPUT" "CompatibilityFallbackHandler")
SAFE_MULTISEND_ADDRESS=$(extract_address "$SAFE_INFRA_OUTPUT" "MultiSend")
SAFE_MULTISEND_CALL_ONLY_ADDRESS=$(extract_address "$SAFE_INFRA_OUTPUT" "MultiSendCallOnly")
SAFE_CREATE_CALL_ADDRESS=$(extract_address "$SAFE_INFRA_OUTPUT" "CreateCall")
SAFE_SIMULATE_TX_ACCESSOR_ADDRESS=$(extract_address "$SAFE_INFRA_OUTPUT" "SimulateTxAccessor")

# Compute nonprod Safe multisig addresses
print_progress "  Computing nonprod multisig addresses..."
SAFE_MULTISIG_NONPROD_OUTPUT=$(FOUNDRY_PROFILE=safe forge script script/safe/DeploySafeMultisigs.s.sol:DeploySafeMultisigs \
    --sig "computeAddresses(address,address,address,string)" \
    "$SAFE_SINGLETON_ADDRESS" "$SAFE_PROXY_FACTORY_ADDRESS" "$SAFE_FALLBACK_HANDLER_ADDRESS" "nonprod" --offline 2>&1) || {
    clear_progress
    echo "Error: Failed to compute Safe multisig addresses (nonprod)" >&2
    echo "$SAFE_MULTISIG_NONPROD_OUTPUT" >&2
    exit 1
}

# Extract nonprod Safe multisig addresses
GUARDIAN_SAFE_NONPROD=$(extract_address "$SAFE_MULTISIG_NONPROD_OUTPUT" "Guardian Safe")
ADMIN_SAFE_NONPROD=$(extract_address "$SAFE_MULTISIG_NONPROD_OUTPUT" "Admin Safe")

# Verify we got the critical nonprod addresses
if [[ -z "$GUARDIAN_SAFE_NONPROD" ]]; then
    clear_progress
    echo "Error: Failed to extract Guardian Safe (nonprod) address from output"
    echo "$SAFE_MULTISIG_NONPROD_OUTPUT"
    exit 1
fi
if [[ -z "$ADMIN_SAFE_NONPROD" ]]; then
    clear_progress
    echo "Error: Failed to extract Admin Safe (nonprod) address from output" >&2
    echo "$SAFE_MULTISIG_NONPROD_OUTPUT" >&2
    exit 1
fi

# Compute prod Safe multisig addresses
print_progress "  Computing prod multisig addresses..."
SAFE_MULTISIG_PROD_OUTPUT=$(FOUNDRY_PROFILE=safe forge script script/safe/DeploySafeMultisigs.s.sol:DeploySafeMultisigs \
    --sig "computeAddresses(address,address,address,string)" \
    "$SAFE_SINGLETON_ADDRESS" "$SAFE_PROXY_FACTORY_ADDRESS" "$SAFE_FALLBACK_HANDLER_ADDRESS" "prod" --offline 2>&1) || {
    clear_progress
    echo "Error: Failed to compute Safe multisig addresses (prod)" >&2
    echo "$SAFE_MULTISIG_PROD_OUTPUT" >&2
    exit 1
}

# Extract prod Safe multisig addresses
GUARDIAN_SAFE_PROD=$(extract_address "$SAFE_MULTISIG_PROD_OUTPUT" "Guardian Safe")
ADMIN_SAFE_PROD=$(extract_address "$SAFE_MULTISIG_PROD_OUTPUT" "Admin Safe")

# Verify we got the critical prod addresses
if [[ -z "$GUARDIAN_SAFE_PROD" ]]; then
    clear_progress
    echo "Error: Failed to extract Guardian Safe (prod) address from output"
    echo "$SAFE_MULTISIG_PROD_OUTPUT"
    exit 1
fi
if [[ -z "$ADMIN_SAFE_PROD" ]]; then
    clear_progress
    echo "Error: Failed to extract Admin Safe (prod) address from output" >&2
    echo "$SAFE_MULTISIG_PROD_OUTPUT" >&2
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
# Step 4: Compute Platform Contract Addresses (for both nonprod and prod)
# -----------------------------------------------------------------------------
# org_factory depends on guardian Safe, whitelist_proxy depends on admin Safe,
# so we compute them separately for each environment.
# Implementation contracts are environment-independent.

# Build --libraries flags using computed library addresses
LIBRARIES_FLAGS="--libraries ${LIB_ORG_POLICY_PATH}:${LIB_ORG_POLICY_ADDRESS}"
LIBRARIES_FLAGS="$LIBRARIES_FLAGS --libraries ${LIB_ORG_ADMIN_PATH}:${LIB_ORG_ADMIN_ADDRESS}"
LIBRARIES_FLAGS="$LIBRARIES_FLAGS --libraries ${LIB_ORG_INIT_PATH}:${LIB_ORG_INIT_ADDRESS}"
LIBRARIES_FLAGS="$LIBRARIES_FLAGS --libraries ${LIB_ORG_ACCOUNT_SIG_PATH}:${LIB_ORG_ACCOUNT_SIG_ADDRESS}"

# Compute platform contracts with NONPROD guardian and admin safes
print_progress "  Computing platform contract addresses (nonprod)..."
CONTRACTS_OUTPUT_NONPROD=$(forge script script/DeployContracts.s.sol:DeployContracts \
    --sig "computeAddresses(address,address,address)" "$FACTORY_ADDRESS" "$GUARDIAN_SAFE_NONPROD" "$ADMIN_SAFE_NONPROD" \
    $LIBRARIES_FLAGS --offline 2>&1) || {
    clear_progress
    echo "Error: Failed to compute platform contract addresses (nonprod)" >&2
    echo "$CONTRACTS_OUTPUT_NONPROD" >&2
    exit 1
}

# Extract implementation addresses (same for both envs - only depends on factory)
WHITELIST_IMPL_ADDRESS=$(extract_address "$CONTRACTS_OUTPUT_NONPROD" "ImplementationWhitelistImplementation")
ORG_IMPL_ADDRESS=$(extract_address "$CONTRACTS_OUTPUT_NONPROD" "OrganizationImplementation")
ACCOUNT_IMPL_ADDRESS=$(extract_address "$CONTRACTS_OUTPUT_NONPROD" "AccountImplementation")

# Extract nonprod-specific addresses (org_factory depends on guardian safe, whitelist_proxy on admin safe)
ORG_FACTORY_NONPROD=$(extract_address "$CONTRACTS_OUTPUT_NONPROD" "OrganizationFactory")
WHITELIST_PROXY_NONPROD=$(extract_address "$CONTRACTS_OUTPUT_NONPROD" "ImplementationWhitelistProxy")

# Compute platform contracts with PROD guardian and admin safes (skip if either is zero)
print_progress "  Computing platform contract addresses (prod)..."
if [[ "$GUARDIAN_SAFE_PROD" == "$ZERO_ADDRESS" || "$ADMIN_SAFE_PROD" == "$ZERO_ADDRESS" ]]; then
    ORG_FACTORY_PROD=""
    WHITELIST_PROXY_PROD=""
else
    CONTRACTS_OUTPUT_PROD=$(forge script script/DeployContracts.s.sol:DeployContracts \
        --sig "computeAddresses(address,address,address)" "$FACTORY_ADDRESS" "$GUARDIAN_SAFE_PROD" "$ADMIN_SAFE_PROD" \
        $LIBRARIES_FLAGS --offline 2>&1) || {
        echo "Warning: Failed to compute platform contract addresses (prod)" >&2
    }
    ORG_FACTORY_PROD=$(extract_address "$CONTRACTS_OUTPUT_PROD" "OrganizationFactory")
    WHITELIST_PROXY_PROD=$(extract_address "$CONTRACTS_OUTPUT_PROD" "ImplementationWhitelistProxy")
fi

# -----------------------------------------------------------------------------
# Step 5: Compute Guardian Safe Executor Module Addresses (for both prod and nonprod)
# -----------------------------------------------------------------------------
print_progress "  Computing Guardian Safe Executor Module addresses (nonprod)..."

# Nonprod Guardian module
GUARDIAN_MODULE_NONPROD_OUTPUT=$(forge script script/safe-module/DeployGuardianSafeModule.s.sol:DeployGuardianSafeModule \
    --sig "computeAddress(address,address,address,address)" \
    "$FACTORY_ADDRESS" "$GUARDIAN_EXECUTOR_NONPROD" "$GUARDIAN_SAFE_NONPROD" "$BATCHED_TRANSACTION_ADDRESS" \
    --offline 2>&1) || {
    echo "Warning: Failed to compute Guardian module address (nonprod)" >&2
}
GUARDIAN_MODULE_NONPROD=$(extract_address "$GUARDIAN_MODULE_NONPROD_OUTPUT" "SafeExecutorModule")

print_progress "  Computing Guardian Safe Executor Module addresses (prod)..."

# Prod Guardian module - skip if executor or safe is zero
if [[ "$GUARDIAN_EXECUTOR_PROD" == "$ZERO_ADDRESS" || "$GUARDIAN_SAFE_PROD" == "$ZERO_ADDRESS" ]]; then
    GUARDIAN_MODULE_PROD=""
else
    GUARDIAN_MODULE_PROD_OUTPUT=$(forge script script/safe-module/DeployGuardianSafeModule.s.sol:DeployGuardianSafeModule \
        --sig "computeAddress(address,address,address,address)" \
        "$FACTORY_ADDRESS" "$GUARDIAN_EXECUTOR_PROD" "$GUARDIAN_SAFE_PROD" "$BATCHED_TRANSACTION_ADDRESS" \
        --offline 2>&1) || {
        echo "Warning: Failed to compute Guardian module address (prod)" >&2
    }
    GUARDIAN_MODULE_PROD=$(extract_address "$GUARDIAN_MODULE_PROD_OUTPUT" "SafeExecutorModule")
fi

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
echo "# Platform Libraries (environment-independent)"
print_toml "lib_org_policy" "${LIB_ORG_POLICY_ADDRESS:-NOT_COMPUTED}"
print_toml "lib_org_admin" "${LIB_ORG_ADMIN_ADDRESS:-NOT_COMPUTED}"
print_toml "lib_org_init" "${LIB_ORG_INIT_ADDRESS:-NOT_COMPUTED}"
print_toml "lib_org_account_sig" "${LIB_ORG_ACCOUNT_SIG_ADDRESS:-NOT_COMPUTED}"
echo ""
echo "# Platform Implementation Contracts (environment-independent)"
print_toml "whitelist_impl" "${WHITELIST_IMPL_ADDRESS:-NOT_COMPUTED}"
print_toml "org_impl" "${ORG_IMPL_ADDRESS:-NOT_COMPUTED}"
print_toml "account_impl" "${ACCOUNT_IMPL_ADDRESS:-NOT_COMPUTED}"
echo ""
echo "# Safe 1.3.0 Infrastructure (environment-independent)"
print_toml "safe_singleton" "${SAFE_SINGLETON_ADDRESS:-NOT_COMPUTED}"
print_toml "safe_proxy_factory" "${SAFE_PROXY_FACTORY_ADDRESS:-NOT_COMPUTED}"
print_toml "safe_fallback_handler" "${SAFE_FALLBACK_HANDLER_ADDRESS:-NOT_COMPUTED}"
print_toml "safe_multisend" "${SAFE_MULTISEND_ADDRESS:-NOT_COMPUTED}"
print_toml "safe_multisend_call_only" "${SAFE_MULTISEND_CALL_ONLY_ADDRESS:-NOT_COMPUTED}"
print_toml "safe_create_call" "${SAFE_CREATE_CALL_ADDRESS:-NOT_COMPUTED}"
print_toml "safe_simulate_tx_accessor" "${SAFE_SIMULATE_TX_ACCESSOR_ADDRESS:-NOT_COMPUTED}"
echo ""
echo "# BatchedTransaction (environment-independent)"
print_toml "batched_transaction" "${BATCHED_TRANSACTION_ADDRESS:-NOT_COMPUTED}"
echo ""
echo "# Environment: nonprod"
echo "# Addresses that depend on the nonprod guardian/admin Safes"
echo "[factory.\"$FACTORY\".env.nonprod]"
print_toml "guardian_safe" "${GUARDIAN_SAFE_NONPROD:-NOT_COMPUTED}"
print_toml "admin_safe" "${ADMIN_SAFE_NONPROD:-NOT_COMPUTED}"
print_toml "org_factory" "${ORG_FACTORY_NONPROD:-NOT_COMPUTED}"
print_toml "whitelist_proxy" "${WHITELIST_PROXY_NONPROD:-NOT_COMPUTED}"
print_toml "guardian_safe_executor_module" "${GUARDIAN_MODULE_NONPROD:-NOT_COMPUTED}"
echo ""
echo "# Environment: prod"
echo "# Addresses that depend on the prod guardian/admin Safes"
echo "[factory.\"$FACTORY\".env.prod]"
print_toml "guardian_safe" "${GUARDIAN_SAFE_PROD:-NOT_COMPUTED}"
print_toml "admin_safe" "${ADMIN_SAFE_PROD:-NOT_COMPUTED}"
print_toml "org_factory" "${ORG_FACTORY_PROD:-NOT_COMPUTED}"
print_toml "whitelist_proxy" "${WHITELIST_PROXY_PROD:-NOT_COMPUTED}"
print_toml "guardian_safe_executor_module" "${GUARDIAN_MODULE_PROD:-NOT_COMPUTED}"

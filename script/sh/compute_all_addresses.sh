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
# Usage:
#   ./compute_all_addresses.sh <factory>
#
# Where <factory> is one of:
#   - arachnid     (0x4e59b44847b379578588920cA78FbF26c0B4956C)
#   - den-nonprod  (0xD13cb449d4f79C0D5A868a3D82e892d3d99b05f5)
#   - den-prod     (0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7)
#
# =============================================================================

set -e  # Stop on first error

# =============================================================================
# Configuration
# =============================================================================
ARACHNID_FACTORY_ADDRESS="0x4e59b44847b379578588920cA78FbF26c0B4956C"
DEN_NONPROD_FACTORY_ADDRESS="0xD13cb449d4f79C0D5A868a3D82e892d3d99b05f5"
DEN_PROD_FACTORY_ADDRESS="0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7"

# Library paths for --libraries flag
LIB_ORG_POLICY_PATH="src/organization/libraries/LibOrganizationPolicy.sol:LibOrganizationPolicy"
LIB_ORG_ADMIN_PATH="src/organization/libraries/LibOrganizationAdmin.sol:LibOrganizationAdmin"
LIB_ORG_INIT_PATH="src/organization/libraries/LibOrganizationInitialization.sol:LibOrganizationInitialization"
LIB_ORG_ACCOUNT_SIG_PATH="src/organization/libraries/LibOrganizationAccountSignature.sol:LibOrganizationAccountSignature"

# Executor EOA addresses (from DeploymentConfig.sol)
# Non-prod addresses (used for local/testnet)
GUARDIAN_EXECUTOR_ADDRESS="0x66FB51BF8C7a973a278578A2E381Fb5e89796DE1"
DEPLOYER_EXECUTOR_ADDRESS="0xBd7DF30E88C5C7fD54F2Ac77a1302581d577E0Fd"

# =============================================================================
# Argument Validation
# =============================================================================
FACTORY="$1"

if [[ -z "$FACTORY" ]]; then
    echo "Error: Factory argument required"
    echo "Usage: $0 <arachnid|den-nonprod|den-prod>"
    exit 1
fi

case "$FACTORY" in
    arachnid)
        FACTORY_ADDRESS="$ARACHNID_FACTORY_ADDRESS"
        ;;
    den-nonprod)
        FACTORY_ADDRESS="$DEN_NONPROD_FACTORY_ADDRESS"
        ;;
    den-prod)
        FACTORY_ADDRESS="$DEN_PROD_FACTORY_ADDRESS"
        ;;
    *)
        echo "Error: Invalid factory '$FACTORY'"
        echo "Usage: $0 <arachnid|den-nonprod|den-prod>"
        exit 1
        ;;
esac

# =============================================================================
# Helper Functions
# =============================================================================

# Extract an address from forge script output given a key pattern
# Usage: extract_address "output" "KeyName"
# Returns: address (0x...) or empty string if not found
extract_address() {
    local output="$1"
    local key="$2"
    # Match lines like "  KeyName: 0x..." or "  KeyName [STATUS]: 0x..."
    # Use grep -o to extract just the address part (more portable than sed with \s)
    echo "$output" | grep -E "^[[:space:]]+${key}([[:space:]]+\[.*\])?:[[:space:]]+0x[a-fA-F0-9]{40}" | head -1 | grep -oE "0x[a-fA-F0-9]{40}"
}

# Print a section header
print_header() {
    echo ""
    echo "================================================================================"
    echo "  $1"
    echo "================================================================================"
    echo ""
}

# Print a key-value pair aligned for easy copying
print_address() {
    local key="$1"
    local value="$2"
    printf "  %-45s = %s\n" "$key" "$value"
}

# =============================================================================
# Main Execution
# =============================================================================

print_header "CREATE2 Address Computation"
echo "  Factory: $FACTORY"
echo "  Factory Address: $FACTORY_ADDRESS"
echo ""

# -----------------------------------------------------------------------------
# Step 1: Compute Safe Infrastructure Addresses
# -----------------------------------------------------------------------------
echo "Computing Safe infrastructure addresses..."
SAFE_OUTPUT=$(FOUNDRY_PROFILE=safe forge script script/safe/DeploySafe.s.sol:DeploySafe \
    --sig "computeAddresses(address)" "$FACTORY_ADDRESS" --offline 2>&1) || {
    echo "Error: Failed to compute Safe addresses"
    echo "$SAFE_OUTPUT"
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
    echo "Error: Failed to extract Deployer Safe address from output"
    echo "$SAFE_OUTPUT"
    exit 1
fi

echo "  Done."

# -----------------------------------------------------------------------------
# Step 2: Compute Library Addresses
# -----------------------------------------------------------------------------
echo "Computing library addresses..."
LIB_OUTPUT=$(forge script script/DeployLibraries.s.sol:DeployLibraries \
    --sig "computeAddresses(address)" "$FACTORY_ADDRESS" --offline 2>&1) || {
    echo "Error: Failed to compute library addresses"
    echo "$LIB_OUTPUT"
    exit 1
}

# Extract library addresses
LIB_ORG_POLICY_ADDRESS=$(extract_address "$LIB_OUTPUT" "LibOrganizationPolicy")
LIB_ORG_ADMIN_ADDRESS=$(extract_address "$LIB_OUTPUT" "LibOrganizationAdmin")
LIB_ORG_INIT_ADDRESS=$(extract_address "$LIB_OUTPUT" "LibOrganizationInitialization")
LIB_ORG_ACCOUNT_SIG_ADDRESS=$(extract_address "$LIB_OUTPUT" "LibOrganizationAccountSignature")

# Verify we got all library addresses
if [[ -z "$LIB_ORG_POLICY_ADDRESS" || -z "$LIB_ORG_ADMIN_ADDRESS" || -z "$LIB_ORG_INIT_ADDRESS" || -z "$LIB_ORG_ACCOUNT_SIG_ADDRESS" ]]; then
    echo "Error: Failed to extract all library addresses from output"
    echo "$LIB_OUTPUT"
    exit 1
fi

echo "  Done."

# -----------------------------------------------------------------------------
# Step 3: Compute BatchedTransaction Address
# -----------------------------------------------------------------------------
echo "Computing BatchedTransaction address..."
BATCHED_OUTPUT=$(forge script script/safe-module/DeployBatchedTransaction.s.sol:DeployBatchedTransaction \
    --sig "computeAddress(address)" "$FACTORY_ADDRESS" --offline 2>&1) || {
    echo "Error: Failed to compute BatchedTransaction address"
    echo "$BATCHED_OUTPUT"
    exit 1
}

# Extract BatchedTransaction address
BATCHED_TRANSACTION_ADDRESS=$(extract_address "$BATCHED_OUTPUT" "BatchedTransaction")

if [[ -z "$BATCHED_TRANSACTION_ADDRESS" ]]; then
    echo "Error: Failed to extract BatchedTransaction address from output"
    echo "$BATCHED_OUTPUT"
    exit 1
fi

echo "  Done."

# -----------------------------------------------------------------------------
# Step 4: Compute Platform Contract Addresses
# -----------------------------------------------------------------------------
echo "Computing platform contract addresses (with dynamic library linking)..."

# Build --libraries flags using computed library addresses
LIBRARIES_FLAGS="--libraries ${LIB_ORG_POLICY_PATH}:${LIB_ORG_POLICY_ADDRESS}"
LIBRARIES_FLAGS="$LIBRARIES_FLAGS --libraries ${LIB_ORG_ADMIN_PATH}:${LIB_ORG_ADMIN_ADDRESS}"
LIBRARIES_FLAGS="$LIBRARIES_FLAGS --libraries ${LIB_ORG_INIT_PATH}:${LIB_ORG_INIT_ADDRESS}"
LIBRARIES_FLAGS="$LIBRARIES_FLAGS --libraries ${LIB_ORG_ACCOUNT_SIG_PATH}:${LIB_ORG_ACCOUNT_SIG_ADDRESS}"

# Run DeployContracts.computeAddresses with computed library addresses and deployer safe
CONTRACTS_OUTPUT=$(forge script script/DeployContracts.s.sol:DeployContracts \
    --sig "computeAddresses(address,address)" "$FACTORY_ADDRESS" "$DEPLOYER_SAFE_ADDRESS" \
    $LIBRARIES_FLAGS --offline 2>&1) || {
    echo "Error: Failed to compute platform contract addresses"
    echo "$CONTRACTS_OUTPUT"
    exit 1
}

# Extract platform contract addresses
WHITELIST_IMPL_ADDRESS=$(extract_address "$CONTRACTS_OUTPUT" "ImplementationWhitelistImplementation")
ORG_IMPL_ADDRESS=$(extract_address "$CONTRACTS_OUTPUT" "OrganizationImplementation")
ACCOUNT_IMPL_ADDRESS=$(extract_address "$CONTRACTS_OUTPUT" "AccountImplementation")
ORG_FACTORY_ADDRESS=$(extract_address "$CONTRACTS_OUTPUT" "OrganizationFactory")
WHITELIST_PROXY_ADDRESS=$(extract_address "$CONTRACTS_OUTPUT" "ImplementationWhitelistProxy")

echo "  Done."

# -----------------------------------------------------------------------------
# Step 5: Compute Safe Executor Module Addresses
# -----------------------------------------------------------------------------
echo "Computing Safe Executor Module addresses..."

# Guardian module - use the overloaded function that accepts Safe and BatchedTransaction addresses
# This ensures we use the computed addresses, not hardcoded ones from DeploymentConfig
GUARDIAN_MODULE_OUTPUT=$(forge script script/safe-module/DeploySafeExecutorModule.s.sol:DeploySafeExecutorModule \
    --sig "computeAddress(address,string,address,address,address)" \
    "$FACTORY_ADDRESS" "guardian" "$GUARDIAN_EXECUTOR_ADDRESS" "$GUARDIAN_SAFE_ADDRESS" "$BATCHED_TRANSACTION_ADDRESS" \
    --offline 2>&1) || {
    echo "Warning: Failed to compute Guardian module address (may need different executor address)"
}
GUARDIAN_MODULE_ADDRESS=$(extract_address "$GUARDIAN_MODULE_OUTPUT" "SafeExecutorModule")

# Deployer module - use the overloaded function that accepts Safe and BatchedTransaction addresses
DEPLOYER_MODULE_OUTPUT=$(forge script script/safe-module/DeploySafeExecutorModule.s.sol:DeploySafeExecutorModule \
    --sig "computeAddress(address,string,address,address,address)" \
    "$FACTORY_ADDRESS" "deployer" "$DEPLOYER_EXECUTOR_ADDRESS" "$DEPLOYER_SAFE_ADDRESS" "$BATCHED_TRANSACTION_ADDRESS" \
    --offline 2>&1) || {
    echo "Warning: Failed to compute Deployer module address (may need different executor address)"
}
DEPLOYER_MODULE_ADDRESS=$(extract_address "$DEPLOYER_MODULE_OUTPUT" "SafeExecutorModule")

echo "  Done."

# =============================================================================
# Output Results
# =============================================================================

print_header "Computed Addresses for $FACTORY ($FACTORY_ADDRESS)"

echo "--- Safe 1.3.0 Infrastructure ---"
print_address "SAFE_SINGLETON_ADDRESS" "${SAFE_SINGLETON_ADDRESS:-NOT_COMPUTED}"
print_address "SAFE_PROXY_FACTORY_ADDRESS" "${SAFE_PROXY_FACTORY_ADDRESS:-NOT_COMPUTED}"
print_address "SAFE_FALLBACK_HANDLER_ADDRESS" "${SAFE_FALLBACK_HANDLER_ADDRESS:-NOT_COMPUTED}"
print_address "SAFE_MULTISEND_ADDRESS" "${SAFE_MULTISEND_ADDRESS:-NOT_COMPUTED}"
print_address "SAFE_MULTISEND_CALL_ONLY_ADDRESS" "${SAFE_MULTISEND_CALL_ONLY_ADDRESS:-NOT_COMPUTED}"
print_address "SAFE_CREATE_CALL_ADDRESS" "${SAFE_CREATE_CALL_ADDRESS:-NOT_COMPUTED}"
print_address "SAFE_SIMULATE_TX_ACCESSOR_ADDRESS" "${SAFE_SIMULATE_TX_ACCESSOR_ADDRESS:-NOT_COMPUTED}"
print_address "GUARDIAN_SAFE_ADDRESS" "${GUARDIAN_SAFE_ADDRESS:-NOT_COMPUTED}"
print_address "DEPLOYER_SAFE_ADDRESS" "${DEPLOYER_SAFE_ADDRESS:-NOT_COMPUTED}"
echo ""

echo "--- Platform Libraries ---"
print_address "LIB_ORG_POLICY_ADDRESS" "${LIB_ORG_POLICY_ADDRESS:-NOT_COMPUTED}"
print_address "LIB_ORG_ADMIN_ADDRESS" "${LIB_ORG_ADMIN_ADDRESS:-NOT_COMPUTED}"
print_address "LIB_ORG_INIT_ADDRESS" "${LIB_ORG_INIT_ADDRESS:-NOT_COMPUTED}"
print_address "LIB_ORG_ACCOUNT_SIG_ADDRESS" "${LIB_ORG_ACCOUNT_SIG_ADDRESS:-NOT_COMPUTED}"
echo ""

echo "--- Platform Contracts ---"
print_address "WHITELIST_IMPL_ADDRESS" "${WHITELIST_IMPL_ADDRESS:-NOT_COMPUTED}"
print_address "ORG_IMPL_ADDRESS" "${ORG_IMPL_ADDRESS:-NOT_COMPUTED}"
print_address "ACCOUNT_IMPL_ADDRESS" "${ACCOUNT_IMPL_ADDRESS:-NOT_COMPUTED}"
print_address "ORG_FACTORY_ADDRESS" "${ORG_FACTORY_ADDRESS:-NOT_COMPUTED}"
print_address "WHITELIST_PROXY_ADDRESS" "${WHITELIST_PROXY_ADDRESS:-NOT_COMPUTED}"
echo ""

echo "--- BatchedTransaction ---"
print_address "BATCHED_TRANSACTION_ADDRESS" "${BATCHED_TRANSACTION_ADDRESS:-NOT_COMPUTED}"
echo ""

echo "--- Safe Executor Modules ---"
print_address "GUARDIAN_MODULE_ADDRESS" "${GUARDIAN_MODULE_ADDRESS:-NOT_COMPUTED}"
print_address "DEPLOYER_MODULE_ADDRESS" "${DEPLOYER_MODULE_ADDRESS:-NOT_COMPUTED}"
echo ""

echo "================================================================================"
echo "  Done!"
echo "================================================================================"

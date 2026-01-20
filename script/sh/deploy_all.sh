#!/usr/bin/env bash
# ==============================================================================
# deploy_all.sh - Deploy the Den Multi-layer Security (MLS) Wallet Platform
# ==============================================================================
#
# This script deploys all platform contracts deterministically using CREATE2.
# It follows a 4-step deployment process:
#
#   Step 1: Deploy Arachnid Factory (if not already deployed)
#   Step 2: Deploy Safe Singleton Factory (only if Arachnid failed/unavailable)
#   Step 3: Deploy platform libraries via CREATE2
#   Step 4: Deploy all contracts with library linking
#
# USAGE:
#   ./script/sh/deploy_all.sh [OPTIONS]
#
# REQUIRED ENVIRONMENT VARIABLES:
#   PRIVATE_KEY       - Deployer EOA private key (use env var, NEVER CLI arg)
#   RPC_URL           - Target chain RPC endpoint
#
# OPTIONAL ENVIRONMENT VARIABLES:
#   CREATE2_FACTORY_ADDRESS - Override auto-detected factory (skips steps 1-2)
#   CHAIN_ID          - Override auto-detected chain ID (for broadcast dir lookup)
#   ETHERSCAN_API_KEY - For contract verification
#   VERIFY            - Set to "true" to enable contract verification
#   DRY_RUN           - Set to "true" to simulate without broadcasting
#   CONFIRM_DEPLOYMENT - Set to "true" to enable factory deployment
#
# EXAMPLES:
#   # Standard deployment (auto-detects or deploys factory)
#   PRIVATE_KEY=$KEY RPC_URL=$RPC CONFIRM_DEPLOYMENT=true ./script/sh/deploy_all.sh
#
#   # Dry run (no broadcast)
#   PRIVATE_KEY=$KEY RPC_URL=$RPC DRY_RUN=true ./script/sh/deploy_all.sh
#
#   # With pre-existing factory (skips factory deployment)
#   PRIVATE_KEY=$KEY RPC_URL=$RPC CREATE2_FACTORY_ADDRESS=0x4e59... ./script/sh/deploy_all.sh
#
#   # With verification
#   PRIVATE_KEY=$KEY RPC_URL=$RPC ETHERSCAN_API_KEY=$API VERIFY=true ./script/sh/deploy_all.sh
#
# ==============================================================================

# ------------------------------------------------------------------------------
# STRICT MODE - Fail loudly on any error
# ------------------------------------------------------------------------------
# -e: Exit immediately if a command exits with non-zero status
# -u: Treat unset variables as an error
# -o pipefail: Pipeline fails if any command in it fails
set -euo pipefail

# ------------------------------------------------------------------------------
# CONSTANTS
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BROADCAST_DIR="${PROJECT_ROOT}/broadcast"

# Factory addresses (must match DeploymentConfig.sol)
ARACHNID_FACTORY_ADDRESS="0x4e59b44847b379578588920cA78FbF26c0B4956C"
SAFE_SINGLETON_FACTORY_ADDRESS="0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7"

# Library paths (must match DeploymentConfig.sol)
LIB_POLICY_PATH="src/organization/libraries/LibOrganizationPolicy.sol:LibOrganizationPolicy"
LIB_ADMIN_PATH="src/organization/libraries/LibOrganizationAdmin.sol:LibOrganizationAdmin"
LIB_INIT_PATH="src/organization/libraries/LibOrganizationInitialization.sol:LibOrganizationInitialization"
LIB_ACC_SIG_PATH="src/organization/libraries/LibOrganizationAccountSignature.sol:LibOrganizationAccountSignature"

# Contract names as they appear in broadcast JSON
LIB_POLICY_NAME="LibOrganizationPolicy"
LIB_ADMIN_NAME="LibOrganizationAdmin"
LIB_INIT_NAME="LibOrganizationInitialization"
LIB_ACC_SIG_NAME="LibOrganizationAccountSignature"

# ------------------------------------------------------------------------------
# COLORS (for terminal output)
# ------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ------------------------------------------------------------------------------
# LOGGING FUNCTIONS
# ------------------------------------------------------------------------------
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_section() {
    echo ""
    echo "================================================================================"
    echo "  $1"
    echo "================================================================================"
    echo ""
}

# ------------------------------------------------------------------------------
# VALIDATION FUNCTIONS
# ------------------------------------------------------------------------------
validate_environment() {
    log_section "Validating Environment"
    
    local missing_vars=()
    
    # Check required environment variables
    if [[ -z "${PRIVATE_KEY:-}" ]]; then
        missing_vars+=("PRIVATE_KEY")
    fi
    
    if [[ -z "${RPC_URL:-}" ]]; then
        missing_vars+=("RPC_URL")
    fi
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables:"
        for var in "${missing_vars[@]}"; do
            log_error "  - $var"
        done
        log_error ""
        log_error "Set these variables before running:"
        log_error "  export PRIVATE_KEY=<your-private-key>"
        log_error "  export RPC_URL=<your-rpc-url>"
        exit 1
    fi
    
    # Security check: Ensure PRIVATE_KEY is not exposed in command line
    if [[ "${PRIVATE_KEY}" == *" "* ]]; then
        log_error "PRIVATE_KEY appears to contain spaces. Ensure it's set correctly."
        exit 1
    fi
    
    # Validate we're in the project root
    if [[ ! -f "${PROJECT_ROOT}/foundry.toml" ]]; then
        log_error "Cannot find foundry.toml. Run this script from the project root."
        exit 1
    fi
    
    # Check for required tools
    if ! command -v forge &> /dev/null; then
        log_error "forge (Foundry) is not installed. Install from https://getfoundry.sh"
        exit 1
    fi
    
    if ! command -v cast &> /dev/null; then
        log_error "cast (Foundry) is not installed. Install from https://getfoundry.sh"
        exit 1
    fi
    
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Install via: brew install jq (macOS) or apt install jq (Linux)"
        exit 1
    fi
    
    log_success "Environment validation passed"
}

# ------------------------------------------------------------------------------
# CHAIN ID DETECTION
# ------------------------------------------------------------------------------
get_chain_id() {
    if [[ -n "${CHAIN_ID:-}" ]]; then
        echo "${CHAIN_ID}"
        return
    fi
    
    # Query chain ID from RPC
    local chain_id
    chain_id=$(cast chain-id --rpc-url "${RPC_URL}" 2>/dev/null || echo "")
    
    if [[ -z "${chain_id}" ]]; then
        log_error "Failed to get chain ID from RPC. Set CHAIN_ID manually or check RPC_URL."
        exit 1
    fi
    
    echo "${chain_id}"
}

# ------------------------------------------------------------------------------
# CONTRACT EXISTENCE CHECK
# ------------------------------------------------------------------------------
is_contract_deployed() {
    local address="$1"
    local code
    code=$(cast code "${address}" --rpc-url "${RPC_URL}" 2>/dev/null || echo "0x")
    
    # Check if there's code at the address (more than just "0x")
    if [[ "${code}" != "0x" && -n "${code}" ]]; then
        return 0  # true - contract exists
    else
        return 1  # false - no contract
    fi
}

# ------------------------------------------------------------------------------
# BROADCAST JSON PARSING
# ------------------------------------------------------------------------------
# Extracts a deployed contract address from Foundry's broadcast JSON
# Uses jq to parse the JSON (more reliable than grep/sed)
get_deployed_address() {
    local json_file="$1"
    local contract_name="$2"
    
    if [[ ! -f "${json_file}" ]]; then
        log_error "Broadcast file not found: ${json_file}"
        exit 1
    fi
    
    # Parse the broadcast JSON to find the contract deployment
    # The JSON structure has transactions[] with contractName and contractAddress
    local address
    address=$(jq -r --arg name "${contract_name}" \
        '.transactions[] | select(.contractName == $name) | .contractAddress' \
        "${json_file}" 2>/dev/null | head -1)
    
    if [[ -z "${address}" || "${address}" == "null" ]]; then
        log_error "Could not find deployed address for ${contract_name} in ${json_file}"
        exit 1
    fi
    
    echo "${address}"
}

# ------------------------------------------------------------------------------
# BUILD FLAGS
# ------------------------------------------------------------------------------
build_forge_flags() {
    local flags=()
    
    flags+=("--rpc-url" "${RPC_URL}")
    
    # Add broadcast flag unless dry run
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        flags+=("--broadcast")
    else
        log_warn "DRY_RUN mode: Transactions will NOT be broadcast"
    fi
    
    # Add verification if requested
    if [[ "${VERIFY:-false}" == "true" ]]; then
        if [[ -z "${ETHERSCAN_API_KEY:-}" ]]; then
            log_warn "VERIFY=true but ETHERSCAN_API_KEY not set. Skipping verification."
        else
            flags+=("--verify")
        fi
    fi
    
    # Verbose output
    flags+=("-vvvv")
    
    echo "${flags[@]}"
}

# ------------------------------------------------------------------------------
# STEP 1: DEPLOY/DETECT CREATE2 FACTORY
# ------------------------------------------------------------------------------
ensure_create2_factory() {
    log_section "Step 1: Ensuring CREATE2 Factory is Available"
    
    # If CREATE2_FACTORY_ADDRESS is already set, verify it exists
    if [[ -n "${CREATE2_FACTORY_ADDRESS:-}" ]]; then
        log_info "CREATE2_FACTORY_ADDRESS provided: ${CREATE2_FACTORY_ADDRESS}"
        if is_contract_deployed "${CREATE2_FACTORY_ADDRESS}"; then
            log_success "Factory verified at ${CREATE2_FACTORY_ADDRESS}"
            return 0
        else
            log_error "No contract found at provided CREATE2_FACTORY_ADDRESS: ${CREATE2_FACTORY_ADDRESS}"
            exit 1
        fi
    fi
    
    # Check if Arachnid factory already exists
    log_info "Checking for Arachnid factory at ${ARACHNID_FACTORY_ADDRESS}..."
    if is_contract_deployed "${ARACHNID_FACTORY_ADDRESS}"; then
        log_success "Arachnid factory already deployed"
        export CREATE2_FACTORY_ADDRESS="${ARACHNID_FACTORY_ADDRESS}"
        return 0
    fi
    
    # Check if Safe Singleton factory already exists
    log_info "Checking for Safe Singleton factory at ${SAFE_SINGLETON_FACTORY_ADDRESS}..."
    if is_contract_deployed "${SAFE_SINGLETON_FACTORY_ADDRESS}"; then
        log_success "Safe Singleton factory already deployed"
        export CREATE2_FACTORY_ADDRESS="${SAFE_SINGLETON_FACTORY_ADDRESS}"
        return 0
    fi
    
    # No factory found - need to deploy one
    log_warn "No CREATE2 factory found on this chain"
    
    # Check if deployment is confirmed
    if [[ "${CONFIRM_DEPLOYMENT:-false}" != "true" ]]; then
        log_error "Factory deployment requires CONFIRM_DEPLOYMENT=true"
        log_error "Re-run with: CONFIRM_DEPLOYMENT=true ./script/sh/deploy_all.sh"
        exit 1
    fi
    
    # Try to deploy Arachnid factory first
    log_info "Attempting to deploy Arachnid factory..."
    if deploy_arachnid_factory; then
        export CREATE2_FACTORY_ADDRESS="${ARACHNID_FACTORY_ADDRESS}"
        return 0
    fi
    
    # Arachnid failed (likely EIP-155 chain), try Safe Singleton
    log_warn "Arachnid deployment failed (chain may enforce EIP-155)"
    log_info "Attempting to deploy Safe Singleton factory..."
    
    if deploy_safe_singleton_factory; then
        export CREATE2_FACTORY_ADDRESS="${SAFE_SINGLETON_FACTORY_ADDRESS}"
        return 0
    fi
    
    log_error "Failed to deploy any CREATE2 factory"
    log_error "You may need to manually deploy and set CREATE2_FACTORY_ADDRESS"
    exit 1
}

# ------------------------------------------------------------------------------
# DEPLOY ARACHNID FACTORY
# ------------------------------------------------------------------------------
deploy_arachnid_factory() {
    log_info "Running DeployArachnidFactory.s.sol..."
    
    # Run the Arachnid factory deployment script
    # Note: This uses a pre-signed transaction and may fail on EIP-155 chains
    if CONFIRM_DEPLOYMENT=true forge script script/DeployArachnidFactory.s.sol:DeployArachnidFactory \
        --rpc-url "${RPC_URL}" \
        --broadcast \
        -vvvv 2>&1; then
        
        # Verify deployment
        if is_contract_deployed "${ARACHNID_FACTORY_ADDRESS}"; then
            log_success "Arachnid factory deployed at ${ARACHNID_FACTORY_ADDRESS}"
            return 0
        fi
    fi
    
    return 1
}

# ------------------------------------------------------------------------------
# DEPLOY SAFE SINGLETON FACTORY
# ------------------------------------------------------------------------------
deploy_safe_singleton_factory() {
    # Check if SAFE_FACTORY_DEPLOYER_PRIVATE_KEY is set
    if [[ -z "${SAFE_FACTORY_DEPLOYER_PRIVATE_KEY:-}" ]]; then
        log_error "SAFE_FACTORY_DEPLOYER_PRIVATE_KEY not set"
        log_error "This is required to deploy the Safe Singleton factory"
        log_error "The deployer must have nonce 0 at address 0xE1CB04A0fA36DdD16a06ea828007E35e1a3cBC37"
        return 1
    fi
    
    log_info "Running DeploySafeSingletonFactory.s.sol..."
    
    # Run the Safe Singleton factory deployment script
    if CONFIRM_DEPLOYMENT=true forge script script/DeploySafeSingletonFactory.s.sol:DeploySafeSingletonFactory \
        --rpc-url "${RPC_URL}" \
        --broadcast \
        -vvvv 2>&1; then
        
        # Verify deployment
        if is_contract_deployed "${SAFE_SINGLETON_FACTORY_ADDRESS}"; then
            log_success "Safe Singleton factory deployed at ${SAFE_SINGLETON_FACTORY_ADDRESS}"
            return 0
        fi
    fi
    
    return 1
}

# ------------------------------------------------------------------------------
# STEP 3: DEPLOY LIBRARIES
# ------------------------------------------------------------------------------
deploy_libraries() {
    log_section "Step 3: Deploying Platform Libraries"
    
    log_info "Using CREATE2 factory: ${CREATE2_FACTORY_ADDRESS}"
    log_info "Running DeployLibraries.s.sol..."
    
    local forge_flags
    forge_flags=$(build_forge_flags)
    
    # Run the library deployment script with factory address
    # shellcheck disable=SC2086
    CREATE2_FACTORY_ADDRESS="${CREATE2_FACTORY_ADDRESS}" \
    forge script script/DeployLibraries.s.sol:DeployLibraries \
        ${forge_flags}
    
    log_success "Library deployment complete"
}

# ------------------------------------------------------------------------------
# STEP 4: DEPLOY CONTRACTS WITH LIBRARY LINKING
# ------------------------------------------------------------------------------
deploy_contracts() {
    local lib_policy_addr="$1"
    local lib_admin_addr="$2"
    local lib_init_addr="$3"
    local lib_acc_sig_addr="$4"
    
    log_section "Step 4: Deploying Contracts with Library Linking"
    
    log_info "Using CREATE2 factory: ${CREATE2_FACTORY_ADDRESS}"
    log_info "Library addresses for linking:"
    log_info "  LibOrganizationPolicy:           ${lib_policy_addr}"
    log_info "  LibOrganizationAdmin:            ${lib_admin_addr}"
    log_info "  LibOrganizationInitialization:   ${lib_init_addr}"
    log_info "  LibOrganizationAccountSignature: ${lib_acc_sig_addr}"
    echo ""
    
    local forge_flags
    forge_flags=$(build_forge_flags)
    
    # Run the contracts deployment script with library linking
    # shellcheck disable=SC2086
    CREATE2_FACTORY_ADDRESS="${CREATE2_FACTORY_ADDRESS}" \
    forge script script/DeployContracts.s.sol:DeployContracts \
        ${forge_flags} \
        --libraries "${LIB_POLICY_PATH}:${lib_policy_addr}" \
        --libraries "${LIB_ADMIN_PATH}:${lib_admin_addr}" \
        --libraries "${LIB_INIT_PATH}:${lib_init_addr}" \
        --libraries "${LIB_ACC_SIG_PATH}:${lib_acc_sig_addr}"
    
    log_success "Contract deployment complete"
}

# ------------------------------------------------------------------------------
# MAIN EXECUTION
# ------------------------------------------------------------------------------
main() {
    log_section "Den Multi-layer Security (MLS) Wallet Platform Deployment"
    
    log_info "Project root: ${PROJECT_ROOT}"
    log_info "Script started at: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    
    # Validate environment
    validate_environment
    
    # Get chain ID for broadcast directory lookup
    local chain_id
    chain_id=$(get_chain_id)
    log_info "Target chain ID: ${chain_id}"
    
    # Step 1 & 2: Ensure CREATE2 factory is available
    ensure_create2_factory
    log_info "CREATE2_FACTORY_ADDRESS set to: ${CREATE2_FACTORY_ADDRESS}"
    
    # Step 3: Deploy libraries
    deploy_libraries
    
    # Extract library addresses from broadcast JSON
    log_section "Extracting Library Addresses from Broadcast"
    
    local broadcast_file="${BROADCAST_DIR}/DeployLibraries.s.sol/${chain_id}/run-latest.json"
    
    if [[ ! -f "${broadcast_file}" ]]; then
        log_error "Broadcast file not found: ${broadcast_file}"
        log_error "This may indicate the library deployment failed or DRY_RUN was enabled."
        exit 1
    fi
    
    log_info "Reading from: ${broadcast_file}"
    
    local lib_policy_addr lib_admin_addr lib_init_addr lib_acc_sig_addr
    lib_policy_addr=$(get_deployed_address "${broadcast_file}" "${LIB_POLICY_NAME}")
    lib_admin_addr=$(get_deployed_address "${broadcast_file}" "${LIB_ADMIN_NAME}")
    lib_init_addr=$(get_deployed_address "${broadcast_file}" "${LIB_INIT_NAME}")
    lib_acc_sig_addr=$(get_deployed_address "${broadcast_file}" "${LIB_ACC_SIG_NAME}")
    
    log_success "Extracted all library addresses"
    
    # Step 4: Deploy contracts with library linking
    deploy_contracts "${lib_policy_addr}" "${lib_admin_addr}" "${lib_init_addr}" "${lib_acc_sig_addr}"
    
    # Summary
    log_section "Deployment Complete"
    
    log_success "All contracts deployed successfully!"
    log_info ""
    log_info "CREATE2 Factory used: ${CREATE2_FACTORY_ADDRESS}"
    log_info ""
    log_info "Deployed library addresses (save these for verification):"
    log_info "  LibOrganizationPolicy:           ${lib_policy_addr}"
    log_info "  LibOrganizationAdmin:            ${lib_admin_addr}"
    log_info "  LibOrganizationInitialization:   ${lib_init_addr}"
    log_info "  LibOrganizationAccountSignature: ${lib_acc_sig_addr}"
    log_info ""
    log_info "Full deployment artifacts available at:"
    log_info "  ${BROADCAST_DIR}/DeployLibraries.s.sol/${chain_id}/"
    log_info "  ${BROADCAST_DIR}/DeployContracts.s.sol/${chain_id}/"
    log_info ""
    log_info "Finished at: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
}

# Run main function
main "$@"

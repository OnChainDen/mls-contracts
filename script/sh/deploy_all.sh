#!/usr/bin/env bash
# ==============================================================================
# deploy_all.sh - Deploy the Den Onchain Custody Platform
# ==============================================================================
#
# This script deploys all platform contracts deterministically using CREATE2.
# It handles the two-phase deployment required for deterministic library linking.
#
# USAGE:
#   ./script/sh/deploy_all.sh [OPTIONS]
#
# REQUIRED ENVIRONMENT VARIABLES:
#   PRIVATE_KEY       - Deployer EOA private key (use env var, NEVER CLI arg)
#   RPC_URL           - Target chain RPC endpoint
#
# OPTIONAL ENVIRONMENT VARIABLES:
#   CHAIN_ID          - Override auto-detected chain ID (for broadcast dir lookup)
#   ETHERSCAN_API_KEY - For contract verification
#   VERIFY            - Set to "true" to enable contract verification
#   DRY_RUN           - Set to "true" to simulate without broadcasting
#
# EXAMPLES:
#   # Standard deployment
#   PRIVATE_KEY=$KEY RPC_URL=$RPC ./script/sh/deploy_all.sh
#
#   # Dry run (no broadcast)
#   PRIVATE_KEY=$KEY RPC_URL=$RPC DRY_RUN=true ./script/sh/deploy_all.sh
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
# PHASE 1: DEPLOY LIBRARIES
# ------------------------------------------------------------------------------
deploy_libraries() {
    log_section "Phase 1: Deploying Platform Libraries"
    
    log_info "Deploying libraries via CREATE2 for deterministic addresses..."
    
    local forge_flags
    forge_flags=$(build_forge_flags)
    
    # Run the library deployment
    # shellcheck disable=SC2086
    forge script script/DeployPlatform.s.sol:DeployPlatform \
        --sig "deployLibraries()" \
        ${forge_flags}
    
    log_success "Library deployment complete"
}

# ------------------------------------------------------------------------------
# PHASE 2: DEPLOY PLATFORM WITH LIBRARY LINKING
# ------------------------------------------------------------------------------
deploy_platform() {
    local lib_policy_addr="$1"
    local lib_admin_addr="$2"
    local lib_init_addr="$3"
    local lib_acc_sig_addr="$4"
    
    log_section "Phase 2: Deploying Platform with Library Linking"
    
    log_info "Library addresses for linking:"
    log_info "  LibOrganizationPolicy:          ${lib_policy_addr}"
    log_info "  LibOrganizationAdmin:           ${lib_admin_addr}"
    log_info "  LibOrganizationInitialization:  ${lib_init_addr}"
    log_info "  LibOrganizationAccountSignature: ${lib_acc_sig_addr}"
    echo ""
    
    local forge_flags
    forge_flags=$(build_forge_flags)
    
    # Run the full deployment with library linking
    # shellcheck disable=SC2086
    forge script script/DeployPlatform.s.sol:DeployPlatform \
        ${forge_flags} \
        --libraries "${LIB_POLICY_PATH}:${lib_policy_addr}" \
        --libraries "${LIB_ADMIN_PATH}:${lib_admin_addr}" \
        --libraries "${LIB_INIT_PATH}:${lib_init_addr}" \
        --libraries "${LIB_ACC_SIG_PATH}:${lib_acc_sig_addr}"
    
    log_success "Platform deployment complete"
}

# ------------------------------------------------------------------------------
# MAIN EXECUTION
# ------------------------------------------------------------------------------
main() {
    log_section "Den Onchain Custody Platform Deployment"
    
    log_info "Project root: ${PROJECT_ROOT}"
    log_info "Script started at: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    
    # Step 1: Validate environment
    validate_environment
    
    # Step 2: Get chain ID for broadcast directory lookup
    local chain_id
    chain_id=$(get_chain_id)
    log_info "Target chain ID: ${chain_id}"
    
    # Step 3: Deploy libraries (Phase 1)
    deploy_libraries
    
    # Step 4: Extract library addresses from broadcast JSON
    log_section "Extracting Library Addresses from Broadcast"
    
    local broadcast_file="${BROADCAST_DIR}/DeployPlatform.s.sol/${chain_id}/run-latest.json"
    
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
    
    # Step 5: Deploy platform with library linking (Phase 2)
    deploy_platform "${lib_policy_addr}" "${lib_admin_addr}" "${lib_init_addr}" "${lib_acc_sig_addr}"
    
    # Step 6: Summary
    log_section "Deployment Complete"
    
    log_success "All contracts deployed successfully!"
    log_info ""
    log_info "Deployed library addresses (save these for verification):"
    log_info "  LibOrganizationPolicy:          ${lib_policy_addr}"
    log_info "  LibOrganizationAdmin:           ${lib_admin_addr}"
    log_info "  LibOrganizationInitialization:  ${lib_init_addr}"
    log_info "  LibOrganizationAccountSignature: ${lib_acc_sig_addr}"
    log_info ""
    log_info "Full deployment artifacts available at:"
    log_info "  ${BROADCAST_DIR}/DeployPlatform.s.sol/${chain_id}/"
    log_info ""
    log_info "Finished at: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
}

# Run main function
main "$@"

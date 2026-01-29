#!/bin/bash
# =============================================================================
# Local End-to-End Deployment Test Script
# =============================================================================
# Runs the full deployment flow on a local Anvil instance for testing during development
#
# Usage:
#   ./test_deploy_scripts_locally.sh arachnid      # Test Arachnid factory flow
#   ./test_deploy_scripts_locally.sh den-nonprod   # Test Den non-prod factory flow
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

# For this script, only arachnid and den-nonprod are valid (local testing)
if [[ -z "$FACTORY" ]]; then
    echo "Error: Factory argument required"
    echo "Usage: $0 <arachnid|den-nonprod>"
    exit 1
fi

if [[ "$FACTORY" != "arachnid" && "$FACTORY" != "den-nonprod" ]]; then
    echo "Error: Invalid factory '$FACTORY'"
    echo "Usage: $0 <arachnid|den-nonprod>"
    echo "  arachnid    - Test deployment via Arachnid Deterministic Deployer"
    echo "  den-nonprod - Test deployment via Den Non-Production Singleton Factory"
    exit 1
fi

# =============================================================================
# Account Configuration
# =============================================================================
# Foundry managed accounts and their addresses:
#   test-deployer              - 0x901cab5fdb93571f0f6cd6d643f8b2532f00d2a3 (default for deployments)
#   test-den-factory-deployer  - (read from deployment.toml factory_deployer)
#   test-guardian-safe-owner   - (read from deployment.toml)
#   test-admin-safe-owner      - (read from deployment.toml)
#   test-guardian-executor     - (read from deployment.toml)

PORT="8545"
RPC_URL="http://127.0.0.1:$PORT"

# Account names
DEPLOYER_ACCOUNT="test-deployer"
DEN_FACTORY_DEPLOYER_ACCOUNT="test-den-factory-deployer"
GUARDIAN_SAFE_OWNER_ACCOUNT="test-guardian-safe-owner"

# EOA addresses - some hardcoded (foundry test accounts), some from deployment.toml
DEPLOYER_ADDRESS="0x901cab5fdb93571f0f6cd6d643f8b2532f00d2a3"
DEN_FACTORY_DEPLOYER_ADDRESS=$(get_factory_deployer "den-nonprod")

# Read Safe owner and executor addresses from deployment.toml (nonprod)
# Note: get_* functions exit with error if value not found, so no need for separate validation
GUARDIAN_SAFE_OWNER_ADDRESS=$(get_guardian_safe_owner "nonprod")
ADMIN_SAFE_OWNER_ADDRESS=$(get_admin_safe_owner "nonprod")
GUARDIAN_EXECUTOR_ADDRESS=$(get_guardian_executor "nonprod")

echo "============================================================================="
echo "Local Deployment Test: $FACTORY"
echo "============================================================================="
echo "  RPC URL: $RPC_URL"
echo "  Deployer Account: $DEPLOYER_ACCOUNT ($DEPLOYER_ADDRESS)"
echo "  Guardian Safe Owner: $GUARDIAN_SAFE_OWNER_ADDRESS"
echo "  Admin Safe Owner: $ADMIN_SAFE_OWNER_ADDRESS"
echo "  Guardian Executor: $GUARDIAN_EXECUTOR_ADDRESS"
echo "============================================================================="

# =============================================================================
# Step 1: Start Anvil
# =============================================================================
echo ""
echo "[Step 1] Starting Anvil..."
pkill anvil || true  # Kill any existing Anvil instances (ignore error if none running)

# Start Anvil without the default CREATE2 deployer so we can deploy our own
anvil --disable-default-create2-deployer -p $PORT &
ANVIL_PID=$!

# Wait for Anvil to start
sleep 5

echo "  Anvil started (PID: $ANVIL_PID)"

# =============================================================================
# Step 2: Fund EOAs
# =============================================================================
echo ""
echo "[Step 2] Funding EOAs..."

# Fund all test accounts with max balance
for addr in $DEPLOYER_ADDRESS $DEN_FACTORY_DEPLOYER_ADDRESS $GUARDIAN_SAFE_OWNER_ADDRESS $ADMIN_SAFE_OWNER_ADDRESS $GUARDIAN_EXECUTOR_ADDRESS; do
    cast rpc anvil_setBalance $addr 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff --rpc-url $RPC_URL
    echo "  Funded $addr"
done

# =============================================================================
# Step 3: Deploy CREATE2 Factory
# =============================================================================
echo ""
echo "[Step 3] Deploying CREATE2 Factory ($FACTORY)..."

if [[ "$FACTORY" == "arachnid" ]]; then
    # Arachnid factory uses a pre-signed keyless transaction
    # We need to fund the Arachnid deployer address first
    make fund-arachnid-deployer ACCOUNT=$DEPLOYER_ACCOUNT
    make deploy-arachnid-factory ACCOUNT=$DEPLOYER_ACCOUNT
else
    # Den non-prod factory is deployed by the Den factory deployer account
    make deploy-den-factory ACCOUNT=$DEN_FACTORY_DEPLOYER_ACCOUNT
fi

# =============================================================================
# Step 4: Deploy Safe Infrastructure and Multisigs
# =============================================================================
echo ""
echo "[Step 4] Deploying Safe 1.3.0 infrastructure and multisigs..."
make deploy-safe ACCOUNT=$DEPLOYER_ACCOUNT FACTORY=$FACTORY

# =============================================================================
# Step 5: Deploy Platform Libraries (in two stages)
# =============================================================================
# Libraries must be deployed in two stages due to inter-library dependencies:
#   Stage 1 (independent): Policy and Admin (no dependencies on other libs)
#   Stage 2 (dependent): Init and AccountSig (depend on Policy/Admin being linked)
echo ""
echo "[Step 5a] Deploying independent libraries (Policy, Admin)..."
make deploy-independent-libs ACCOUNT=$DEPLOYER_ACCOUNT FACTORY=$FACTORY

echo ""
echo "[Step 5b] Deploying dependent libraries (Init, AccountSig)..."
make deploy-dependent-libs ACCOUNT=$DEPLOYER_ACCOUNT FACTORY=$FACTORY

# =============================================================================
# Step 6: Deploy Platform Contracts
# =============================================================================
echo ""
echo "[Step 6] Deploying platform contracts..."
make deploy-contracts ACCOUNT=$DEPLOYER_ACCOUNT FACTORY=$FACTORY

# =============================================================================
# Step 6.5: Deploy BatchedTransaction
# =============================================================================
echo ""
echo "[Step 6.5] Deploying BatchedTransaction..."
make deploy-batched-transaction ACCOUNT=$DEPLOYER_ACCOUNT FACTORY=$FACTORY

# =============================================================================
# Step 7: Deploy Guardian Safe Executor Module
# =============================================================================
echo ""
echo "[Step 7] Deploying Guardian Safe Executor Module..."

echo "  Deploying Guardian Safe Executor Module (executor: $GUARDIAN_EXECUTOR_ADDRESS)..."
make deploy-guardian-safe-module EXECUTOR=$GUARDIAN_EXECUTOR_ADDRESS ACCOUNT=$DEPLOYER_ACCOUNT FACTORY=$FACTORY

# =============================================================================
# Step 8: Add Module to Guardian Safe (Local Testing Only)
# =============================================================================
echo ""
echo "[Step 8] Adding module to Guardian Safe..."
echo "  Note: This requires Guardian Safe owner signatures. Using the Guardian Safe owner account."

# Add module to Guardian Safe (using Guardian Safe owner account)
echo "  Adding module to Guardian Safe..."
make guardian-safe-add-module ACCOUNT=$GUARDIAN_SAFE_OWNER_ACCOUNT FACTORY=$FACTORY EXECUTE=true || {
    echo "  Warning: Failed to add module to Guardian Safe (may need multi-sig approval)"
}

# =============================================================================
# Done!
# =============================================================================
echo ""
echo "============================================================================="
echo "Deployment Complete!"
echo "============================================================================="
echo "  Factory: $FACTORY"
echo "  All contracts deployed successfully on local Anvil."
echo ""
echo "  Anvil is still running (PID: $ANVIL_PID)"
echo "  To stop: pkill anvil"
echo "============================================================================="

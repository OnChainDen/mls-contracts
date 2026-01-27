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
# Requirements:
#   - yq (for reading deployment.toml)
#
# =============================================================================

set -e  # Stop on first error

# =============================================================================
# Configuration (read from deployment.toml)
# =============================================================================
DEPLOYMENT_TOML="deployment.toml"

# Verify deployment.toml exists
if [[ ! -f "$DEPLOYMENT_TOML" ]]; then
    echo "Error: deployment.toml not found"
    exit 1
fi

# Verify yq is available
if ! command -v yq &> /dev/null; then
    echo "Error: yq is required but not installed"
    echo "Install with: brew install yq"
    exit 1
fi

# =============================================================================
# Argument Validation
# =============================================================================
FACTORY="$1"

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
#   test-den-factory-deployer  - 0xfda43c00ba0589bb10bc3b75c3d8e1046e73e328 (for Den factory deployment)
#   test-guardian-safe-owner   - (read from deployment.toml)
#   test-deployer-safe-owner   - (read from deployment.toml)
#   test-guardian-executor     - (read from deployment.toml)
#   test-deployer-executor     - (read from deployment.toml)

PORT="8545"
RPC_URL="http://127.0.0.1:$PORT"

# Account names
DEPLOYER_ACCOUNT="test-deployer"
DEN_FACTORY_DEPLOYER_ACCOUNT="test-den-factory-deployer"
GUARDIAN_SAFE_OWNER_ACCOUNT="test-guardian-safe-owner"
DEPLOYER_SAFE_OWNER_ACCOUNT="test-deployer-safe-owner"

# EOA addresses - some hardcoded (foundry test accounts), some from deployment.toml
DEPLOYER_ADDRESS="0x901cab5fdb93571f0f6cd6d643f8b2532f00d2a3"
DEN_FACTORY_DEPLOYER_ADDRESS="0xfda43c00ba0589bb10bc3b75c3d8e1046e73e328"

# Read Safe owner and executor addresses from deployment.toml (nonprod)
GUARDIAN_SAFE_OWNER_ADDRESS=$(yq -r '.safe.nonprod.guardian_safe_owner_1' "$DEPLOYMENT_TOML")
DEPLOYER_SAFE_OWNER_ADDRESS=$(yq -r '.safe.nonprod.deployer_safe_owner_1' "$DEPLOYMENT_TOML")
GUARDIAN_EXECUTOR_ADDRESS=$(yq -r '.safe.nonprod.guardian_executor_eoa' "$DEPLOYMENT_TOML")
DEPLOYER_EXECUTOR_ADDRESS=$(yq -r '.safe.nonprod.deployer_executor_eoa' "$DEPLOYMENT_TOML")

# Validate addresses were read successfully
if [[ -z "$GUARDIAN_SAFE_OWNER_ADDRESS" || "$GUARDIAN_SAFE_OWNER_ADDRESS" == "null" ]]; then
    echo "Error: Guardian Safe owner address not found in deployment.toml"
    exit 1
fi
if [[ -z "$DEPLOYER_SAFE_OWNER_ADDRESS" || "$DEPLOYER_SAFE_OWNER_ADDRESS" == "null" ]]; then
    echo "Error: Deployer Safe owner address not found in deployment.toml"
    exit 1
fi
if [[ -z "$GUARDIAN_EXECUTOR_ADDRESS" || "$GUARDIAN_EXECUTOR_ADDRESS" == "null" ]]; then
    echo "Error: Guardian executor EOA address not found in deployment.toml"
    exit 1
fi
if [[ -z "$DEPLOYER_EXECUTOR_ADDRESS" || "$DEPLOYER_EXECUTOR_ADDRESS" == "null" ]]; then
    echo "Error: Deployer executor EOA address not found in deployment.toml"
    exit 1
fi

echo "============================================================================="
echo "Local Deployment Test: $FACTORY"
echo "============================================================================="
echo "  RPC URL: $RPC_URL"
echo "  Deployer Account: $DEPLOYER_ACCOUNT ($DEPLOYER_ADDRESS)"
echo "  Guardian Safe Owner: $GUARDIAN_SAFE_OWNER_ADDRESS"
echo "  Deployer Safe Owner: $DEPLOYER_SAFE_OWNER_ADDRESS"
echo "  Guardian Executor: $GUARDIAN_EXECUTOR_ADDRESS"
echo "  Deployer Executor: $DEPLOYER_EXECUTOR_ADDRESS"
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
for addr in $DEPLOYER_ADDRESS $DEN_FACTORY_DEPLOYER_ADDRESS $GUARDIAN_SAFE_OWNER_ADDRESS $DEPLOYER_SAFE_OWNER_ADDRESS $GUARDIAN_EXECUTOR_ADDRESS $DEPLOYER_EXECUTOR_ADDRESS; do
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
# Step 7: Deploy Safe Executor Modules
# =============================================================================
echo ""
echo "[Step 7] Deploying Safe Executor Modules..."

echo "  Deploying guardian Safe Executor Module (executor: $GUARDIAN_EXECUTOR_ADDRESS)..."
make deploy-safe-module SAFE_TYPE=guardian EXECUTOR=$GUARDIAN_EXECUTOR_ADDRESS ACCOUNT=$DEPLOYER_ACCOUNT FACTORY=$FACTORY

echo "  Deploying deployer Safe Executor Module (executor: $DEPLOYER_EXECUTOR_ADDRESS)..."
make deploy-safe-module SAFE_TYPE=deployer EXECUTOR=$DEPLOYER_EXECUTOR_ADDRESS ACCOUNT=$DEPLOYER_ACCOUNT FACTORY=$FACTORY

# =============================================================================
# Step 8: Add Modules to Safes (Local Testing Only)
# =============================================================================
echo ""
echo "[Step 8] Adding modules to Safes..."
echo "  Note: This requires Safe owner signatures. Using the Safe owner accounts."

# Add module to guardian Safe (using guardian Safe owner account)
echo "  Adding module to guardian Safe..."
make safe-add-module SAFE_TYPE=guardian ACCOUNT=$GUARDIAN_SAFE_OWNER_ACCOUNT FACTORY=$FACTORY EXECUTE=true || {
    echo "  Warning: Failed to add module to guardian Safe (may need multi-sig approval)"
}

# Add module to deployer Safe (using deployer Safe owner account)
echo "  Adding module to deployer Safe..."
make safe-add-module SAFE_TYPE=deployer ACCOUNT=$DEPLOYER_SAFE_OWNER_ACCOUNT FACTORY=$FACTORY EXECUTE=true || {
    echo "  Warning: Failed to add module to deployer Safe (may need multi-sig approval)"
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

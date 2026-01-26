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
# Configuration
# =============================================================================
PORT="8545"
RPC_URL="http://127.0.0.1:$PORT"
ACCOUNT="test-singleton-factory-deployer"

# The EOA address for the account (Den non-prod factory deployer)
# This address is used for all deployments regardless of factory choice
EOA_ADDRESS="0x22002e8661A780d61EF4c86F4a9fFa843A6fea20"

echo "============================================================================="
echo "Local Deployment Test: $FACTORY"
echo "============================================================================="
echo "  RPC URL: $RPC_URL"
echo "  Account: $ACCOUNT"
echo "  EOA:     $EOA_ADDRESS"
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
# Step 2: Fund EOA
# =============================================================================
echo ""
echo "[Step 2] Funding EOA..."
cast rpc anvil_setBalance $EOA_ADDRESS 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff --rpc-url $RPC_URL
echo "  Funded $EOA_ADDRESS"

# =============================================================================
# Step 3: Deploy CREATE2 Factory
# =============================================================================
echo ""
echo "[Step 3] Deploying CREATE2 Factory ($FACTORY)..."

if [[ "$FACTORY" == "arachnid" ]]; then
    # Arachnid factory uses a pre-signed keyless transaction
    # We need to fund the Arachnid deployer address first
    make fund-arachnid-deployer ACCOUNT=$ACCOUNT
    make deploy-arachnid-factory ACCOUNT=$ACCOUNT
else
    # Den non-prod factory is deployed by the EOA we already funded
    # No need to run fund-den-deployer since EOA is already funded
    make deploy-den-factory ACCOUNT=$ACCOUNT
fi

# =============================================================================
# Step 4: Deploy Safe Infrastructure and Multisigs
# =============================================================================
echo ""
echo "[Step 4] Deploying Safe 1.3.0 infrastructure and multisigs..."
make deploy-safe ACCOUNT=$ACCOUNT FACTORY=$FACTORY

# =============================================================================
# Step 5: Deploy Platform Libraries
# =============================================================================
echo ""
echo "[Step 5] Deploying platform libraries..."
make deploy-libraries ACCOUNT=$ACCOUNT FACTORY=$FACTORY

# =============================================================================
# Step 6: Deploy Platform Contracts
# =============================================================================
echo ""
echo "[Step 6] Deploying platform contracts..."
make deploy-contracts ACCOUNT=$ACCOUNT FACTORY=$FACTORY

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

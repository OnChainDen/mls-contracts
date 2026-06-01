#!/bin/bash
# =============================================================================
# Local End-to-End Deployment Test Script
# =============================================================================
# Runs the full deployment flow on a local Anvil instance for testing during development
#
# Usage:
#   ./test_deploy_scripts_locally.sh arachnid      # Test Arachnid factory flow
#   ./test_deploy_scripts_locally.sh den-nonprod   # Test Den non-prod factory flow
#   ./test_deploy_scripts_locally.sh arachnid /path/to/state.json  # Optional custom Anvil state file
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
STATE_FILE_ARG="$2"

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
#   test-deployer              - 0x901cab5fdb93571f0f6cd6d643f8b2532f00d2a3 (the MLS contracts deployer:
#                                deploys all platform contracts via the CREATE2 factory; also the funder here)
#   test-den-factory-deployer  - (read from deployment.toml factory_deployer; deploys the Den CREATE2 factory)
#   test-guardian-safe-owner   - (read from deployment.toml)
#   test-admin-safe-owner      - (read from deployment.toml)
#   test-guardian-executor     - (read from deployment.toml)

PORT="8545"
RPC_URL="http://127.0.0.1:$PORT"
LOCAL_CHAIN_ID="8421"
ANVIL_STATE_FILE="${STATE_FILE_ARG:-${ANVIL_STATE_FILE:-../.anvil/state.json}}"

# Account names
MLS_CONTRACTS_DEPLOYER_ACCOUNT="test-deployer"
DEN_FACTORY_DEPLOYER_ACCOUNT="test-den-factory-deployer"
GUARDIAN_SAFE_OWNER_ACCOUNT="test-guardian-safe-owner"
ADMIN_SAFE_OWNER_ACCOUNT="test-admin-safe-owner"

# EOA addresses - some hardcoded (foundry test accounts), some from deployment.toml
MLS_CONTRACTS_DEPLOYER_ADDRESS="0x901cab5fdb93571f0f6cd6d643f8b2532f00d2a3"
DEN_FACTORY_DEPLOYER_ADDRESS=$(get_factory_deployer "den-nonprod")

# Read Safe owner and executor addresses from deployment.toml (nonprod)
# Note: get_* functions exit with error if value not found, so no need for separate validation
GUARDIAN_SAFE_OWNER_ADDRESS=$(get_guardian_safe_owner "nonprod")
ADMIN_SAFE_OWNER_ADDRESS=$(get_admin_safe_owner "nonprod")
GUARDIAN_EXECUTOR_ADDRESS=$(get_guardian_executor "nonprod")

# Read platform implementation addresses from deployment.toml (environment-independent).
# These are whitelisted via Admin Safe transactions after the whitelist is deployed.
ORG_IMPL_ADDRESS=$(get_org_impl "$FACTORY")
ACCOUNT_IMPL_ADDRESS=$(get_account_impl "$FACTORY")

echo "============================================================================="
echo "Local Deployment Test: $FACTORY"
echo "============================================================================="
echo "  RPC URL: $RPC_URL"
echo "  Deployer Account: $MLS_CONTRACTS_DEPLOYER_ACCOUNT ($MLS_CONTRACTS_DEPLOYER_ADDRESS)"
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
anvil --disable-default-create2-deployer --chain-id $LOCAL_CHAIN_ID --state $ANVIL_STATE_FILE -p $PORT &
ANVIL_PID=$!

# Wait for Anvil to start
sleep 5

echo "  Anvil started (PID: $ANVIL_PID)"

# =============================================================================
# Step 2: Fund EOAs
# =============================================================================
echo ""
echo "[Step 2] Funding EOAs..."

# Bootstrap-fund the deployer EOA (the funder) and the guardian executor EOA directly via the
# anvil cheat. The deployer must hold a balance before it can pay for the *real* funding
# transactions below, and the executor isn't covered by a funding make target.
for addr in $MLS_CONTRACTS_DEPLOYER_ADDRESS $GUARDIAN_EXECUTOR_ADDRESS; do
    cast rpc anvil_setBalance $addr 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff --rpc-url $RPC_URL
    echo "  Bootstrap-funded $addr"
done

# Fund the Safe owners with real funding transactions via the make target (exercises
# `make fund-safe-owners`). Local testing always uses the nonprod Safe config (chain id
# $LOCAL_CHAIN_ID is non-production), and the deployer EOA pays.
# (The den-nonprod factory deployer is funded in Step 3, only when that factory is used.)
echo "  Funding nonprod Safe owners via 'make fund-safe-owners'..."
make fund-safe-owners FUND_ENV=nonprod ACCOUNT=$MLS_CONTRACTS_DEPLOYER_ACCOUNT

# =============================================================================
# Step 3: Deploy CREATE2 Factory
# =============================================================================
echo ""
echo "[Step 3] Deploying CREATE2 Factory ($FACTORY)..."

if [[ "$FACTORY" == "arachnid" ]]; then
    # Arachnid factory uses a pre-signed keyless transaction
    # We need to fund the Arachnid deployer address first
    make fund-arachnid-factory-deployer ACCOUNT=$MLS_CONTRACTS_DEPLOYER_ACCOUNT
    make deploy-arachnid-factory ACCOUNT=$MLS_CONTRACTS_DEPLOYER_ACCOUNT
else
    # Den non-prod factory is deployed by the Den factory deployer account at nonce 0.
    # Fund that deployer first via the make target (exercises `make fund-den-factory-deployer`).
    # The funder is the deployer EOA, never the Den factory deployer itself (sending a tx from
    # it would burn nonce 0 and change the deterministic factory address).
    make fund-den-factory-deployer DEN_FACTORY_DEPLOYER_ADDRESS=$DEN_FACTORY_DEPLOYER_ADDRESS ACCOUNT=$MLS_CONTRACTS_DEPLOYER_ACCOUNT
    make deploy-den-factory ACCOUNT=$DEN_FACTORY_DEPLOYER_ACCOUNT
fi

# =============================================================================
# Step 4: Deploy Safe Infrastructure and Multisigs
# =============================================================================
# Safe deployment is split into two steps for security:
#   Step 4a: Infrastructure (singleton, proxy factory, handlers)
#   Step 4b: Multisigs (Guardian and Admin Safes) - verifies infra first
echo ""
echo "[Step 4a] Deploying Safe 1.4.1 infrastructure..."
make deploy-safe-infra ACCOUNT=$MLS_CONTRACTS_DEPLOYER_ACCOUNT FACTORY=$FACTORY

echo ""
echo "[Step 4b] Deploying Safe multisigs (Guardian and Admin Safes)..."
make deploy-safe-multisigs ACCOUNT=$MLS_CONTRACTS_DEPLOYER_ACCOUNT FACTORY=$FACTORY

# =============================================================================
# Step 5: Deploy Platform Libraries (in two stages)
# =============================================================================
# Libraries must be deployed in two stages due to inter-library dependencies:
#   Stage 1 (independent): Policy, Admin, Members, Groups, TxRecovery, GuardianRecovery (no deps on other libs)
#   Stage 2 (dependent): Init and AccountSig (depend on Stage 1 libs being linked)
echo ""
echo "[Step 5a] Deploying independent libraries (Policy, Admin, Members, Groups, TxRecovery, GuardianRecovery)..."
make deploy-independent-libs ACCOUNT=$MLS_CONTRACTS_DEPLOYER_ACCOUNT FACTORY=$FACTORY

echo ""
echo "[Step 5b] Deploying dependent libraries (Init, AccountSig)..."
make deploy-dependent-libs ACCOUNT=$MLS_CONTRACTS_DEPLOYER_ACCOUNT FACTORY=$FACTORY

# =============================================================================
# Step 6: Deploy Platform Contracts
# =============================================================================
echo ""
echo "[Step 6] Deploying platform contracts..."
make deploy-contracts ACCOUNT=$MLS_CONTRACTS_DEPLOYER_ACCOUNT FACTORY=$FACTORY

# =============================================================================
# Step 6.4: Whitelist Organization and Account Implementations (single Admin Safe transaction)
# =============================================================================
# The Admin Safe owns the whitelist, so whitelisting the implementations requires an Admin Safe
# transaction. Both the Organization and Account implementations are whitelisted together in one
# atomic transaction (batched via MultiSendCallOnly).
echo ""
echo "[Step 6.4] Whitelisting implementations via a single Admin Safe transaction..."
echo "  Note: This requires Admin Safe owner signatures. Using the Admin Safe owner account."
echo "  Whitelisting Organization ($ORG_IMPL_ADDRESS) and Account ($ACCOUNT_IMPL_ADDRESS) implementations..."
make whitelist-implementations \
    ORG_IMPLEMENTATIONS="[$ORG_IMPL_ADDRESS]" ACCOUNT_IMPLEMENTATIONS="[$ACCOUNT_IMPL_ADDRESS]" EXECUTE=true \
    ACCOUNT=$ADMIN_SAFE_OWNER_ACCOUNT FACTORY=$FACTORY || {
    echo "  Warning: Failed to whitelist implementations (may need multi-sig approval)"
}

# Verify the implementations were actually whitelisted onchain (fails the script via `set -e` if not).
# This guards against the whitelist transaction silently not taking effect.
echo ""
echo "  Verifying implementations are whitelisted onchain..."
make is-implementation-whitelisted CONTRACT_TYPE=organization IMPLEMENTATION=$ORG_IMPL_ADDRESS FACTORY=$FACTORY
make is-implementation-whitelisted CONTRACT_TYPE=account IMPLEMENTATION=$ACCOUNT_IMPL_ADDRESS FACTORY=$FACTORY
echo "  ✅ Both Organization and Account implementations are whitelisted."

# =============================================================================
# Step 6.5: Deploy BatchedTransaction
# =============================================================================
echo ""
echo "[Step 6.5] Deploying BatchedTransaction..."
make deploy-batched-transaction ACCOUNT=$MLS_CONTRACTS_DEPLOYER_ACCOUNT FACTORY=$FACTORY

# =============================================================================
# Step 7: Deploy Guardian Safe Executor Module
# =============================================================================
echo ""
echo "[Step 7] Deploying Guardian Safe Executor Module..."

echo "  Deploying Guardian Safe Executor Module (executor: $GUARDIAN_EXECUTOR_ADDRESS)..."
make deploy-guardian-safe-module EXECUTOR=$GUARDIAN_EXECUTOR_ADDRESS ACCOUNT=$MLS_CONTRACTS_DEPLOYER_ACCOUNT FACTORY=$FACTORY

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

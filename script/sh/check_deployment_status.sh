#!/bin/bash
# =============================================================================
# Check Deployment Status Script
# =============================================================================
# Verifies that every platform contract (and the CREATE2 factory itself) for a
# given factory is deployed on a target network by performing a simple
# bytecode-nonzero check (`cast code`) against each expected address from
# deployment.toml (the single source of truth).
#
# This is a READ-ONLY check intended to be run before, during, and after a
# deployment:
#   - Before:  confirm nothing has been deployed yet (everything MISSING).
#   - During:  watch expected progress as contracts come online.
#   - After:   confirm everything that should be deployed actually is.
#
# Output is grouped by factory section (factory / libraries / implementations /
# Safe infrastructure / BatchedTransaction) and then by environment
# (nonprod vs prod) for the env-dependent Safes and contracts.
#
# The active environment (prod vs nonprod) is derived from the chain ID, mirroring
# DeploymentConfig._isProductionChain() in script/base/DeploymentConfig.sol. Both
# environments are always shown, but only the active one is counted toward the
# pass/fail summary and exit code; the other is shown for reference.
#
# Usage:
#   ./check_deployment_status.sh <factory> [rpc_url] [network_label] [env]
#
# Where:
#   <factory>        arachnid | den-nonprod | den-prod
#   [rpc_url]        RPC URL or foundry.toml alias (default: http://127.0.0.1:8545)
#   [network_label]  Human-readable network name for display (default: rpc_url)
#   [env]            auto | nonprod | prod | both  (default: auto — detect from chain id)
#
# Exit code:
#   0  All contracts in the active scope are deployed (no MISSING / ERROR).
#   1  One or more active-scope contracts are missing or could not be checked.
#
# =============================================================================

# NOTE: We deliberately do NOT use `set -e`. Individual `cast code` calls are
# expected to "fail" (e.g. RPC hiccups) and we want to report them per-address
# rather than abort the whole report.

# =============================================================================
# Source Shared Configuration
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# Run from repo root so deployment.toml (relative path in the config lib) and
# foundry.toml rpc aliases resolve correctly regardless of caller CWD.
cd "$REPO_ROOT" || exit 1

source "$SCRIPT_DIR/lib/deployment_config.sh"

# Validate prerequisites (deployment.toml exists, yq available)
validate_prerequisites

if ! command -v cast &> /dev/null; then
    echo "Error: cast (Foundry) is required but not installed" >&2
    exit 1
fi

# =============================================================================
# Argument Parsing
# =============================================================================
FACTORY="$1"
RPC_URL="${2:-http://127.0.0.1:8545}"
NETWORK_LABEL="${3:-$RPC_URL}"
ENV_OVERRIDE="${4:-auto}"

validate_factory "$FACTORY"

ZERO_ADDRESS="0x0000000000000000000000000000000000000000"

# =============================================================================
# Colors (only when stdout is a terminal and NO_COLOR is unset)
# =============================================================================
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    C_GREEN=$'\033[32m'
    C_RED=$'\033[31m'
    C_YELLOW=$'\033[33m'
    C_DIM=$'\033[2m'
    C_BOLD=$'\033[1m'
    C_RESET=$'\033[0m'
else
    C_GREEN=""; C_RED=""; C_YELLOW=""; C_DIM=""; C_BOLD=""; C_RESET=""
fi

# =============================================================================
# Counters
# =============================================================================
# "active" scope (factory + env-independent + active env) — gates the exit code.
DEPLOYED_COUNT=0
MISSING_COUNT=0
SKIPPED_COUNT=0
ERROR_COUNT=0
# "reference" scope (the non-active env) — informational only.
REF_DEPLOYED=0
REF_MISSING=0
REF_SKIPPED=0
REF_ERROR=0

# Whether the current section counts toward the exit code ("active") or is
# informational only ("reference"). Defaults to active.
COUNT_MODE="active"

# =============================================================================
# Helpers
# =============================================================================

# Read a factory-level (environment-independent) address from deployment.toml.
fac() { get_config_silent ".factory[\"$FACTORY\"].$1"; }

# Read an environment-dependent address from deployment.toml.
# Usage: env_addr <nonprod|prod> <key>
env_addr() { get_config_silent ".factory[\"$FACTORY\"].env.$1.$2"; }

# Print a section header.
print_section() { printf "\n  %s%s%s\n" "$C_BOLD" "$1" "$C_RESET"; }

# Check a single contract address and print its status line.
# Honors COUNT_MODE to route counts to the active or reference tallies.
# Usage: check_contract <label> <address>
check_contract() {
    local label="$1"
    local addr="$2"
    local status color disp padded

    if [[ -z "$addr" || "$addr" == "null" || "$addr" == "NOT_COMPUTED" || "$addr" == "$ZERO_ADDRESS" ]]; then
        status="SKIPPED"; color="$C_DIM"; disp="(not configured in deployment.toml)"
        if [[ "$COUNT_MODE" == "active" ]]; then SKIPPED_COUNT=$((SKIPPED_COUNT + 1)); else REF_SKIPPED=$((REF_SKIPPED + 1)); fi
    else
        local code rc
        code=$(cast code "$addr" --rpc-url "$RPC_URL" 2>/dev/null)
        rc=$?
        if [[ $rc -ne 0 ]]; then
            status="ERROR"; color="$C_RED"; disp="$addr  (rpc call failed)"
            if [[ "$COUNT_MODE" == "active" ]]; then ERROR_COUNT=$((ERROR_COUNT + 1)); else REF_ERROR=$((REF_ERROR + 1)); fi
        elif [[ -z "$code" || "$code" == "0x" ]]; then
            status="MISSING"; color="$C_RED"; disp="$addr"
            if [[ "$COUNT_MODE" == "active" ]]; then MISSING_COUNT=$((MISSING_COUNT + 1)); else REF_MISSING=$((REF_MISSING + 1)); fi
        else
            status="DEPLOYED"; color="$C_GREEN"; disp="$addr"
            if [[ "$COUNT_MODE" == "active" ]]; then DEPLOYED_COUNT=$((DEPLOYED_COUNT + 1)); else REF_DEPLOYED=$((REF_DEPLOYED + 1)); fi
        fi
    fi

    printf -v padded "%-9s" "$status"
    printf "    %s%s%s  %-32s %s\n" "$color" "$padded" "$C_RESET" "$label" "$disp"
}

# Print and check an environment block (nonprod or prod).
# Sets COUNT_MODE based on whether this env is active for the target network.
check_env_block() {
    local env="$1"
    local annotation

    if [[ "$ACTIVE_ENV" == "both" || "$ACTIVE_ENV" == "unknown" || "$env" == "$ACTIVE_ENV" ]]; then
        COUNT_MODE="active"
        annotation="${C_GREEN}active for ${NETWORK_LABEL}${C_RESET}"
    else
        COUNT_MODE="reference"
        annotation="${C_DIM}reference only — not expected on ${NETWORK_LABEL}${C_RESET}"
    fi

    print_section "Safes & env-dependent contracts — ${env}  (${annotation})"
    check_contract "guardian_safe" "$(env_addr "$env" guardian_safe)"
    check_contract "admin_safe" "$(env_addr "$env" admin_safe)"
    check_contract "org_factory" "$(env_addr "$env" org_factory)"
    check_contract "whitelist_proxy" "$(env_addr "$env" whitelist_proxy)"
    check_contract "guardian_safe_executor_module" "$(env_addr "$env" guardian_safe_executor_module)"

    COUNT_MODE="active"
}

# =============================================================================
# Resolve chain ID and active environment
# =============================================================================
CHAIN_ID=$(cast chain-id --rpc-url "$RPC_URL" 2>/dev/null) || CHAIN_ID=""

if [[ "$ENV_OVERRIDE" == "auto" || -z "$ENV_OVERRIDE" ]]; then
    if [[ -z "$CHAIN_ID" ]]; then
        ACTIVE_ENV="unknown"
    else
        # Production chain IDs — keep in sync with
        # DeploymentConfig._isProductionChain() (script/base/DeploymentConfig.sol).
        case "$CHAIN_ID" in
            1|10|56|137|8453|42161|43114) ACTIVE_ENV="prod" ;;
            *) ACTIVE_ENV="nonprod" ;;
        esac
    fi
else
    case "$ENV_OVERRIDE" in
        nonprod|prod|both) ACTIVE_ENV="$ENV_OVERRIDE" ;;
        *)
            echo "Error: invalid env '$ENV_OVERRIDE' (use auto, nonprod, prod, or both)" >&2
            exit 1
            ;;
    esac
fi

FACTORY_ADDRESS="$(fac factory)"

# =============================================================================
# Header
# =============================================================================
printf "\n%s\n" "================================================================================"
printf "  %sDeployment status%s   factory: %s%s%s   network: %s%s%s\n" \
    "$C_BOLD" "$C_RESET" "$C_BOLD" "$FACTORY" "$C_RESET" "$C_BOLD" "$NETWORK_LABEL" "$C_RESET"
printf "  Factory address: %s\n" "${FACTORY_ADDRESS:-(not configured)}"
printf "  Chain id: %s   Active env: %s%s%s\n" "${CHAIN_ID:-unknown}" "$C_BOLD" "$ACTIVE_ENV" "$C_RESET"
printf "%s\n" "================================================================================"
printf "  %sDEPLOYED%s = bytecode present   %sMISSING%s = no bytecode   %sSKIPPED%s = not configured   %sERROR%s = rpc call failed\n" \
    "$C_GREEN" "$C_RESET" "$C_RED" "$C_RESET" "$C_DIM" "$C_RESET" "$C_RED" "$C_RESET"

# =============================================================================
# Environment-independent sections (always part of the active scope)
# =============================================================================
print_section "Factory (CREATE2)"
check_contract "factory" "$FACTORY_ADDRESS"

print_section "Platform libraries (environment-independent)"
check_contract "lib_org_policy" "$(fac lib_org_policy)"
check_contract "lib_org_admin" "$(fac lib_org_admin)"
check_contract "lib_org_members" "$(fac lib_org_members)"
check_contract "lib_org_groups" "$(fac lib_org_groups)"
check_contract "lib_org_init" "$(fac lib_org_init)"
check_contract "lib_org_account_sig" "$(fac lib_org_account_sig)"
check_contract "lib_org_tx_recovery" "$(fac lib_org_tx_recovery)"
check_contract "lib_org_guardian_recovery" "$(fac lib_org_guardian_recovery)"

print_section "Platform implementations (environment-independent)"
check_contract "whitelist_impl" "$(fac whitelist_impl)"
check_contract "org_impl" "$(fac org_impl)"
check_contract "account_impl" "$(fac account_impl)"

print_section "Safe 1.4.1 infrastructure (environment-independent)"
check_contract "safe_singleton" "$(fac safe_singleton)"
check_contract "safe_proxy_factory" "$(fac safe_proxy_factory)"
check_contract "safe_fallback_handler" "$(fac safe_fallback_handler)"
check_contract "safe_multisend" "$(fac safe_multisend)"
check_contract "safe_multisend_call_only" "$(fac safe_multisend_call_only)"
check_contract "safe_create_call" "$(fac safe_create_call)"
check_contract "safe_simulate_tx_accessor" "$(fac safe_simulate_tx_accessor)"

print_section "BatchedTransaction (environment-independent)"
check_contract "batched_transaction" "$(fac batched_transaction)"

# =============================================================================
# Environment-dependent sections (nonprod then prod; active one gates exit code)
# =============================================================================
check_env_block "nonprod"
check_env_block "prod"

# =============================================================================
# Summary
# =============================================================================
CHECKED=$((DEPLOYED_COUNT + MISSING_COUNT + ERROR_COUNT))

printf "\n%s\n" "--------------------------------------------------------------------------------"
printf "  Summary (%s @ %s, env %s): %s%d/%d deployed%s" \
    "$FACTORY" "$NETWORK_LABEL" "$ACTIVE_ENV" "$C_BOLD" "$DEPLOYED_COUNT" "$CHECKED" "$C_RESET"
[[ $MISSING_COUNT -gt 0 ]] && printf ", %s%d missing%s" "$C_RED" "$MISSING_COUNT" "$C_RESET"
[[ $ERROR_COUNT -gt 0 ]] && printf ", %s%d error%s" "$C_RED" "$ERROR_COUNT" "$C_RESET"
[[ $SKIPPED_COUNT -gt 0 ]] && printf ", %s%d skipped%s" "$C_DIM" "$SKIPPED_COUNT" "$C_RESET"
printf "\n"

# Show the other (reference) environment tally if anything was checked there.
REF_TOTAL=$((REF_DEPLOYED + REF_MISSING + REF_ERROR + REF_SKIPPED))
if [[ $REF_TOTAL -gt 0 ]]; then
    printf "  %sReference env (other): %d deployed, %d missing, %d error, %d skipped — not counted%s\n" \
        "$C_DIM" "$REF_DEPLOYED" "$REF_MISSING" "$REF_ERROR" "$REF_SKIPPED" "$C_RESET"
fi
printf "%s\n" "--------------------------------------------------------------------------------"

if [[ $MISSING_COUNT -gt 0 || $ERROR_COUNT -gt 0 ]]; then
    exit 1
fi
exit 0

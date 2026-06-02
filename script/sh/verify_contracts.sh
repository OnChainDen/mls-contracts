#!/bin/bash
# =============================================================================
# Verify Platform Contracts Script
# =============================================================================
# Verifies every platform contract for a given factory/environment on a block
# explorer using `forge verify-contract`. Addresses, library link addresses,
# and the inputs to constructor args are all read from deployment.toml (the
# single source of truth), so this stays correct as addresses change.
#
# `forge verify-contract` recompiles from source and submits a standard-JSON 
# input to the explorer. The ONLY requirement is that the working tree is checked 
# out at the exact commit (and submodules) that was deployed, so the recompiled 
# bytecode matches what is on-chain. Because foundry.toml sets 
# `bytecode_hash = "none"` and `via_ir`, recompilation is deterministic and 
# yields a byte-exact match.
#
# TIP: run `make check-deployment FACTORY=<factory> RPC_URL=<rpc_url> ENV=<env>`
# first. If it reports every contract DEPLOYED at the locally-computed address,
# your local bytecode == on-chain bytecode and verification will be a full match.
#
# Because every contract is deployed via CREATE2 from the same factory, its
# address is identical on every chain — only the explorer/--chain differs.
#
# Scope: the Den-authored platform contracts (8 libraries, 3 implementations,
# OrganizationFactory, ImplementationWhitelistProxy, BatchedTransaction, and the
# Guardian SafeExecutorModule). The Safe 1.4.1 infrastructure is NOT covered
# here: it is compiled under FOUNDRY_PROFILE=safe (solc 0.7.6) and must be
# verified separately. See docs/DEPLOYMENT.md.
#
# Usage:
#   ./verify_contracts.sh <factory> <chain> [env] [verifier] [verifier_url]
#
# Where:
#   <factory>       arachnid | den-nonprod | den-prod
#   <chain>         chain id or forge chain alias passed to `forge --chain`
#                   (e.g. mainnet, optimism, base, arbitrum, sepolia, 2020)
#   [env]           prod | nonprod | auto  (default auto — derived from <chain>,
#                   mirroring DeploymentConfig._isProductionChain())
#   [verifier]      etherscan (default) | sourcify | blockscout | custom | ...
#   [verifier_url]  optional --verifier-url (required for sourcify/blockscout/custom)
#
# Environment:
#   ETHERSCAN_API_KEY   required when verifier=etherscan. A single Etherscan V2
#                       key works for Ethereum, Optimism, Base, Arbitrum, Sepolia.
#                       Non-Etherscan chains use a different verifier
#                       (blockscout/sourcify) with its endpoint.
#   VERIFIER_API_KEY    API key for non-etherscan verifiers that require one
#                       (oklink, custom, or a key-gated explorer). Not needed for
#                       sourcify or most blockscout instances.
#                       Both keys, if unset in the environment, are read from a .env
#                       file (repo root, or $DOTENV). The real environment wins over .env.
#   DOTENV              path to the .env file to read (default: <repo-root>/.env).
#   DRY_RUN=1           print the forge commands without executing them.
#
# Examples:
#   ETHERSCAN_API_KEY=xxx ./verify_contracts.sh arachnid mainnet prod
#   ETHERSCAN_API_KEY=xxx ./verify_contracts.sh arachnid base
#   ./verify_contracts.sh arachnid 2020 prod sourcify https://sourcify.dev/server
#
# Exit code:
#   0  every in-scope contract verified (or was already verified).
#   1  one or more contracts failed verification (or a prerequisite was missing).
#
# =============================================================================

# NOTE: We deliberately do NOT use `set -e`. Individual verify calls may fail
# (e.g. one contract already verified, transient explorer errors) and we want to
# report them per-contract and continue rather than abort the whole run.

# =============================================================================
# Source Shared Configuration
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$REPO_ROOT/.." && pwd)"
# Run from repo root so deployment.toml and foundry.toml resolve regardless of CWD.
cd "$REPO_ROOT" || exit 1

source "$SCRIPT_DIR/lib/deployment_config.sh"
source "$SCRIPT_DIR/lib/verifier.sh"
source "$SCRIPT_DIR/lib/output.sh"

# Validate prerequisites (deployment.toml exists, yq available)
validate_prerequisites

if ! command -v forge &> /dev/null; then
    echo "Error: forge (Foundry) is required but not installed" >&2
    exit 1
fi
if ! command -v cast &> /dev/null; then
    echo "Error: cast (Foundry) is required but not installed" >&2
    exit 1
fi

# =============================================================================
# Argument Parsing
# =============================================================================
FACTORY="$1"
CHAIN="$2"
ENV_IN="${3:-auto}"
VERIFIER="${4:-etherscan}"
VERIFIER_URL="${5:-}"

validate_factory "$FACTORY"

if [[ -z "$CHAIN" ]]; then
    echo "Error: chain argument required (chain id or forge chain alias, e.g. mainnet, base, 2020)" >&2
    echo "Usage: ./verify_contracts.sh <factory> <chain> [env] [verifier] [verifier_url]" >&2
    exit 1
fi

case "$CHAIN" in
    local|localhost|127.0.0.1|http://127.0.0.1:8545)
        echo "Error: '$CHAIN' is not a verifiable network. Pass a real chain (e.g. mainnet, base, 2020)." >&2
        exit 1
        ;;
esac

# Resolve environment (selects the env-dependent Safe addresses + constructor args).
if [[ "$ENV_IN" == "auto" || -z "$ENV_IN" ]]; then
    # Production chains — keep in sync with
    # DeploymentConfig._isProductionChain() (script/base/DeploymentConfig.sol).
    case "$CHAIN" in
        1|mainnet|ethereum|10|optimism|op|8453|base|42161|arbitrum|arb|arbitrum-one|2020|ronin|11155111|sepolia)
            ENV="prod" ;;
        *)
            ENV="nonprod" ;;
    esac
else
    case "$ENV_IN" in
        prod|nonprod) ENV="$ENV_IN" ;;
        *)
            echo "Error: invalid env '$ENV_IN' (use prod, nonprod, or auto)" >&2
            exit 1
            ;;
    esac
fi

# =============================================================================
# Verifier flags (loads API keys from env or .env; derives Blockscout URL from
# explorers.toml when omitted; see lib/verifier.sh)
# =============================================================================
build_verifier_flags "$CHAIN"

ZERO_ADDRESS="0x0000000000000000000000000000000000000000"

# =============================================================================
# Counters
# =============================================================================
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
FAILED_LABELS=()
VERIFIED_LINKS=()

# =============================================================================
# Address readers (mirror check_deployment_status.sh)
# =============================================================================
fac() { get_config_silent ".factory[\"$FACTORY\"].$1"; }
addr_env() { get_config_silent ".factory[\"$FACTORY\"].env.$ENV.$1"; }

# =============================================================================
# Contract source identifiers (path:Name)
# =============================================================================
ORG_IMPL_CONTRACT="src/organization/OrganizationImplementation.sol:OrganizationImplementation"
ACCOUNT_IMPL_CONTRACT="src/account/AccountImplementation.sol:AccountImplementation"
WHITELIST_IMPL_CONTRACT="src/implementation-whitelist/ImplementationWhitelistImplementation.sol:ImplementationWhitelistImplementation"
WHITELIST_PROXY_CONTRACT="src/implementation-whitelist/ImplementationWhitelistProxy.sol:ImplementationWhitelistProxy"
ORG_FACTORY_CONTRACT="src/organization/OrganizationFactory.sol:OrganizationFactory"
BATCHED_TX_CONTRACT="src/safe-module/BatchedTransaction.sol:BatchedTransaction"
MODULE_CONTRACT="src/safe-module/SafeExecutorModule.sol:SafeExecutorModule"

# =============================================================================
# Library link flags
# =============================================================================
# OrganizationImplementation references all 8 external libraries.
ORG_IMPL_LIBS="$(build_all_libraries_flags "$FACTORY")"
# LibOrganizationInitialization references Admin, Members, Groups, TxRecovery, GuardianRecovery.
INIT_LIBS="--libraries ${LIB_ORG_ADMIN_PATH}:$(get_lib_org_admin "$FACTORY") --libraries ${LIB_ORG_MEMBERS_PATH}:$(get_lib_org_members "$FACTORY") --libraries ${LIB_ORG_GROUPS_PATH}:$(get_lib_org_groups "$FACTORY") --libraries ${LIB_ORG_TX_RECOVERY_PATH}:$(get_lib_org_tx_recovery "$FACTORY") --libraries ${LIB_ORG_GUARDIAN_RECOVERY_PATH}:$(get_lib_org_guardian_recovery "$FACTORY")"
# LibOrganizationAccountSignature references Policy and TxRecovery.
ACCSIG_LIBS="--libraries ${LIB_ORG_POLICY_PATH}:$(get_lib_org_policy "$FACTORY") --libraries ${LIB_ORG_TX_RECOVERY_PATH}:$(get_lib_org_tx_recovery "$FACTORY")"

# =============================================================================
# Constructor args (built from deployment.toml via cast)
# =============================================================================
GUARDIAN_SAFE="$(addr_env guardian_safe)"
ADMIN_SAFE="$(addr_env admin_safe)"
WHITELIST_IMPL_ADDR="$(fac whitelist_impl)"
BATCHED_TX_ADDR="$(fac batched_transaction)"
GUARDIAN_EXEC="$(get_config_silent ".safe.$ENV.guardian_executor_eoa")"

# OrganizationFactory(address _deployerAddress = guardianSafe)
CARGS_FACTORY=""
if [[ -n "$GUARDIAN_SAFE" ]]; then
    CARGS_FACTORY="$(cast abi-encode "args(address)" "$GUARDIAN_SAFE")"
fi

# SafeExecutorModule(address safe, address authorizedExecutor, address batchedTransaction)
CARGS_MODULE=""
if [[ -n "$GUARDIAN_SAFE" && -n "$GUARDIAN_EXEC" && -n "$BATCHED_TX_ADDR" ]]; then
    CARGS_MODULE="$(cast abi-encode "args(address,address,address)" "$GUARDIAN_SAFE" "$GUARDIAN_EXEC" "$BATCHED_TX_ADDR")"
fi

# ImplementationWhitelistProxy(address implementation, bytes initData)
# initData = initialize(adminSafe, [], [])  (owner only; impls are seeded later via Admin Safe txs)
CARGS_PROXY=""
if [[ -n "$WHITELIST_IMPL_ADDR" && -n "$ADMIN_SAFE" ]]; then
    INITDATA="$(cast calldata "initialize(address,address[],address[])" "$ADMIN_SAFE" "[]" "[]")"
    CARGS_PROXY="$(cast abi-encode "args(address,bytes)" "$WHITELIST_IMPL_ADDR" "$INITDATA")"
fi

# =============================================================================
# Verify a single contract
# Usage: verify_one <label> <address> <contract> <constructor_args> <libraries_flags>
# =============================================================================
verify_one() {
    local label="$1" addr="$2" contract="$3" cargs="$4" libs="$5"

    if [[ -z "$addr" || "$addr" == "null" || "$addr" == "NOT_COMPUTED" || "$addr" == "$ZERO_ADDRESS" ]]; then
        printf "  %s%-9s%s %-34s %s\n" "$C_DIM" "SKIP" "$C_RESET" "$label" "(not configured in deployment.toml)"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        return
    fi

    # Assemble the command. Unquoted $libs / $VERIFIER_FLAGS expand into separate
    # tokens (paths and addresses contain no spaces).
    local -a cmd=(forge verify-contract "$addr" "$contract" --chain "$CHAIN" --watch)
    cmd+=($VERIFIER_FLAGS)
    [[ -n "$cargs" ]] && cmd+=(--constructor-args "$cargs")
    [[ -n "$libs" ]] && cmd+=($libs)

    local link
    link="$(explorer_address_url "$CHAIN" "$addr")"

    printf "\n  %s%s%s  %s  %s%s%s\n" "$C_BOLD" "$label" "$C_RESET" "$addr" "$C_DIM" "$contract" "$C_RESET"
    printf "  %s%s%s\n" "$C_DIM" "$(redact_cmd "${cmd[@]}")" "$C_RESET"

    if [[ "${DRY_RUN:-}" == "1" || "${DRY_RUN:-}" == "true" ]]; then
        [[ -n "$link" ]] && printf "    %sexplorer: %s%s\n" "$C_DIM" "$link" "$C_RESET"
        SKIP_COUNT=$((SKIP_COUNT + 1))
        return
    fi

    local output rc
    output="$("${cmd[@]}" 2>&1)"
    rc=$?
    echo "$output" | sed 's/^/    /'

    # Treat "already verified" as success regardless of exit code.
    if [[ $rc -eq 0 ]] || echo "$output" | grep -qiE "already verified|is already verified"; then
        printf "  %s%-9s%s %s\n" "$C_GREEN" "VERIFIED" "$C_RESET" "$label"
        if [[ -n "$link" ]]; then
            printf "    %s%s%s\n" "$C_DIM" "$link" "$C_RESET"
            VERIFIED_LINKS+=("$(printf '  %-36s %s' "$label" "$link")")
        fi
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        printf "  %s%-9s%s %s\n" "$C_RED" "FAILED" "$C_RESET" "$label"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        FAILED_LABELS+=("$label")
    fi
}

# =============================================================================
# Header
# =============================================================================
printf "\n%s\n" "================================================================================"
printf "  %sVerify platform contracts%s   factory: %s%s%s   chain: %s%s%s   env: %s%s%s\n" \
    "$C_BOLD" "$C_RESET" "$C_BOLD" "$FACTORY" "$C_RESET" "$C_BOLD" "$CHAIN" "$C_RESET" "$C_BOLD" "$ENV" "$C_RESET"
printf "  Verifier: %s%s\n" "$VERIFIER" "${VERIFIER_URL:+  (url: $VERIFIER_URL)}"
printf "  API key:  %s\n" "$API_KEY_SOURCE_LABEL"
printf "%s\n" "================================================================================"
printf "  %sReminder:%s verify from the exact commit that was deployed, or bytecode won't match.\n" "$C_YELLOW" "$C_RESET"
printf "  Run %smake check-deployment FACTORY=%s NETWORK=<net> ENV=%s%s first to confirm parity.\n" \
    "$C_DIM" "$FACTORY" "$ENV" "$C_RESET"

# =============================================================================
# Environment-independent contracts
# =============================================================================
printf "\n%s== Platform libraries (environment-independent) ==%s\n" "$C_BOLD" "$C_RESET"
verify_one "LibOrganizationPolicy"           "$(fac lib_org_policy)"            "$LIB_ORG_POLICY_PATH"             "" ""
verify_one "LibOrganizationAdmin"            "$(fac lib_org_admin)"             "$LIB_ORG_ADMIN_PATH"              "" ""
verify_one "LibOrganizationMembers"          "$(fac lib_org_members)"           "$LIB_ORG_MEMBERS_PATH"            "" ""
verify_one "LibOrganizationGroups"           "$(fac lib_org_groups)"            "$LIB_ORG_GROUPS_PATH"             "" ""
verify_one "LibOrganizationTxRecovery"       "$(fac lib_org_tx_recovery)"       "$LIB_ORG_TX_RECOVERY_PATH"        "" ""
verify_one "LibOrganizationGuardianRecovery" "$(fac lib_org_guardian_recovery)" "$LIB_ORG_GUARDIAN_RECOVERY_PATH"  "" ""
verify_one "LibOrganizationInitialization"   "$(fac lib_org_init)"              "$LIB_ORG_INIT_PATH"               "" "$INIT_LIBS"
verify_one "LibOrganizationAccountSignature" "$(fac lib_org_account_sig)"       "$LIB_ORG_ACCOUNT_SIG_PATH"        "" "$ACCSIG_LIBS"

printf "\n%s== Platform implementations (environment-independent) ==%s\n" "$C_BOLD" "$C_RESET"
verify_one "ImplementationWhitelistImplementation" "$(fac whitelist_impl)" "$WHITELIST_IMPL_CONTRACT" "" ""
verify_one "AccountImplementation"                 "$(fac account_impl)"   "$ACCOUNT_IMPL_CONTRACT"   "" ""
verify_one "OrganizationImplementation"            "$(fac org_impl)"       "$ORG_IMPL_CONTRACT"       "" "$ORG_IMPL_LIBS"

printf "\n%s== BatchedTransaction (environment-independent) ==%s\n" "$C_BOLD" "$C_RESET"
verify_one "BatchedTransaction" "$(fac batched_transaction)" "$BATCHED_TX_CONTRACT" "" ""

# =============================================================================
# Environment-dependent contracts (constructor args embed the prod/nonprod Safes)
# =============================================================================
printf "\n%s== Environment-dependent contracts (env: %s) ==%s\n" "$C_BOLD" "$ENV" "$C_RESET"
verify_one "OrganizationFactory"            "$(addr_env org_factory)"                   "$ORG_FACTORY_CONTRACT"    "$CARGS_FACTORY" ""
verify_one "ImplementationWhitelistProxy"   "$(addr_env whitelist_proxy)"               "$WHITELIST_PROXY_CONTRACT" "$CARGS_PROXY"  ""
verify_one "Guardian SafeExecutorModule"    "$(addr_env guardian_safe_executor_module)" "$MODULE_CONTRACT"         "$CARGS_MODULE"  ""

# =============================================================================
# Summary
# =============================================================================
printf "\n%s\n" "--------------------------------------------------------------------------------"
printf "  Summary (%s @ %s, env %s): %s%d verified%s" \
    "$FACTORY" "$CHAIN" "$ENV" "$C_GREEN" "$PASS_COUNT" "$C_RESET"
[[ $FAIL_COUNT -gt 0 ]] && printf ", %s%d failed%s" "$C_RED" "$FAIL_COUNT" "$C_RESET"
[[ $SKIP_COUNT -gt 0 ]] && printf ", %s%d skipped%s" "$C_DIM" "$SKIP_COUNT" "$C_RESET"
printf "\n"
if [[ $FAIL_COUNT -gt 0 ]]; then
    printf "  %sFailed:%s %s\n" "$C_RED" "$C_RESET" "${FAILED_LABELS[*]}"
fi
if [[ ${#VERIFIED_LINKS[@]} -gt 0 ]]; then
    printf "\n  %sVerified — open to confirm:%s\n" "$C_BOLD" "$C_RESET"
    for link_line in "${VERIFIED_LINKS[@]}"; do
        printf "%s\n" "$link_line"
    done
fi
printf "  %sNote:%s Safe 1.4.1 infrastructure is out of scope (compile with FOUNDRY_PROFILE=safe to verify it).\n" "$C_DIM" "$C_RESET"
printf "%s\n" "--------------------------------------------------------------------------------"

[[ $FAIL_COUNT -gt 0 ]] && exit 1
exit 0

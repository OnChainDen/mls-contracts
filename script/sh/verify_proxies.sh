#!/bin/bash
# =============================================================================
# Discover & Verify Factory-Deployed Proxy Instances
# =============================================================================
# Finds one OrganizationProxy and one AccountProxy instance on a chain and verifies
# each, COMPUTING the constructor args (forge's --guess-constructor-args cannot recover
# them: these proxies are created by the factory via CREATE2, not by a top-level tx, so
# Etherscan errors "Fetching of constructor arguments is not supported for contracts
# created by contracts").
#
# Constructor args (see the proxy sources / factory):
#   OrganizationProxy(address whitelistAddress)
#       whitelist = the ImplementationWhitelistProxy (deployment.toml whitelist_proxy for
#       the factory/env) — identical for every org instance.
#   AccountProxy(address beacon, bytes data)
#       beacon = the Organization that deployed the account; data = empty (0x).
#
# Verifying one instance per type per chain is enough — explorers match the rest by bytecode.
#
# Usage:
#   ./verify_proxies.sh <network> [env] [verifier] [verifier_url]
#
# Env:
#   FACTORY      CREATE2 factory (default arachnid) — selects whitelist_proxy / org_factory
#   ORG          Organization to use as the account beacon (default: the discovered org)
#   CHUNK / MAX_CHUNKS / FROM_BLOCK   passed through to find_proxy_instance.sh
#   ETHERSCAN_API_KEY / VERIFIER_API_KEY   via env or .env (handled by verify_contract.sh)
#   DRY_RUN=1    print the verify commands without executing
#
# Exit code: non-zero if any attempted verification failed.
# =============================================================================

# NOTE: no `set -e` — each sub-verification may fail independently; we aggregate.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

source "$SCRIPT_DIR/lib/deployment_config.sh"
source "$SCRIPT_DIR/lib/verifier.sh"
source "$SCRIPT_DIR/lib/output.sh"
validate_prerequisites  # deployment.toml + yq

if ! command -v cast &> /dev/null; then
    echo "Error: cast (Foundry) is required but not installed" >&2
    exit 1
fi

NETWORK="$1"
ENV_IN="${2:-auto}"
VERIFIER="${3:-etherscan}"
VERIFIER_URL="${4:-}"
FACTORY="${FACTORY:-arachnid}"

validate_factory "$FACTORY"

if [[ -z "$NETWORK" ]]; then
    echo "Usage: ./verify_proxies.sh <network> [env] [verifier] [verifier_url]" >&2
    exit 1
fi

# Resolve env (selects whitelist_proxy / org_factory). Mirrors the verify scripts.
if [[ "$ENV_IN" == "auto" || -z "$ENV_IN" ]]; then
    case "$NETWORK" in
        1|mainnet|ethereum|10|optimism|op|8453|base|42161|arbitrum|arb|arbitrum-one|2020|ronin|11155111|sepolia)
            ENV="prod" ;;
        *) ENV="nonprod" ;;
    esac
else
    case "$ENV_IN" in
        prod|nonprod) ENV="$ENV_IN" ;;
        *) echo "Error: invalid env '$ENV_IN' (use prod, nonprod, or auto)" >&2; exit 1 ;;
    esac
fi

FIND="$SCRIPT_DIR/find_proxy_instance.sh"
VERIFY="$SCRIPT_DIR/verify_contract.sh"
ORG_CONTRACT="src/organization/OrganizationProxy.sol:OrganizationProxy"
ACCT_CONTRACT="src/account/AccountProxy.sol:AccountProxy"

OVERALL=0
SUMMARY=()  # one "glyph|label|detail" entry per proxy, rendered at the end

# Verify one proxy and record its result for the summary.
# Usage: verify_proxy <label> <instance> <contract> <constructor_args>
verify_proxy() {
    local label="$1" instance="$2" contract="$3" args="$4"
    if CONSTRUCTOR_ARGS="$args" "$VERIFY" "$instance" "$contract" "$NETWORK" "$VERIFIER" "$VERIFIER_URL"; then
        SUMMARY+=("ok|$label|$(explorer_address_url "$NETWORK" "$instance")")
    else
        SUMMARY+=("fail|$label|$instance")
        OVERALL=1
    fi
}

log_banner "Verify proxies · $NETWORK · env $ENV · factory $FACTORY"

# --- OrganizationProxy ---------------------------------------------------------
log_section "OrganizationProxy"
ORG_INSTANCE="$("$FIND" org "$NETWORK" "$ENV")"
if [[ -n "$ORG_INSTANCE" ]]; then
    WHITELIST="$(get_whitelist_proxy_address "$FACTORY" "$ENV")"
    ORG_ARGS="$(cast abi-encode "ctor(address)" "$WHITELIST")"
    verify_proxy "OrganizationProxy" "$ORG_INSTANCE" "$ORG_CONTRACT" "$ORG_ARGS"
else
    log_skip "skipped: no OrganizationProxy instance discovered on $NETWORK."
    SUMMARY+=("skip|OrganizationProxy|no instance discovered")
fi

# --- AccountProxy --------------------------------------------------------------
log_section "AccountProxy"
BEACON_ORG="${ORG:-$ORG_INSTANCE}"
if [[ -n "$BEACON_ORG" ]]; then
    ACCT_INSTANCE="$(ORG="$BEACON_ORG" "$FIND" account "$NETWORK" "$ENV")"
    if [[ -n "$ACCT_INSTANCE" ]]; then
        # beacon = the Organization (data is empty); identical encoding to the factory's
        # abi.encode(address(this), "").
        ACCT_ARGS="$(cast abi-encode "ctor(address,bytes)" "$BEACON_ORG" 0x)"
        verify_proxy "AccountProxy" "$ACCT_INSTANCE" "$ACCT_CONTRACT" "$ACCT_ARGS"
    else
        log_skip "skipped: no AccountProxy instance discovered under $BEACON_ORG on $NETWORK."
        SUMMARY+=("skip|AccountProxy|no instance discovered")
    fi
else
    log_skip "skipped: no Organization available to use as the beacon."
    SUMMARY+=("skip|AccountProxy|no beacon org")
fi

# --- Summary -------------------------------------------------------------------
log_section "Summary"
for row in "${SUMMARY[@]}"; do
    IFS='|' read -r st label detail <<< "$row"
    case "$st" in
        ok)   log_ok   "$(printf '%-18s %s' "$label" "$detail")" ;;
        fail) log_err  "$(printf '%-18s %s' "$label" "$detail")" ;;
        skip) log_skip "$(printf '%-18s %s' "$label" "$detail")" ;;
    esac
done

exit $OVERALL

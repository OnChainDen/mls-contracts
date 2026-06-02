#!/bin/bash
# =============================================================================
# Find a Representative Proxy Instance
# =============================================================================
# Discovers one factory-deployed proxy instance (OrganizationProxy or AccountProxy)
# from its on-chain creation event, so you can verify it without hunting for an
# address by hand. Verifying ONE instance per proxy type per chain is enough —
# block explorers auto-match the rest by (identical) bytecode.
#
# Events (see src/interfaces):
#   OrganizationDeployed(address indexed org, bytes32 indexed salt, address indexed deployer)
#       emitted by the OrganizationFactory; the org proxy address is topic1.
#   AccountDeployed(address indexed account, address indexed org, bytes32 indexed salt)
#       emitted by each Organization; the account proxy address is topic1.
#
# It scans backward from the latest block in chunks (so it works on rate-limited
# public RPCs and finds a recent instance quickly).
#
# Usage:
#   ./find_proxy_instance.sh <org|account> <network> [env]
#
# Where:
#   <org|account>  which proxy type to find
#   <network>      RPC alias / chain to query (e.g. mainnet, base, ronin) — resolved
#                  via foundry.toml [rpc_endpoints]
#   [env]          prod | nonprod | auto (default auto) — selects the OrganizationFactory
#                  for org lookups; derived from <network> when auto
#
# Environment:
#   FACTORY      CREATE2 factory (default arachnid) — selects the org_factory address
#   ORG          for account lookups: restrict to this Organization (default: discover one)
#   CHUNK        block window per query (default 5000)
#   MAX_CHUNKS   max windows to scan back (default 40 ≈ CHUNK*40 blocks). Raise for older instances.
#   FROM_BLOCK   floor block to stop scanning at (default 0)
#
# Output: the discovered instance address on stdout (empty if none found). Diagnostics
# and a ready-to-run `make verify` command go to stderr.
# =============================================================================

# NOTE: no `set -e` — individual cast calls may fail (RPC hiccups) and we handle them.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT" || exit 1

source "$SCRIPT_DIR/lib/deployment_config.sh"
source "$SCRIPT_DIR/lib/output.sh"
validate_prerequisites  # deployment.toml + yq

if ! command -v cast &> /dev/null; then
    echo "Error: cast (Foundry) is required but not installed" >&2
    exit 1
fi

TYPE="$1"
NETWORK="$2"
ENV_IN="${3:-auto}"
FACTORY="${FACTORY:-arachnid}"
CHUNK="${CHUNK:-5000}"
MAX_CHUNKS="${MAX_CHUNKS:-40}"
FLOOR="${FROM_BLOCK:-0}"

validate_factory "$FACTORY"

if [[ -z "$TYPE" || -z "$NETWORK" ]]; then
    echo "Usage: ./find_proxy_instance.sh <org|account> <network> [env]" >&2
    exit 1
fi

# Resolve env (selects the OrganizationFactory address for org lookups).
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

# Scan creation events backward from `latest` in CHUNK-sized windows; print the most
# recent matching log's topic1 (the proxy address), or empty if none found.
# Usage: scan_topic1 "<event sig>" [emitter address]
scan_topic1() {
    local event="$1" emitter="${2:-}"
    local -a addr_flag=()
    [[ -n "$emitter" ]] && addr_flag=(--address "$emitter")

    local latest to from i topic1
    latest="$(cast block-number --rpc-url "$NETWORK" 2>/dev/null)"
    if [[ -z "$latest" || ! "$latest" =~ ^[0-9]+$ ]]; then
        log_err "could not read latest block from '$NETWORK' (is the RPC reachable?)"
        return 1
    fi

    to="$latest"
    for ((i = 0; i < MAX_CHUNKS; i++)); do
        (( to < FLOOR )) && break
        from=$(( to - CHUNK + 1 ))
        (( from < FLOOR )) && from=$FLOOR

        topic1="$(cast logs "${addr_flag[@]}" "$event" \
            --from-block "$from" --to-block "$to" --rpc-url "$NETWORK" --json 2>/dev/null \
            | yq -p=json -r '.[-1].topics[1] // ""' 2>/dev/null)"

        if [[ -n "$topic1" && "$topic1" != "null" ]]; then
            # topic1 is a 32-byte word; the address is its low 20 bytes (last 40 hex).
            local lower="0x${topic1: -40}"
            cast to-check-sum-address "$lower" 2>/dev/null || echo "$lower"
            return 0
        fi
        (( from <= FLOOR )) && break
        to=$(( from - 1 ))
    done
    return 1
}

case "$TYPE" in
    org)
        FACTORY_ADDR="$(get_org_factory_address "$FACTORY" "$ENV")"
        log_dim "scanning OrganizationDeployed from factory $FACTORY_ADDR on $NETWORK (env $ENV)..."
        INSTANCE="$(scan_topic1 "OrganizationDeployed(address,bytes32,address)" "$FACTORY_ADDR")"
        CONTRACT="src/organization/OrganizationProxy.sol:OrganizationProxy"
        ;;
    account)
        # Narrow to one Organization's events (RPC-friendly): use $ORG, else discover one.
        ORG_ADDR="${ORG:-}"
        if [[ -z "$ORG_ADDR" ]]; then
            log_dim "discovering an Organization first (set ORG=0x... to skip)..."
            ORG_ADDR="$(FACTORY="$FACTORY" scan_topic1 "OrganizationDeployed(address,bytes32,address)" "$(get_org_factory_address "$FACTORY" "$ENV")")"
        fi
        if [[ -z "$ORG_ADDR" ]]; then
            log_warn "no Organization found, so cannot locate an AccountProxy."
            exit 0
        fi
        log_dim "scanning AccountDeployed from Organization $ORG_ADDR on $NETWORK..."
        INSTANCE="$(scan_topic1 "AccountDeployed(address,address,bytes32)" "$ORG_ADDR")"
        CONTRACT="src/account/AccountProxy.sol:AccountProxy"
        ;;
    *)
        log_err "type must be 'org' or 'account'"
        exit 1
        ;;
esac

if [[ -z "$INSTANCE" ]]; then
    log_warn "no $TYPE proxy creation event found in the scanned range (last $((CHUNK * MAX_CHUNKS)) blocks)."
    log_dim "raise MAX_CHUNKS / CHUNK or set FROM_BLOCK to the factory's deploy block, or use a private/archive RPC."
    exit 0
fi

# Address on stdout (for scripting); guidance on stderr.
echo "$INSTANCE"
log_ok "found instance: ${C_BOLD}${INSTANCE}${C_RESET}"
log_dim "verify with: make verify-proxies NETWORK=$NETWORK ENV=$ENV  (computes constructor args)"

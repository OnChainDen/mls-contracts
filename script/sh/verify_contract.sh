#!/bin/bash
# =============================================================================
# Verify a Single Contract Script
# =============================================================================
# Verifies one already-deployed contract on a block explorer, using the same
# verifier/API-key handling as verify_contracts.sh (shared via lib/verifier.sh).
# This is what `make verify` calls.
#
# Like verify_contracts.sh, this does NOT need an RPC or the broadcast/ directory:
# forge recompiles from source and submits to the explorer API. Run it from the
# exact commit that was deployed so the recompiled bytecode matches on-chain.
#
# Usage:
#   ./verify_contract.sh <address> <contract> <chain> [verifier] [verifier_url]
#
# Where:
#   <address>       deployed contract address
#   <contract>      contract identifier <path>:<Name>
#                   (e.g. src/organization/OrganizationFactory.sol:OrganizationFactory)
#   <chain>         chain id or forge chain alias passed to `forge --chain`
#   [verifier]      etherscan (default) | sourcify | blockscout | oklink | custom
#   [verifier_url]  optional --verifier-url. For blockscout it is auto-derived from
#                   the explorer origin in explorers.toml ("<origin>/api/") when omitted;
#                   pass it to override. Required for sourcify/custom on chains that
#                   need a specific endpoint.
#
# Environment (all optional unless noted):
#   ETHERSCAN_API_KEY   required when verifier=etherscan (read from env or .env)
#   VERIFIER_API_KEY    API key for key-gated non-etherscan verifiers (oklink/custom)
#   CONSTRUCTOR_ARGS    ABI-encoded constructor args (hex), if the contract has any
#   GUESS_CONSTRUCTOR_ARGS=1  extract constructor args from the on-chain creation tx
#                       instead of passing CONSTRUCTOR_ARGS (adds --guess-constructor-args
#                       --rpc-url <network>). Works ONLY for contracts created by a
#                       top-level tx (EOA-deployed) — NOT factory-created ones (Etherscan
#                       errors "...not supported for contracts created by contracts"). For
#                       the factory-deployed proxies use `make verify-proxies` / verify_proxies.sh,
#                       which computes the args.
#   LIBRARIES           raw forge --libraries flags, e.g.
#                       "--libraries path:Name:0xaddr --libraries path:Name2:0xaddr"
#   DOTENV              path to the .env file to read keys from (default <repo-root>/.env)
#   DRY_RUN=1           print the forge command without executing it
#
# Examples:
#   ./verify_contract.sh 0xabc.. src/account/AccountImplementation.sol:AccountImplementation mainnet
#   CONSTRUCTOR_ARGS=0x000..f6cb.. ./verify_contract.sh 0xda35.. \
#     src/organization/OrganizationFactory.sol:OrganizationFactory base
#   ./verify_contract.sh 0xdef.. src/safe-module/BatchedTransaction.sol:BatchedTransaction \
#     <network> blockscout   # verifier URL auto-derived from explorers.toml as <origin>/api/
#
# Exit code: forge's verification result (0 on success / already verified).
# =============================================================================

# NOTE: We deliberately do NOT use `set -e`. Argument validation and the verifier
# flag builder use explicit `exit 1`, and the final `exec` returns forge's own exit
# code, so a global errexit would only mask the per-step error messages.

# =============================================================================
# Source Shared Configuration
# =============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$REPO_ROOT/.." && pwd)"
# Run from repo root so foundry.toml / .env resolve regardless of caller CWD.
cd "$REPO_ROOT" || exit 1

source "$SCRIPT_DIR/lib/verifier.sh"
source "$SCRIPT_DIR/lib/output.sh"

if ! command -v forge &> /dev/null; then
    echo "Error: forge (Foundry) is required but not installed" >&2
    exit 1
fi

# =============================================================================
# Argument Parsing
# =============================================================================
CONTRACT_ADDRESS="${1:-}"
CONTRACT_NAME="${2:-}"
CHAIN="${3:-}"
VERIFIER="${4:-etherscan}"
VERIFIER_URL="${5:-}"

if [[ -z "$CONTRACT_ADDRESS" || -z "$CONTRACT_NAME" || -z "$CHAIN" ]]; then
    echo "Error: address, contract, and chain are required." >&2
    echo "Usage: ./verify_contract.sh <address> <contract> <chain> [verifier] [verifier_url]" >&2
    exit 1
fi

case "$CHAIN" in
    local|localhost|127.0.0.1|http://127.0.0.1:8545)
        echo "Error: '$CHAIN' is not a verifiable network. Pass a real chain (e.g. mainnet, base, 2020)." >&2
        exit 1
        ;;
esac

# =============================================================================
# Build verifier flags (loads API keys from env or .env; derives Blockscout URL
# from explorers.toml when omitted; see lib/verifier.sh)
# =============================================================================
build_verifier_flags "$CHAIN"

# =============================================================================
# Assemble and run
# =============================================================================
# Unquoted $VERIFIER_FLAGS / $LIBRARIES expand into separate tokens (no spaces in values).
cmd=(forge verify-contract "$CONTRACT_ADDRESS" "$CONTRACT_NAME" --chain "$CHAIN" --watch)
cmd+=($VERIFIER_FLAGS)

# Constructor args: explicit CONSTRUCTOR_ARGS wins; otherwise, if GUESS_CONSTRUCTOR_ARGS
# is set, let forge extract them from the on-chain creation tx (needs an RPC, so pass
# --rpc-url <network>). This is the turnkey path for factory-deployed instances (e.g.
# OrganizationProxy / AccountProxy) where the args vary per instance.
if [[ -n "${CONSTRUCTOR_ARGS:-}" ]]; then
    cmd+=(--constructor-args "$CONSTRUCTOR_ARGS")
elif [[ "${GUESS_CONSTRUCTOR_ARGS:-}" == "1" || "${GUESS_CONSTRUCTOR_ARGS:-}" == "true" ]]; then
    cmd+=(--guess-constructor-args --rpc-url "$CHAIN")
fi

[[ -n "${LIBRARIES:-}" ]] && cmd+=($LIBRARIES)

LINK="$(explorer_address_url "$CHAIN" "$CONTRACT_ADDRESS")"

printf '\n%s%s%s %son %s%s\n' "$C_BOLD" "$CONTRACT_NAME" "$C_RESET" "$C_DIM" "$CHAIN" "$C_RESET"
printf '  %saddress %s  %s\n' "$C_DIM" "$C_RESET" "$CONTRACT_ADDRESS"
printf '  %sverifier%s  %s%s\n' "$C_DIM" "$C_RESET" "$VERIFIER" "${VERIFIER_URL:+ (url: $VERIFIER_URL)}"
printf '  %sapi key %s  %s\n' "$C_DIM" "$C_RESET" "$API_KEY_SOURCE_LABEL"
printf '  %s%s%s\n' "$C_DIM" "$(redact_cmd "${cmd[@]}")" "$C_RESET"

if [[ "${DRY_RUN:-}" == "1" || "${DRY_RUN:-}" == "true" ]]; then
    [[ -n "$LINK" ]] && printf '  %sexplorer%s  %s\n' "$C_DIM" "$C_RESET" "$LINK"
    exit 0
fi

# Run (streaming forge output), then print a colored result + the explorer link so it
# can be opened to confirm. `exec` is intentionally avoided so we can print after.
"${cmd[@]}"
rc=$?

if [[ $rc -eq 0 ]]; then
    printf '\n  %s✓ verified%s%s\n' "$C_GREEN" "$C_RESET" "${LINK:+  $LINK}"
else
    printf '\n  %s✗ verification failed%s (forge exit %d)%s\n' "$C_RED" "$C_RESET" "$rc" "${LINK:+ — check $LINK}"
fi
exit $rc

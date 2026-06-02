#!/bin/bash
# =============================================================================
# Shared Block-Explorer Verification Library
# =============================================================================
# Shared helpers for building `forge verify-contract` verifier flags, used by
# both verify_contract.sh (single contract) and verify_contracts.sh (all
# platform contracts) so the two stay consistent. Source this file after
# REPO_ROOT is defined.
#
# Usage:
#   source "$SCRIPT_DIR/lib/verifier.sh"
#   build_verifier_flags                  # sets VERIFIER_FLAGS + API_KEY_SOURCE_LABEL
#   forge verify-contract <addr> <name> --chain "$CHAIN" $VERIFIER_FLAGS ...
#
# Inputs (variables/env, all optional except as noted):
#   VERIFIER          etherscan (default) | sourcify | blockscout | oklink | custom
#   VERIFIER_URL      --verifier-url value (required for custom; needed for clones/instances)
#   ETHERSCAN_API_KEY API key for the etherscan verifier (required when VERIFIER=etherscan)
#   VERIFIER_API_KEY  API key for key-gated non-etherscan verifiers (oklink/custom)
#   DOTENV            path to a .env file to read keys from (default: <repo-root>/.env)
#
# Key resolution: a key already set in the environment always wins; otherwise it
# is read from the .env file. Only the requested key is parsed (the file is not
# sourced), so arbitrary .env content is never executed.
# =============================================================================

# Load <var_name> from the .env file unless it is already set in the environment.
# Records where the value came from in <var_name>_SOURCE for display.
load_key_from_dotenv() {
    local var_name="$1"
    local dotenv_file="${DOTENV:-$REPO_ROOT/.env}"
    printf -v "${var_name}_SOURCE" '%s' "environment"

    # Real environment wins; nothing to load if already set or no .env file.
    # Use if/return (not `&& return`) so this stays safe if a caller sets `set -e`.
    if [[ -n "${!var_name:-}" ]]; then return; fi
    [[ -f "$dotenv_file" ]] || return

    local line value
    line="$(grep -E "^[[:space:]]*(export[[:space:]]+)?${var_name}[[:space:]]*=" "$dotenv_file" | tail -1)"
    [[ -n "$line" ]] || return

    # Strip everything up to the '=', surrounding whitespace, and optional quotes.
    value="${line#*=}"
    value="$(printf '%s' "$value" | sed -E "s/^[[:space:]]+//; s/[[:space:]]+\$//; s/^\"(.*)\"\$/\1/; s/^'(.*)'\$/\1/")"
    [[ -n "$value" ]] || return

    export "$var_name=$value"
    printf -v "${var_name}_SOURCE" '%s' "$dotenv_file"
}

# Build the verifier portion of the forge verify-contract command line.
# Usage: build_verifier_flags <chain>
# Loads API keys from .env if needed, then sets:
#   VERIFIER_FLAGS        --verifier ... [--verifier-url ...] [--*-api-key ...]
#   API_KEY_SOURCE_LABEL  human-readable note about where the key came from
#   VERIFIER_URL          may be populated by Blockscout auto-derivation (see below)
# Exits 1 if the etherscan verifier is selected without a key.
#
# Key handling depends on the verifier:
#   - etherscan (and Etherscan clones via --verifier-url): --etherscan-api-key (required)
#   - sourcify / most blockscout: no key
#   - oklink / custom / key-gated explorers: --verifier-api-key (optional here; forge
#     will error if the chosen verifier actually requires one)
#
# Blockscout URL auto-derivation: Blockscout serves its API on the same host as the
# explorer UI, so when VERIFIER=blockscout and no VERIFIER_URL is given, derive it
# from the explorer origin in explorers.toml as "<origin>/api/". This is NOT valid
# for etherscan (different API host) or sourcify (uses a "/server" URL), so it is
# applied only for blockscout.
build_verifier_flags() {
    local verifier="${VERIFIER:-etherscan}"
    local chain="${1:-}"
    local dotenv_file="${DOTENV:-$REPO_ROOT/.env}"

    load_key_from_dotenv ETHERSCAN_API_KEY
    load_key_from_dotenv VERIFIER_API_KEY

    # forge binds ETHERSCAN_API_KEY / VERIFIER_API_KEY as env defaults for its
    # --etherscan-api-key / --verifier-api-key args. An EMPTY value in the environment
    # (e.g. exported empty by a Makefile or shell) is treated as "set to empty" and
    # breaks verifier resolution ("ETHERSCAN_API_KEY must be set ...") even when a real
    # key is passed on the CLI. Drop empties so forge only ever sees real values.
    [[ -z "${ETHERSCAN_API_KEY:-}" ]] && unset ETHERSCAN_API_KEY
    [[ -z "${VERIFIER_API_KEY:-}" ]] && unset VERIFIER_API_KEY

    if [[ "$verifier" == "blockscout" && -z "${VERIFIER_URL:-}" && -n "$chain" ]]; then
        local derived_base
        derived_base="$(explorer_base_url "$chain")"
        [[ -n "$derived_base" ]] && VERIFIER_URL="$derived_base/api/"
    fi

    VERIFIER_FLAGS="--verifier $verifier"
    [[ -n "${VERIFIER_URL:-}" ]] && VERIFIER_FLAGS="$VERIFIER_FLAGS --verifier-url $VERIFIER_URL"

    if [[ "$verifier" == "etherscan" ]]; then
        if [[ -z "${ETHERSCAN_API_KEY:-}" ]]; then
            echo "Error: ETHERSCAN_API_KEY must be set for the etherscan verifier." >&2
            echo "       Set it in your environment, or add it to a .env file (looked in: $dotenv_file)." >&2
            echo "       A single Etherscan V2 key covers Ethereum/Optimism/Base/Arbitrum/Sepolia." >&2
            echo "       For non-Etherscan chains, pass VERIFIER=blockscout|sourcify (+ VERIFIER_URL)," >&2
            echo "       or VERIFIER=oklink|custom with VERIFIER_API_KEY." >&2
            exit 1
        fi
        VERIFIER_FLAGS="$VERIFIER_FLAGS --etherscan-api-key $ETHERSCAN_API_KEY"
        API_KEY_SOURCE_LABEL="loaded from $ETHERSCAN_API_KEY_SOURCE"
    elif [[ -n "${VERIFIER_API_KEY:-}" ]]; then
        VERIFIER_FLAGS="$VERIFIER_FLAGS --verifier-api-key $VERIFIER_API_KEY"
        API_KEY_SOURCE_LABEL="loaded from $VERIFIER_API_KEY_SOURCE"
    else
        API_KEY_SOURCE_LABEL="none (verifier requires no key)"
    fi
}

# Print the explorer origin (e.g. https://etherscan.io) for <chain> from
# explorers.toml (keyed by the NETWORK/--chain value), with any trailing slash
# stripped. Prints nothing if yq is unavailable, the file is missing, or there is
# no entry for the chain. Used both for browse links and to derive the Blockscout
# verifier URL.
# Usage: base="$(explorer_base_url "$CHAIN")"
explorer_base_url() {
    local chain="$1"
    local toml="${EXPLORERS_TOML:-explorers.toml}"

    command -v yq &> /dev/null || return
    [[ -f "$toml" ]] || return

    local base
    base="$(yq -r ".[\"$chain\"]" "$toml" 2>/dev/null)"
    [[ -n "$base" && "$base" != "null" ]] || return

    printf '%s' "${base%/}"  # strip a trailing slash
}

# Print the block-explorer "address page" URL for <chain> + <address>: the explorer
# origin from explorers.toml + the /address/<addr>#code route. The #code fragment
# opens the verified-source tab on Etherscan-family explorers and is a harmless
# no-op elsewhere (fragments are client-side only). Prints nothing if there is no
# explorer entry for the chain.
# Usage: url="$(explorer_address_url "$CHAIN" "$addr")"
explorer_address_url() {
    local chain="$1" addr="$2" base
    base="$(explorer_base_url "$chain")"
    [[ -n "$base" ]] || return
    printf '%s/address/%s#code' "$base" "$addr"
}

# Print a forge command with API-key values masked, for safe display/logging. The
# value following --etherscan-api-key or --verifier-api-key is replaced with '***'
# (the real command array, with the real key, is still what gets executed).
# Usage: echo "$(redact_cmd "${cmd[@]}")"
redact_cmd() {
    local out="" prev="" tok
    for tok in "$@"; do
        if [[ "$prev" == "--etherscan-api-key" || "$prev" == "--verifier-api-key" ]]; then
            out+=" ***"
        else
            out+=" $tok"
        fi
        prev="$tok"
    done
    printf '%s' "${out# }"
}

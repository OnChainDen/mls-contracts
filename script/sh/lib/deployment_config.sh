#!/bin/bash
# =============================================================================
# Shared Deployment Configuration Library
# =============================================================================
# This file provides shared functions and constants for reading deployment
# configuration from deployment.toml. Source this file from other scripts.
#
# Usage:
#   source "$(dirname "$0")/lib/deployment_config.sh"
#
# =============================================================================

# =============================================================================
# Constants
# =============================================================================

# Path to deployment.toml (relative to repo root)
DEPLOYMENT_TOML="deployment.toml"

# Library paths for --libraries flag (these are constants, not addresses)
LIB_ORG_POLICY_PATH="src/organization/libraries/LibOrganizationPolicy.sol:LibOrganizationPolicy"
LIB_ORG_ADMIN_PATH="src/organization/libraries/LibOrganizationAdmin.sol:LibOrganizationAdmin"
LIB_ORG_INIT_PATH="src/organization/libraries/LibOrganizationInitialization.sol:LibOrganizationInitialization"
LIB_ORG_ACCOUNT_SIG_PATH="src/organization/libraries/LibOrganizationAccountSignature.sol:LibOrganizationAccountSignature"

# =============================================================================
# Validation Functions
# =============================================================================

# Validate that deployment.toml exists and yq is available
# Usage: validate_prerequisites
validate_prerequisites() {
    if [[ ! -f "$DEPLOYMENT_TOML" ]]; then
        echo "Error: deployment.toml not found"
        exit 1
    fi

    if ! command -v yq &> /dev/null; then
        echo "Error: yq is required but not installed"
        echo "Install with: brew install yq"
        exit 1
    fi
}

# Validate factory argument
# Usage: validate_factory "arachnid"
# Valid values: arachnid, den-nonprod, den-prod
validate_factory() {
    local factory="$1"

    if [[ -z "$factory" ]]; then
        echo "Error: Factory argument required"
        echo "Usage: <arachnid|den-nonprod|den-prod>"
        exit 1
    fi

    case "$factory" in
        arachnid|den-nonprod|den-prod)
            # Valid factory name
            ;;
        *)
            echo "Error: Invalid factory '$factory'"
            echo "Valid options: arachnid, den-nonprod, den-prod"
            exit 1
            ;;
    esac
}

# =============================================================================
# Generic Config Reading
# =============================================================================

# Read a value from deployment.toml
# Usage: get_config ".factory[\"arachnid\"].factory"
# Returns: The value, or exits with error if not found
get_config() {
    local path="$1"
    local value
    value=$(yq -r "$path" "$DEPLOYMENT_TOML")

    if [[ -z "$value" || "$value" == "null" ]]; then
        echo "Error: Config not found at path: $path" >&2
        exit 1
    fi

    echo "$value"
}

# Read a value from deployment.toml (silent version - returns empty on failure)
# Usage: get_config_silent ".factory[\"arachnid\"].factory"
# Returns: The value, or empty string if not found
get_config_silent() {
    local path="$1"
    local value
    value=$(yq -r "$path" "$DEPLOYMENT_TOML" 2>/dev/null)

    if [[ "$value" == "null" ]]; then
        echo ""
    else
        echo "$value"
    fi
}

# =============================================================================
# Factory Address Getters
# =============================================================================

# Get factory address for a given factory
# Usage: get_factory_address "arachnid"
get_factory_address() {
    local factory="$1"
    get_config ".factory[\"$factory\"].factory"
}

# Get factory deployer address for a given factory
# Usage: get_factory_deployer "arachnid"
get_factory_deployer() {
    local factory="$1"
    get_config ".factory[\"$factory\"].factory_deployer"
}

# Get LibOrganizationPolicy address for a given factory
# Usage: get_lib_org_policy "arachnid"
get_lib_org_policy() {
    local factory="$1"
    get_config ".factory[\"$factory\"].lib_org_policy"
}

# Get LibOrganizationAdmin address for a given factory
# Usage: get_lib_org_admin "arachnid"
get_lib_org_admin() {
    local factory="$1"
    get_config ".factory[\"$factory\"].lib_org_admin"
}

# Get LibOrganizationInitialization address for a given factory
# Usage: get_lib_org_init "arachnid"
get_lib_org_init() {
    local factory="$1"
    get_config ".factory[\"$factory\"].lib_org_init"
}

# Get LibOrganizationAccountSignature address for a given factory
# Usage: get_lib_org_account_sig "arachnid"
get_lib_org_account_sig() {
    local factory="$1"
    get_config ".factory[\"$factory\"].lib_org_account_sig"
}

# =============================================================================
# Safe Config Getters (from [safe.*] sections)
# =============================================================================

# Get guardian executor EOA address
# Usage: get_guardian_executor "nonprod"
get_guardian_executor() {
    local env="$1"
    get_config ".safe.$env.guardian_executor_eoa"
}

# Get guardian Safe owner address (first owner)
# Usage: get_guardian_safe_owner "nonprod"
get_guardian_safe_owner() {
    local env="$1"
    get_config ".safe.$env.guardian_safe_owner_1"
}

# Get admin Safe owner address (first owner)
# Usage: get_admin_safe_owner "nonprod"
get_admin_safe_owner() {
    local env="$1"
    get_config ".safe.$env.admin_safe_owner_1"
}

# =============================================================================
# Environment-Dependent Address Getters (from [factory.*.env.*] sections)
# =============================================================================

# Get guardian Safe address for a factory/env combination
# Usage: get_guardian_safe_address "arachnid" "nonprod"
get_guardian_safe_address() {
    local factory="$1"
    local env="$2"
    get_config ".factory[\"$factory\"].env.$env.guardian_safe"
}

# Get admin Safe address for a factory/env combination
# Usage: get_admin_safe_address "arachnid" "nonprod"
get_admin_safe_address() {
    local factory="$1"
    local env="$2"
    get_config ".factory[\"$factory\"].env.$env.admin_safe"
}

# Get OrganizationFactory address for a factory/env combination
# Usage: get_org_factory_address "arachnid" "nonprod"
get_org_factory_address() {
    local factory="$1"
    local env="$2"
    get_config ".factory[\"$factory\"].env.$env.org_factory"
}

# Get ImplementationWhitelistProxy address for a factory/env combination
# Usage: get_whitelist_proxy_address "arachnid" "nonprod"
get_whitelist_proxy_address() {
    local factory="$1"
    local env="$2"
    get_config ".factory[\"$factory\"].env.$env.whitelist_proxy"
}

# Get guardian module address for a factory/env combination
# Usage: get_guardian_module_address "arachnid" "nonprod"
get_guardian_module_address() {
    local factory="$1"
    local env="$2"
    get_config ".factory[\"$factory\"].env.$env.guardian_safe_executor_module"
}

# =============================================================================
# Library Flags Builders
# =============================================================================

# Build --libraries flags for independent libraries (Policy, Admin)
# Usage: FLAGS=$(build_independent_libraries_flags "arachnid")
build_independent_libraries_flags() {
    local factory="$1"
    local policy_addr
    local admin_addr

    policy_addr=$(get_lib_org_policy "$factory")
    admin_addr=$(get_lib_org_admin "$factory")

    echo "--libraries ${LIB_ORG_POLICY_PATH}:${policy_addr} --libraries ${LIB_ORG_ADMIN_PATH}:${admin_addr}"
}

# Build --libraries flags for all libraries
# Usage: FLAGS=$(build_all_libraries_flags "arachnid")
build_all_libraries_flags() {
    local factory="$1"
    local policy_addr
    local admin_addr
    local init_addr
    local account_sig_addr

    policy_addr=$(get_lib_org_policy "$factory")
    admin_addr=$(get_lib_org_admin "$factory")
    init_addr=$(get_lib_org_init "$factory")
    account_sig_addr=$(get_lib_org_account_sig "$factory")

    echo "--libraries ${LIB_ORG_POLICY_PATH}:${policy_addr} --libraries ${LIB_ORG_ADMIN_PATH}:${admin_addr} --libraries ${LIB_ORG_INIT_PATH}:${init_addr} --libraries ${LIB_ORG_ACCOUNT_SIG_PATH}:${account_sig_addr}"
}

# =============================================================================
# Helper Functions
# =============================================================================

# Extract an address from forge script output given a key pattern
# Usage: extract_address "output" "KeyName"
# Returns: address (0x...) or empty string if not found
extract_address() {
    local output="$1"
    local key="$2"
    # Match lines like "  KeyName: 0x..." or "  KeyName [STATUS]: 0x..."
    # Use grep -o to extract just the address part (more portable than sed with \s)
    echo "$output" | grep -E "^[[:space:]]+${key}([[:space:]]+\[.*\])?:[[:space:]]+0x[a-fA-F0-9]{40}" | head -1 | grep -oE "0x[a-fA-F0-9]{40}"
}

# Print a TOML key-value pair
# Usage: print_toml "key" "value"
print_toml() {
    local key="$1"
    local value="$2"
    printf "%s = \"%s\"\n" "$key" "$value"
}

#!/usr/bin/env bash
# ==============================================================================
# check-headers.sh - Verify SPDX license and copyright headers in Solidity files
# ==============================================================================
#
# This script ensures all .sol files in src/ and script/ have the correct
# SPDX license identifier and copyright notice at the top of the file.
#
# Expected header format:
#   // SPDX-License-Identifier: UNLICENSED
#   // Copyright (c) 2026 Den Technologies Inc. All rights reserved.
#
# USAGE:
#   ./script/sh/check-headers.sh
#
# EXIT CODES:
#   0 - All headers are correct
#   1 - One or more files have incorrect headers
#
# ==============================================================================

# ------------------------------------------------------------------------------
# STRICT MODE - Fail loudly on any error
# ------------------------------------------------------------------------------
set -euo pipefail

# ------------------------------------------------------------------------------
# CONSTANTS
# ------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Expected header lines
EXPECTED_LICENSE="// SPDX-License-Identifier: UNLICENSED"
EXPECTED_COPYRIGHT="// Copyright (c) 2026 Den Technologies Inc. All rights reserved."

# ------------------------------------------------------------------------------
# COLORS (for terminal output)
# ------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ------------------------------------------------------------------------------
# LOGGING FUNCTIONS
# ------------------------------------------------------------------------------
log_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# ------------------------------------------------------------------------------
# MAIN LOGIC
# ------------------------------------------------------------------------------
main() {
    echo "Checking Solidity file headers..."
    echo ""
    
    local errors=0
    local checked=0
    
    # Find all .sol files in src/ and script/, excluding lib/
    while IFS= read -r -d '' file; do
        checked=$((checked + 1))
        
        # Read first two lines
        local line1 line2
        line1=$(head -n 1 "$file")
        line2=$(head -n 2 "$file" | tail -n 1)
        
        local file_has_error=0
        
        # Check SPDX license
        if [[ "$line1" != "$EXPECTED_LICENSE" ]]; then
            log_error "$file"
            echo "         Line 1 - Expected: $EXPECTED_LICENSE"
            echo "         Line 1 - Found:    $line1"
            file_has_error=1
        fi
        
        # Check copyright
        if [[ "$line2" != "$EXPECTED_COPYRIGHT" ]]; then
            if [[ $file_has_error -eq 0 ]]; then
                log_error "$file"
            fi
            echo "         Line 2 - Expected: $EXPECTED_COPYRIGHT"
            echo "         Line 2 - Found:    $line2"
            file_has_error=1
        fi
        
        if [[ $file_has_error -eq 1 ]]; then
            errors=$((errors + 1))
            echo ""
        fi
        
    done < <(find "$PROJECT_ROOT/src" "$PROJECT_ROOT/script" -name "*.sol" -type f -print0 2>/dev/null)
    
    # Summary
    echo "----------------------------------------"
    if [[ $errors -gt 0 ]]; then
        log_error "Found $errors file(s) with incorrect headers (checked $checked files)"
        echo ""
        echo "Expected header format:"
        echo "  $EXPECTED_LICENSE"
        echo "  $EXPECTED_COPYRIGHT"
        exit 1
    else
        log_success "All $checked file(s) have correct headers"
        exit 0
    fi
}

# Run main function
main "$@"

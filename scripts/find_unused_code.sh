#!/bin/bash

# find_unused_code.sh
# Scans Solidity files in src/ for potentially unused functions, constants, events, errors, structs, and enums.
#
# Usage:
#   ./scripts/find_unused_code.sh              # Only search in src/
#   ./scripts/find_unused_code.sh --with-tests # Also search in test/ directory
#   ./scripts/find_unused_code.sh --verbose    # Show more details

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

SRC_DIR="src"
SEARCH_DIRS="$SRC_DIR"
VERBOSE=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --with-tests)
            if [[ -d "test" ]]; then
                SEARCH_DIRS="$SRC_DIR test"
            fi
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --with-tests  Also search in test/ directory for usages"
            echo "  --verbose     Show more details about each finding"
            echo "  --help, -h    Show this help message"
            exit 0
            ;;
    esac
done

# Temporary files for storing results
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Unused Code Scanner for Solidity     ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${CYAN}Source directory:${NC} $SRC_DIR"
echo -e "${CYAN}Search directories:${NC} $SEARCH_DIRS"
echo ""

# Function to count occurrences across search directories
count_occurrences() {
    local name="$1"
    local count=0
    for dir in $SEARCH_DIRS; do
        if [[ -d "$dir" ]]; then
            local dir_count
            dir_count=$(grep -rw "$name" "$dir" --include="*.sol" 2>/dev/null | wc -l | tr -d ' ')
            count=$((count + dir_count))
        fi
    done
    echo "$count"
}

# Function to get line number of definition
get_line_number() {
    local file="$1"
    local name="$2"
    local type="$3"

    case "$type" in
        function)
            grep -n "function[[:space:]]\+$name[[:space:]]*(" "$file" 2>/dev/null | head -1 | cut -d: -f1
            ;;
        constant)
            grep -n "constant[[:space:]]\+$name" "$file" 2>/dev/null | head -1 | cut -d: -f1
            ;;
        event)
            grep -n "event[[:space:]]\+$name[[:space:]]*(" "$file" 2>/dev/null | head -1 | cut -d: -f1
            ;;
        error)
            grep -n "error[[:space:]]\+$name" "$file" 2>/dev/null | head -1 | cut -d: -f1
            ;;
        struct)
            grep -n "struct[[:space:]]\+$name[[:space:]]*{" "$file" 2>/dev/null | head -1 | cut -d: -f1
            ;;
        enum)
            grep -n "enum[[:space:]]\+$name[[:space:]]*{" "$file" 2>/dev/null | head -1 | cut -d: -f1
            ;;
    esac
}

# Function to extract and check usage
check_usage() {
    local file="$1"
    local pattern="$2"
    local type="$3"

    # Extract names from the file
    grep -oE "$pattern" "$file" 2>/dev/null | while read -r match; do
        # Extract the name from the match based on type
        local name
        case "$type" in
            constant)
                name=$(echo "$match" | sed -E 's/.*constant[[:space:]]+([A-Z_][A-Z0-9_]*).*/\1/')
                ;;
            function)
                name=$(echo "$match" | sed -E 's/function[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/')
                ;;
            event)
                name=$(echo "$match" | sed -E 's/event[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/')
                ;;
            error)
                name=$(echo "$match" | sed -E 's/error[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/')
                ;;
            struct)
                name=$(echo "$match" | sed -E 's/struct[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/')
                ;;
            enum)
                name=$(echo "$match" | sed -E 's/enum[[:space:]]+([a-zA-Z_][a-zA-Z0-9_]*).*/\1/')
                ;;
        esac

        # Skip if we couldn't extract a name
        if [[ -z "$name" || "$name" == "$match" ]]; then
            continue
        fi

        # Skip common false positives (keywords)
        if [[ "$name" == "function" || "$name" == "event" || "$name" == "error" || \
              "$name" == "struct" || "$name" == "enum" || "$name" == "constant" ]]; then
            continue
        fi

        # Count occurrences in all search directories
        local count
        count=$(count_occurrences "$name")

        # Get line number
        local line_num
        line_num=$(get_line_number "$file" "$name" "$type")

        # If count is 1, it's only defined but never used
        if [[ "$count" -eq 1 ]]; then
            echo "$type|$name|$file|$line_num"
        fi
    done
}

echo -e "${YELLOW}Scanning Solidity files in $SRC_DIR...${NC}"
echo ""

# Find all .sol files in src/ and process them
find "$SRC_DIR" -name "*.sol" | sort | while read -r file; do
    # Check functions
    check_usage "$file" 'function[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(' "function" >> "$TEMP_DIR/functions.txt" 2>/dev/null || true

    # Check constants (look for constant followed by uppercase name)
    check_usage "$file" 'constant[[:space:]]+[A-Z_][A-Z0-9_]*' "constant" >> "$TEMP_DIR/constants.txt" 2>/dev/null || true

    # Check events
    check_usage "$file" 'event[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(' "event" >> "$TEMP_DIR/events.txt" 2>/dev/null || true

    # Check errors
    check_usage "$file" 'error[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*[\(\;]' "error" >> "$TEMP_DIR/errors.txt" 2>/dev/null || true

    # Check structs
    check_usage "$file" 'struct[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\{' "struct" >> "$TEMP_DIR/structs.txt" 2>/dev/null || true

    # Check enums
    check_usage "$file" 'enum[[:space:]]+[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\{' "enum" >> "$TEMP_DIR/enums.txt" 2>/dev/null || true
done

# Print results
print_results() {
    local file="$1"
    local title="$2"
    local color="$3"

    if [[ -f "$file" && -s "$file" ]]; then
        echo -e "${color}$title${NC}"
        echo "----------------------------------------"
        local count=0
        # Sort and deduplicate
        sort -u "$file" | while IFS='|' read -r type name location line_num; do
            count=$((count + 1))
            echo -e "  ${RED}$name${NC}"
            if [[ -n "$line_num" ]]; then
                echo -e "    └── ${location}:${line_num}"
            else
                echo -e "    └── ${location}"
            fi
        done
        echo ""
        return 0
    fi
    return 1
}

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  RESULTS: Potentially Unused Code     ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

found_unused=false
total_count=0

if [[ -f "$TEMP_DIR/functions.txt" && -s "$TEMP_DIR/functions.txt" ]]; then
    found_unused=true
    count=$(sort -u "$TEMP_DIR/functions.txt" | wc -l | tr -d ' ')
    total_count=$((total_count + count))
    print_results "$TEMP_DIR/functions.txt" "UNUSED FUNCTIONS ($count):" "$YELLOW"
fi

if [[ -f "$TEMP_DIR/constants.txt" && -s "$TEMP_DIR/constants.txt" ]]; then
    found_unused=true
    count=$(sort -u "$TEMP_DIR/constants.txt" | wc -l | tr -d ' ')
    total_count=$((total_count + count))
    print_results "$TEMP_DIR/constants.txt" "UNUSED CONSTANTS ($count):" "$YELLOW"
fi

if [[ -f "$TEMP_DIR/events.txt" && -s "$TEMP_DIR/events.txt" ]]; then
    found_unused=true
    count=$(sort -u "$TEMP_DIR/events.txt" | wc -l | tr -d ' ')
    total_count=$((total_count + count))
    print_results "$TEMP_DIR/events.txt" "UNUSED EVENTS ($count):" "$YELLOW"
fi

if [[ -f "$TEMP_DIR/errors.txt" && -s "$TEMP_DIR/errors.txt" ]]; then
    found_unused=true
    count=$(sort -u "$TEMP_DIR/errors.txt" | wc -l | tr -d ' ')
    total_count=$((total_count + count))
    print_results "$TEMP_DIR/errors.txt" "UNUSED ERRORS ($count):" "$YELLOW"
fi

if [[ -f "$TEMP_DIR/structs.txt" && -s "$TEMP_DIR/structs.txt" ]]; then
    found_unused=true
    count=$(sort -u "$TEMP_DIR/structs.txt" | wc -l | tr -d ' ')
    total_count=$((total_count + count))
    print_results "$TEMP_DIR/structs.txt" "UNUSED STRUCTS ($count):" "$YELLOW"
fi

if [[ -f "$TEMP_DIR/enums.txt" && -s "$TEMP_DIR/enums.txt" ]]; then
    found_unused=true
    count=$(sort -u "$TEMP_DIR/enums.txt" | wc -l | tr -d ' ')
    total_count=$((total_count + count))
    print_results "$TEMP_DIR/enums.txt" "UNUSED ENUMS ($count):" "$YELLOW"
fi

if [[ "$found_unused" == false ]]; then
    echo -e "${GREEN}No unused code found!${NC}"
else
    echo -e "${YELLOW}Total potentially unused items: $total_count${NC}"
fi

echo ""
echo -e "${BLUE}========================================${NC}"
echo -e "${CYAN}Note:${NC} This script uses simple pattern matching."
echo "Some results may be false positives if:"
echo "  - The code is used via inheritance"
echo "  - The code is part of an interface (use --with-tests)"
echo "  - The code is used dynamically (e.g., via selectors)"
echo "  - The code will be used in future features"
echo ""
echo -e "Use ${GREEN}--with-tests${NC} to also search test/ directory."
echo "Please manually verify before removing any code."
echo -e "${BLUE}========================================${NC}"

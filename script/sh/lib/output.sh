#!/bin/bash
# =============================================================================
# Shared Output / Pretty-Printing Library
# =============================================================================
# Colors + small logging helpers used by the verification and proxy-discovery
# scripts so they share one consistent style.
#
# Colors are enabled when output is a terminal (stdout OR stderr is a tty) and
# NO_COLOR is unset. The log_* helpers write to STDERR — that keeps stdout clean
# for primary output and machine-readable values (e.g. a discovered address that a
# caller captures with $(...)), while still showing colored diagnostics in a terminal.
# =============================================================================

if [[ -z "${NO_COLOR:-}" && ( -t 1 || -t 2 ) ]]; then
    C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_YELLOW=$'\033[33m'
    C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'
    C_DIM=$'\033[2m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
    C_GREEN=""; C_RED=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""; C_DIM=""; C_BOLD=""; C_RESET=""
fi

# A heavier banner with a title (blank line + bold cyan rule). To stderr.
log_banner() {
    printf '\n%s%s%s\n' "$C_BOLD$C_CYAN" "════════════════════════════════════════════════════════════" "$C_RESET" >&2
    printf '%s %s%s\n'  "$C_BOLD$C_CYAN" "$*" "$C_RESET" >&2
    printf '%s%s%s\n'   "$C_BOLD$C_CYAN" "════════════════════════════════════════════════════════════" "$C_RESET" >&2
}

# A section header (blank line + bold "▸ <title>"). To stderr.
log_section() { printf '\n%s▸ %s%s\n' "$C_BOLD" "$*" "$C_RESET" >&2; }

# Status / info lines (indented). To stderr.
log_info() { printf '  %s\n' "$*" >&2; }
log_dim()  { printf '  %s%s%s\n' "$C_DIM" "$*" "$C_RESET" >&2; }
log_ok()   { printf '  %s✓%s %s\n' "$C_GREEN" "$C_RESET" "$*" >&2; }
log_warn() { printf '  %s!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
log_err()  { printf '  %s✗%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
log_skip() { printf '  %s↷ %s%s\n' "$C_DIM" "$*" "$C_RESET" >&2; }

# A "key: value" line with a dimmed, fixed-width key. To stderr.
# Usage: log_kv "address" "0x..."
log_kv() { printf '  %s%-9s%s %s\n' "$C_DIM" "$1" "$C_RESET" "$2" >&2; }

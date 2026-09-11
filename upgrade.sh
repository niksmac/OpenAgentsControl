#!/usr/bin/env bash
#############################################################################
# OpenAgents Control Upgrade
# Adds NEW components (agents, subagents, ...) to an existing installation
# without touching anything already installed.
#
#   update.sh   = refreshes files you already have
#   upgrade.sh  = adds registered components you are missing (this script)
#
# Compatible with:
# - macOS (bash 3.2+)
# - Linux (bash 3.2+)
# - Windows (Git Bash, WSL)
#
# Usage:
#   ./upgrade.sh                                    # profile=developer
#   ./upgrade.sh --profile full                     # explicit profile
#   ./upgrade.sh --component agent:openplanner      # single component (+deps)
#   ./upgrade.sh --refresh --component agent:openplanner  # re-fetch even if present
#   ./upgrade.sh --install-dir PATH --dry-run       # preview only
#
# Environment variables:
#   OPENCODE_INSTALL_DIR   Override the installation directory
#   OPENCODE_BRANCH        Branch to pull from (default: main)
#   REGISTRY_URL           Registry location (supports file:// for testing)
#   OAC_SOURCE_DIR         Local repo root to copy files from instead of
#                          downloading (dev/test/air-gapped use)
#############################################################################

set -e

# Detect platform (only needed for the global install path)
PLATFORM="$(uname -s)"
case "$PLATFORM" in
    Linux*)     PLATFORM="Linux";;
    Darwin*)    PLATFORM="macOS";;
    CYGWIN*|MINGW*|MSYS*) PLATFORM="Windows";;
    *)          PLATFORM="Unknown";;
esac

if [ "$PLATFORM" = "Windows" ] && [ -z "$WT_SESSION" ] && [ -z "$ConEmuPID" ]; then
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; NC=''
else
    RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
    BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
fi

BRANCH="${OPENCODE_BRANCH:-main}"
RAW_URL="https://raw.githubusercontent.com/niksmac/OpenAgentsControl/${BRANCH}"

if [ -n "$REGISTRY_URL" ]; then
    :
elif [ -f "./registry.json" ]; then
    REGISTRY_URL="file://$(pwd)/registry.json"
else
    REGISTRY_URL="${RAW_URL}/registry.json"
fi

PROFILE="developer"
PROFILE_EXPLICIT=false
CUSTOM_INSTALL_DIR=""
DRY_RUN=false
REFRESH=false
EXTRA_COMPONENTS=""

TEMP_DIR="/tmp/opencode-upgrade-$$"
trap 'rm -rf "$TEMP_DIR" 2>/dev/null || true' EXIT INT TERM

ADDED=0
PRESENT=0
REFRESHED=0
FAILED=0
FAILED_FILES=""

#############################################################################
# Helpers
#############################################################################

print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_info()    { echo -e "${BLUE}ℹ${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
print_error()   { echo -e "${RED}✗${NC} $1" >&2; }
print_step()    { echo -e "\n${CYAN}${BOLD}▶${NC} $1\n"; }

print_header() {
    echo -e "${CYAN}${BOLD}"
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo "║                                                                ║"
    echo "║           OpenAgents Control Upgrade v1.0.0                    ║"
    echo "║           (adds missing components, changes nothing)           ║"
    echo "║                                                                ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_usage() {
    echo "Usage: $0 [--profile NAME] [--component type:id] [--refresh] [--install-dir PATH] [--dry-run]"
    echo ""
    echo "Options:"
    echo "  --profile NAME       Registry profile to sync (default: developer)"
    echo "  --component type:id  Add one component plus its dependencies"
    echo "                       (repeatable, e.g. --component agent:openplanner;"
    echo "                       without --profile, syncs only these)"
    echo "  --refresh            Re-fetch files even when already present."
    echo "                       Without it, existing files are never touched,"
    echo "                       so modifications to components you already have"
    echo "                       (e.g. openplanner.md permission fix) report as"
    echo "                       'already present'. Use --refresh (optionally with"
    echo "                       --component) to pull the latest version."
    echo "  --install-dir PATH   Target installation directory"
    echo "  --dry-run            List what would be added, change nothing"
    echo "  --help               Show this help message"
    echo ""
    echo "Environment variables:"
    echo "  OPENCODE_INSTALL_DIR   Override the installation directory"
    echo "  OPENCODE_BRANCH        Branch to pull from (default: main)"
    echo "  REGISTRY_URL           Registry location (file:// supported)"
    echo "  OAC_SOURCE_DIR         Local repo root to copy from (no download)"
}

jq_exec() {
    local output
    output=$(jq -r "$@" 2>/dev/null)
    local ret=$?
    printf "%s\n" "$output" | tr -d '\r'
    return $ret
}

get_global_install_path() {
    echo "${HOME}/.config/opencode"
}

normalize_path() {
    local input_path="$1"
    [ -z "$input_path" ] && echo "" && return 1
    local normalized_path
    if [[ $input_path == ~* ]]; then
        normalized_path="${HOME}${input_path:1}"
    else
        normalized_path="$input_path"
    fi
    normalized_path="${normalized_path//\\\\//}"
    normalized_path="${normalized_path%/}"
    if [[ ! "$normalized_path" = /* ]] && [[ ! "$normalized_path" =~ ^[A-Za-z]: ]]; then
        normalized_path="$(pwd)/${normalized_path}"
    fi
    echo "$normalized_path"
    return 0
}

resolve_install_dir() {
    local custom_dir="$1"
    if [ -n "$custom_dir" ]; then
        normalize_path "$custom_dir"
        return
    fi
    if [ -n "$OPENCODE_INSTALL_DIR" ]; then
        normalize_path "$OPENCODE_INSTALL_DIR"
        return
    fi
    local local_path="$(pwd)/.opencode"
    local global_path
    global_path=$(get_global_install_path)
    if [ -d "$local_path" ]; then
        echo "$local_path"
    elif [ -d "$global_path" ]; then
        echo "$global_path"
    else
        echo "$local_path"
    fi
}

# Map "agent:foo" -> registry key "agents" (plural), like install.sh
get_registry_key() {
    local type="$1"
    case "$type" in
        agents|subagents|commands|tools|plugins|skills|contexts|config) echo "$type" ;;
        agent) echo "agents" ;;
        subagent) echo "subagents" ;;
        command) echo "commands" ;;
        tool) echo "tools" ;;
        plugin) echo "plugins" ;;
        skill) echo "skills" ;;
        context) echo "contexts" ;;
        *) echo "${type}s" ;;
    esac
}

fetch_registry() {
    print_step "Fetching component registry..."
    mkdir -p "$TEMP_DIR"
    case "$REGISTRY_URL" in
        file://*)
            local local_path="${REGISTRY_URL#file://}"
            if [ -f "$local_path" ]; then
                cp "$local_path" "$TEMP_DIR/registry.json"
                print_success "Using local registry: $local_path"
            else
                print_error "Local registry not found: $local_path"
                exit 1
            fi
            ;;
        *)
            if ! curl -fsSL "$REGISTRY_URL" -o "$TEMP_DIR/registry.json"; then
                print_error "Failed to fetch registry from $REGISTRY_URL"
                exit 1
            fi
            print_success "Registry fetched"
            ;;
    esac
}

# Resolve one component ID to registry file path(s), one per line.
# Handles exact components and context:prefix/* wildcards.
resolve_component_paths() {
    local comp="$1"
    local type="${comp%%:*}"
    local id="${comp##*:}"
    local registry_key
    registry_key=$(get_registry_key "$type")

    case "$type" in
        context)
            case "$id" in
                */\*)
                    local prefix="${id%\*}"
                    jq_exec ".components.contexts[]? | select(.path | startswith(\".opencode/context/${prefix}\")) | .path" "$TEMP_DIR/registry.json"
                    ;;
                *)
                    jq_exec ".components.contexts[]? | select(.id == \"${id}\" or (.path | endswith(\"/${id}.md\")) or .path == \".opencode/context/${id}.md\") | .path" "$TEMP_DIR/registry.json"
                    ;;
            esac
            ;;
        *)
            jq_exec ".components.${registry_key}[]? | select(.id == \"${id}\") | .path" "$TEMP_DIR/registry.json"
            ;;
    esac
}

# Print direct registry dependencies of one component ID, one per line.
component_dependencies() {
    local comp="$1"
    local type="${comp%%:*}"
    local id="${comp##*:}"
    local registry_key
    registry_key=$(get_registry_key "$type")
    jq_exec ".components.${registry_key}[]? | select(.id == \"${id}\") | .dependencies[]?" "$TEMP_DIR/registry.json"
}

# already_seen tracks processed component IDs (newline-separated, bash 3.2 safe)
already_seen() {
    case "$1" in
        *"$2"*) return 0 ;;
        *) return 1 ;;
    esac
}

# Expand profile + explicit components + transitive deps into $TEMP_DIR/wanted.txt
collect_wanted() {
    : > "$TEMP_DIR/wanted.txt"
    : > "$TEMP_DIR/queue.txt"

    local profile_comps=""
    # --component without an explicit --profile syncs just those components
    # (plus their dependencies), not the whole default profile.
    if [ "$PROFILE_EXPLICIT" = true ] || [ -z "$EXTRA_COMPONENTS" ]; then
        profile_comps=$(jq_exec ".profiles.${PROFILE}.components[]?" "$TEMP_DIR/registry.json")
        if [ -z "$profile_comps" ] || [ "$profile_comps" = "null" ]; then
            print_error "Unknown profile: ${PROFILE}"
            print_info "Available profiles: $(jq_exec '.profiles | keys | join(", ")' "$TEMP_DIR/registry.json")"
            exit 1
        fi
    fi
    printf "%s\n" "$profile_comps" >> "$TEMP_DIR/queue.txt"
    for comp in $EXTRA_COMPONENTS; do
        printf "%s\n" "$comp" >> "$TEMP_DIR/queue.txt"
    done

    local seen=""
    while IFS= read -r comp; do
        [ -z "$comp" ] && continue
        if already_seen "$seen" "|${comp}|"; then
            continue
        fi
        seen="${seen}|${comp}|"
        printf "%s\n" "$comp" >> "$TEMP_DIR/wanted.txt"
        local deps
        deps=$(component_dependencies "$comp")
        for dep in $deps; do
            [ -z "$dep" ] && continue
            printf "%s\n" "$dep" >> "$TEMP_DIR/queue.txt"
        done
    done < "$TEMP_DIR/queue.txt"
}

fetch_file() {
    local registry_path="$1"   # e.g. .opencode/agent/core/openplanner.md
    local dest="$2"
    if [ -n "$OAC_SOURCE_DIR" ] && [ -f "${OAC_SOURCE_DIR}/${registry_path}" ]; then
        cp "${OAC_SOURCE_DIR}/${registry_path}" "$dest"
        return $?
    fi
    curl -fsSL "${RAW_URL}/${registry_path}" -o "$dest" 2>/dev/null
    return $?
}

sync_missing() {
    local install_dir="$1"
    while IFS= read -r comp; do
        [ -z "$comp" ] && continue
        local paths
        paths=$(resolve_component_paths "$comp")
        if [ -z "$paths" ] || [ "$paths" = "null" ]; then
            print_warning "Not in registry, skipping: $comp"
            continue
        fi
        while IFS= read -r registry_path; do
            [ -z "$registry_path" ] || [ "$registry_path" = "null" ] && continue
            # Registry paths are rooted at .opencode/... — map onto install dir
            local relative_path="${registry_path#.opencode/}"
            if [ "$relative_path" = "$registry_path" ]; then
                relative_path="$registry_path"
            fi
            local dest="${install_dir}/${relative_path}"
            if [ -f "$dest" ] && [ "$REFRESH" != true ]; then
                PRESENT=$((PRESENT + 1))
                continue
            fi
            local exists_before=false
            [ -f "$dest" ] && exists_before=true
            if [ "$DRY_RUN" = true ]; then
                if [ "$exists_before" = true ]; then
                    echo "  would refresh: $relative_path  ($comp)"
                else
                    echo "  would add: $relative_path  ($comp)"
                fi
                ADDED=$((ADDED + 1))
                continue
            fi
            mkdir -p "$(dirname "$dest")"
            local backup=""
            if [ "$exists_before" = true ]; then
                backup="${dest}.upgrade-backup"
                cp "$dest" "$backup" 2>/dev/null || true
            fi
            if fetch_file "$registry_path" "$dest"; then
                [ -n "$backup" ] && rm -f "$backup"
                if [ "$exists_before" = true ]; then
                    print_success "Refreshed $relative_path"
                    REFRESHED=$((REFRESHED + 1))
                else
                    print_success "Added $relative_path"
                    ADDED=$((ADDED + 1))
                fi
            else
                if [ "$exists_before" = true ] && [ -f "$backup" ]; then
                    mv "$backup" "$dest"
                else
                    rm -f "$dest"
                fi
                print_warning "Failed to fetch $relative_path"
                FAILED=$((FAILED + 1))
                FAILED_FILES="${FAILED_FILES} $relative_path"
            fi
        done <<EOF
$paths
EOF
    done < "$TEMP_DIR/wanted.txt"
}

#############################################################################
# Argument parsing
#############################################################################

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile)
                PROFILE="$2"; PROFILE_EXPLICIT=true; shift 2 ;;
            --profile=*)
                PROFILE="${1#*=}"; PROFILE_EXPLICIT=true; shift ;;
            --component)
                EXTRA_COMPONENTS="${EXTRA_COMPONENTS} $2"; shift 2 ;;
            --component=*)
                EXTRA_COMPONENTS="${EXTRA_COMPONENTS} ${1#*=}"; shift ;;
            --install-dir)
                CUSTOM_INSTALL_DIR="$2"; shift 2 ;;
            --install-dir=*)
                CUSTOM_INSTALL_DIR="${1#*=}"; shift ;;
            --refresh|--force)
                REFRESH=true; shift ;;
            --dry-run)
                DRY_RUN=true; shift ;;
            --help|-h)
                print_usage; exit 0 ;;
            *)
                print_error "Unknown option: $1"
                print_usage
                exit 1 ;;
        esac
    done
}

#############################################################################
# Main
#############################################################################

main() {
    parse_args "$@"

    if ! command -v jq >/dev/null 2>&1; then
        print_error "jq is required but not installed"
        exit 1
    fi

    print_header

    local install_dir
    install_dir=$(resolve_install_dir "$CUSTOM_INSTALL_DIR")

    if [ ! -d "$install_dir" ]; then
        print_error "Installation directory not found: $install_dir"
        echo ""
        echo "Run install.sh first, or point at an existing install with:"
        echo "  $0 --install-dir PATH"
        exit 1
    fi

    if [ ! -w "$install_dir" ]; then
        print_error "No write permission for: $install_dir"
        exit 1
    fi

    fetch_registry

    print_info "Install dir: ${CYAN}${install_dir}${NC}"
    print_info "Profile: ${CYAN}${PROFILE}${NC}"
    if [ -n "$OAC_SOURCE_DIR" ]; then
        print_info "Source: local ${OAC_SOURCE_DIR}"
    else
        print_info "Source: ${BRANCH} branch"
    fi
    if [ "$DRY_RUN" = true ]; then
        print_info "Mode: dry-run (nothing will change)"
    fi

    print_step "Resolving components..."
    collect_wanted
    local wanted_count
    wanted_count=$(grep -c . "$TEMP_DIR/wanted.txt" 2>/dev/null || echo 0)
    print_info "Tracking $wanted_count component(s) incl. dependencies"

    print_step "Syncing missing files (existing files are never touched)..."
    if [ "$REFRESH" = true ]; then
        print_info "Refresh mode: existing files will be re-fetched"
    fi
    sync_missing "$install_dir"

    echo ""
    if [ "$DRY_RUN" = true ]; then
        print_info "Dry-run result: $ADDED file(s) would be added/refreshed, $PRESENT already present"
    else
        print_success "Upgrade complete: $ADDED added, $REFRESHED refreshed, $PRESENT already present, $FAILED failed"
    fi
    if [ "$PRESENT" -gt 0 ] && [ "$ADDED" -eq 0 ] && [ "$REFRESHED" -eq 0 ] && [ "$REFRESH" != true ]; then
        print_info "Nothing new to add. If you expected updates to files you already"
        print_info "have (e.g. a fix to agent:openplanner), re-run with --refresh:"
        print_info "  $0 --refresh --component agent:openplanner"
        print_info "Or refresh everything you already have with update.sh."
    fi
    if [ -n "$FAILED_FILES" ]; then
        print_warning "Failed files:$FAILED_FILES"
        exit 1
    fi
}

main "$@"

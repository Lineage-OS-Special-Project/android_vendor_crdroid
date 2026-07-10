#!/bin/bash

# ================================================================
# LOSP Device Setup Script
# ================================================================

# NINJA
export NINJA_STATUS=$'[\033[1;32m%f\033[0m/\033[1;36m%t\033[0m (\033[1;34m%p\033[0m) Elapsed: \033[1;33m%es\033[0m]                                          '

# Default DEBUG if unset
DEBUG="${DEBUG:-0}"

# Clear screen at start
[[ "$DEBUG" -eq 0 ]] && clear

# Define color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
RESET='\033[0m'

ROM_NAME="LOSP"
ROM_PRODUCT_PREFIX="lineage"
ROM_FLAVOR="cp2a"
ROM_BUILD_TARGET="losp"
ROM_VENDOR_CONFIG_PATH="vendor/lineage"
STASH_DIRS=()

DEVICE_CODENAME=""
LUNCH_COMBO=""
BUILD_VARIANT=""

DEVICE_MAPPINGS_FILE="${ROM_VENDOR_CONFIG_PATH}/build/device_mappings.conf"
LOCAL_MANIFEST=".repo/local_manifests/roomservice.xml"
LOSP_BUILD_CONFIG_FILE=".losp_build_config.mk"
LOSP_GMS_TYPE="${LOSP_GMS_TYPE:-gms}"

# ================================================================
# Helper functions
# ================================================================

is_sourced() {
    if [[ -n "${ZSH_EVAL_CONTEXT:-}" ]]; then
        [[ "$ZSH_EVAL_CONTEXT" == *:file:* ]]
    else
        [[ "${BASH_SOURCE[0]}" != "$0" ]]
    fi
}

die() {
    echo -e "${RED}✗ $1${RESET}" >&2
    if is_sourced; then
        return 1
    else
        exit 1
    fi
}

require_repo_root() {
    if [[ ! -d ".repo" ]]; then
        die "This script must be run from the Android repo root."
        return 1
    fi

    if [[ ! -f "build/envsetup.sh" ]]; then
        die "build/envsetup.sh not found. Are you in the Android source root?"
        return 1
    fi

    return 0
}

dir_has_contents() {
    local dir="$1"
    [[ -d "$dir" ]] && find "$dir" -mindepth 1 -maxdepth 1 | grep -q .
}

section_header() {
    echo -e "${CYAN}=== $1 ===${RESET}"
}

prompt_user() {
    echo -e "${BLUE}»${RESET} ${CYAN}$1${RESET}"
    echo -en "${GREEN}➤ ${RESET}"
}

show_warning() {
    echo -e "${YELLOW}⚠ $1${RESET}"
}

show_success() {
    echo -e "${GREEN}✓ $1${RESET}"
}

show_error() {
    echo -e "${RED}✗ $1${RESET}"
}

validate_yn() {
    local input="$1"
    [[ "$input" =~ ^[YyNn]$ ]]
}

add_separator() {
    echo -e "\n${BLUE}------------------------------------------------${RESET}\n"
}

show_progress() {
    local current="$1"
    local total="$2"
    local task="$3"
    local width=50 percentage completed remaining

    [[ "$total" -eq 0 ]] && total=1
    [[ "$current" -gt "$total" ]] && current="$total"

    percentage=$((current * 100 / total))
    completed=$((current * width / total))
    remaining=$((width - completed))

    printf "\r${BLUE}[${RESET}"
    printf "%*s" "$completed" | tr ' ' '='
    printf "%*s" "$remaining" | tr ' ' '.'
    printf "${BLUE}]${RESET} ${CYAN}%3d%%${RESET} ${YELLOW}%s${RESET}" "$percentage" "$task"

    if [[ "$current" -eq "$total" ]]; then
        printf " ${GREEN}✓${RESET}\n"
    fi
}

repo_target_exists() {
    local path="$1"

    [[ -e "$path/.git" ]] || return 1
    git -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
    git -C "$path" rev-parse HEAD >/dev/null 2>&1 || return 1

    return 0
}

repo_project_known() {
    local path="$1"
    repo list "$path" >/dev/null 2>&1
}

refresh_repo_manifest_view() {
    local manifest_file="$1"

    show_warning "Refreshing repo manifest view..."
    return 0
}

reset_repo_project() {
    local project_path="$1"
    local attempt

    echo
    show_warning "Resetting repo project: ${project_path}"

    if ! repo_project_known "$project_path"; then
        show_error "${project_path} is not present in the current manifest"
        return 1
    fi

    for attempt in 1 2 3; do
        show_warning "Sync attempt ${attempt}/3 for ${project_path}"

        rm -rf "$project_path"
        rm -rf ".repo/projects/${project_path}.git"

        find .repo -name "*.lock" -type f -delete 2>/dev/null || true

        if repo sync \
            --force-sync \
            --force-remove-dirty \
            --detach \
            --current-branch \
            --no-tags \
            --no-clone-bundle \
            --fail-fast \
            -j4 \
            "$project_path"; then

            if repo_target_exists "$project_path"; then
                git -C "$project_path" fsck --connectivity-only >/dev/null 2>&1 || {
                    show_error "${project_path} failed git connectivity check"
                    continue
                }

                show_success "Restored ${project_path}"
                return 0
            fi
        fi

        show_warning "Retrying ${project_path} after failed or incomplete sync..."
        sleep 2
    done

    show_error "Failed to restore ${project_path} after 3 attempts"
    return 1
}

write_losp_build_config() {
    local provider="$1"
    local pixel_launcher="$2"

    case "$provider" in
        gms|microg|vanilla)
            ;;
        *)
            show_error "Invalid mobile services provider: $provider"
            return 1
            ;;
    esac

    case "$pixel_launcher" in
        true|false)
            ;;
        *)
            show_error "Invalid Pixel Launcher value: $pixel_launcher"
            return 1
            ;;
    esac

    cat > "$LOSP_BUILD_CONFIG_FILE" <<EOF
# Automatically generated by the LOSP device setup wizard.
# Valid LOSP_GMS_TYPE values: gms, microg, vanilla

LOSP_GMS_TYPE := ${provider}
TARGET_INCLUDE_PIXEL_LAUNCHER := ${pixel_launcher}
EOF

    export LOSP_GMS_TYPE="$provider"
    export TARGET_INCLUDE_PIXEL_LAUNCHER="$pixel_launcher"

    if [[ "$provider" == "gms" ]]; then
        export WITH_GMS=true
    else
        export WITH_GMS=false
    fi

    show_success "Saved LOSP build configuration to ${LOSP_BUILD_CONFIG_FILE}"
}

# ================================================================
# Device mapping / detection
# ================================================================

load_device_mappings() {
    local manufacturer="$1"
    local device_codename="$2"

    [[ -f "$DEVICE_MAPPINGS_FILE" ]] || return 1

    local mapping
    mapping=$(grep -E "^${manufacturer}:${device_codename}:" "$DEVICE_MAPPINGS_FILE" | head -1)

    if [[ -n "$mapping" ]]; then
        echo "$mapping" | cut -d: -f3
        return 0
    fi

    return 1
}

get_google_family() {
    local device="$1"

    case "$device" in
        coral|flame)
            echo "coral"
            ;;
        bonito|sargo)
            echo "bonito"
            ;;
        blueline|crosshatch)
            echo "crosshatch"
            ;;
        caiman|tokay|komodo)
            echo "caimito"
            ;;
        husky|shiba)
            echo "shusky"
            ;;
        cheetah|panther|bluejay)
            echo "pantah"
            ;;
        marlin|sailfish)
            echo "marlin"
            ;;
        blazer)
            echo "muzel"
            ;;
        mu64x|sdk_phone_x86_64)
            echo ""
            ;;
        *)
            load_device_mappings google "$device" 2>/dev/null || true
            ;;
    esac
}

find_device_tree() {
    local device_codename="$1"
    local google_family="$2"

    if [[ -n "$google_family" && -d "device/google/${google_family}/${device_codename}" ]]; then
        echo "device/google/${google_family}/${device_codename}"
        return 0
    fi

    if [[ -n "$google_family" && -d "device/google/${google_family}" ]]; then
        echo "device/google/${google_family}"
        return 0
    fi

    local found_path
    found_path=$(find device -maxdepth 4 -type d -name "$device_codename" 2>/dev/null | head -n 1)
    if [[ -n "$found_path" ]]; then
        echo "$found_path"
        return 0
    fi

    return 1
}

detect_common_tree() {
    local manufacturer="$1"
    local device_codename="$2"
    local device_tree_path="$3"
    local silent="${4:-false}"

    local common_tree=""

    common_tree=$(load_device_mappings "$manufacturer" "$device_codename")
    if [[ -n "$common_tree" ]]; then
        if [[ -d "device/${manufacturer}/${common_tree}" || -d "vendor/${manufacturer}/${common_tree}" ]]; then
            [[ "$silent" != "true" ]] && {
                echo
                show_success "Found common tree in mappings: $common_tree"
            }
            echo "$common_tree"
            return 0
        fi
    fi

    if [[ -f "$device_tree_path/device.mk" || -f "$device_tree_path/${device_codename}.mk" ]]; then
        local device_mk common_ref
        for device_mk in "$device_tree_path/device.mk" "$device_tree_path/${device_codename}.mk"; do
            [[ -f "$device_mk" ]] || continue
            common_ref=$(grep -E 'inherit-product.*common.*\.mk|common.*inherit-product' "$device_mk" | head -1)
            if [[ -n "$common_ref" && "$common_ref" =~ device/${manufacturer}/([^/]+)/ ]]; then
                common_tree="${BASH_REMATCH[1]}"
                [[ "$silent" != "true" ]] && {
                    echo
                    show_success "Found common tree in makefile: $common_tree"
                }
                echo "$common_tree"
                return 0
            fi
        done
    fi

    if [[ "$device_tree_path" == *"$manufacturer"* ]]; then
        local parent_dir possible_common
        parent_dir=$(dirname "$device_tree_path")
        possible_common=$(basename "$parent_dir")
        if [[ "$possible_common" == *"common"* ]]; then
            [[ "$silent" != "true" ]] && {
                echo
                show_success "Found common tree in parent directory: $possible_common"
            }
            echo "$possible_common"
            return 0
        fi
    fi

    [[ "$silent" != "true" ]] && {
        echo
        show_warning "No common tree detected for $manufacturer $device_codename"
    }
    echo ""
    return 1
}

find_primary_boardconfig() {
    local device_codename="$1"
    local google_family="$2"
    local device_tree_path="$3"

    local candidates=()

    if [[ -n "$google_family" ]]; then
        candidates+=(
            "device/google/${google_family}/${device_codename}/BoardConfigLineage.mk"
            "device/google/${google_family}/${device_codename}/BoardConfig.mk"
            "device/google/${google_family}/${device_codename}/BoardConfigCommon.mk"
            "device/google/${google_family}/${device_codename}/BoardConfigKernel.mk"
            "device/google/${google_family}/${device_codename}/board/BoardConfigCommon.mk"
        )
    fi

    candidates+=(
        "${device_tree_path}/BoardConfigLineage.mk"
        "${device_tree_path}/BoardConfig.mk"
        "${device_tree_path}/BoardConfigCommon.mk"
        "${device_tree_path}/BoardConfigKernel.mk"
        "${device_tree_path}/BoardConfigGsi.mk"
        "${device_tree_path}/board/BoardConfigCommon.mk"
    )

    if [[ -n "$google_family" ]]; then
        candidates+=(
            "device/google/${google_family}/BoardConfigLineage.mk"
            "device/google/${google_family}/BoardConfig.mk"
            "device/google/${google_family}/BoardConfigCommon.mk"
            "device/google/${google_family}/BoardConfigKernel.mk"
        )
    fi

    local config_file
    for config_file in "${candidates[@]}"; do
        if [[ -s "$config_file" ]]; then
            echo "$config_file"
            return 0
        fi
    done

    return 1
}

resolve_manufacturer() {
    local primary_device_path="$1"

    if [[ "$primary_device_path" =~ ^device/google/ ]]; then
        echo "google"
    else
        basename "$(dirname "$primary_device_path")"
    fi
}

# ================================================================
# Manifest / repo helpers
# ================================================================

rewrite_roomservice_clean() {
    local manifest_file="$1"
    local manufacturer="$2"
    local device_codename="$3"
    local common_tree="$4"
    local tmp_file="${manifest_file}.tmp"

    mkdir -p "$(dirname "$manifest_file")"

    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<manifest>'

        if [[ -f "$manifest_file" ]]; then
            awk -v m="$manufacturer" -v d="$device_codename" -v c="$common_tree" '
                BEGIN {
                    dev_name = "TheMuppets/proprietary_vendor_" m "_" d
                    dev_path = "vendor/" m "/" d
                    common_name = "TheMuppets/proprietary_vendor_" m "_" c
                    common_path = "vendor/" m "/" c
                }
                /^<\?xml/ { next }
                /^<manifest>$/ { next }
                /^<\/manifest>$/ { next }
                index($0, dev_name) { next }
                index($0, dev_path) { next }
                (c != "" && index($0, common_name)) { next }
                (c != "" && index($0, common_path)) { next }
                { print }
            ' "$manifest_file"
        fi

        echo "  <!-- Device: ${device_codename} -->"
        echo "  <!-- Added on $(date) -->"
        echo "  <project name=\"TheMuppets/proprietary_vendor_${manufacturer}_${device_codename}\" path=\"vendor/${manufacturer}/${device_codename}\" remote=\"github\" />"

        if [[ -n "$common_tree" && "$manufacturer" != "google" ]]; then
            echo "  <project name=\"TheMuppets/proprietary_vendor_${manufacturer}_${common_tree}\" path=\"vendor/${manufacturer}/${common_tree}\" remote=\"github\" />"
        fi

        echo '</manifest>'
    } > "$tmp_file"

    mv "$tmp_file" "$manifest_file"
}

sync_vendor_repo() {
    local repo_path="$1"

    # Make repo aware of newly-added local manifest projects.
    repo sync -n --no-tags --no-clone-bundle -j1 "$repo_path" >/dev/null 2>&1 || true

    show_warning "Syncing ${repo_path}"

    if ! repo_project_known "$repo_path"; then
        show_error "${repo_path} is not present in the current manifest"
        return 1
    fi

    if repo_target_exists "$repo_path" && dir_has_contents "$repo_path"; then
    show_success "${repo_path} already present and valid"
    return 0
fi

if [[ -d "$repo_path" ]]; then
    show_warning "${repo_path} exists but appears incomplete; removing before re-sync"
    rm -rf "$repo_path"
    rm -rf ".repo/projects/${repo_path}.git"
fi

    find .repo -name "*.lock" -type f -delete 2>/dev/null || true

    if repo sync \
        --force-sync \
        --force-remove-dirty \
        --current-branch \
        --no-tags \
        --no-clone-bundle \
        --fail-fast \
        -j4 \
        "$repo_path"; then

        if repo_target_exists "$repo_path"; then
            show_success "Synced ${repo_path}"
            return 0
        fi
    fi

    show_error "Failed to sync ${repo_path}"
    return 1
}

verify_vendor_repo() {
    local repo_path="$1"
    local label="$2"

    if ! dir_has_contents "$repo_path"; then
        show_error "${label} missing or empty: ${repo_path}"
        return 1
    fi

    if ! repo_target_exists "$repo_path"; then
        show_error "${label} is not a valid git checkout: ${repo_path}"
        return 1
    fi

    local mk_found=0
    local base_name
    base_name=$(basename "$repo_path")

    local candidates=(
        "${repo_path}/${base_name}-vendor.mk"
        "${repo_path}/device-vendor.mk"
        "${repo_path}/vendor.mk"
        "${repo_path}/BoardConfigVendor.mk"
    )

    local vendor_mk
    for vendor_mk in "${candidates[@]}"; do
        if [[ -f "$vendor_mk" ]]; then
            show_success "${label} makefile found: $(basename "$vendor_mk")"
            mk_found=1
            break
        fi
    done

    if [[ "$mk_found" -eq 0 ]]; then
        show_error "${label} makefile missing under ${repo_path}"
        return 1
    fi

    return 0
}

repair_external_iptables() {
    local project_path="external/iptables"

    echo
    show_warning "Checking ${project_path}"

    if ! repo list | awk '{print $1}' | grep -qx "$project_path"; then
        show_warning "${project_path} is not in the manifest; skipping"
        return 0
    fi

    if [[ -f "${project_path}/iptables/xtables.lock" ]] && repo_target_exists "$project_path"; then
        show_success "${project_path} already present and valid"
        return 0
    fi

    show_warning "Force-repairing ${project_path}"

    rm -rf "$project_path"
    rm -rf ".repo/projects/${project_path}.git"

    find .repo -name "*.lock" -type f -delete 2>/dev/null || true

    if repo sync \
        --force-sync \
        --force-remove-dirty \
        --no-tags \
        --no-clone-bundle \
        --fail-fast \
        -j4 \
        "$project_path"; then

        if [[ -f "${project_path}/iptables/xtables.lock" ]]; then
            show_success "${project_path} repaired successfully"
            return 0
        fi

        show_error "${project_path} synced but xtables.lock is still missing"
        return 1
    fi

    show_error "Failed to repair ${project_path}"
    return 1
}

remove_duplicate_moseyapp_for_blazer() {
    local device_codename="$1"
    local device_bp="vendor/google/${device_codename}/Android.bp"

    [[ "$device_codename" == "blazer" ]] || return 0
    [[ -f "$device_bp" ]] || return 0

    if ! grep -RqE 'LOCAL_MODULE[[:space:]]*:=[[:space:]]*MoseyApp|name:[[:space:]]*"MoseyApp"' vendor/gms 2>/dev/null; then
        show_success "MoseyApp not found in vendor/gms; keeping device vendor copy"
        return 0
    fi

    if ! grep -q 'name:[[:space:]]*"MoseyApp"' "$device_bp"; then
        show_success "No MoseyApp module found in ${device_bp}"
        return 0
    fi

    show_warning "Removing duplicate MoseyApp module from ${device_bp}"

    python3 - "$device_bp" <<'PY'
import sys
from pathlib import Path

bp = Path(sys.argv[1])
text = bp.read_text()

needle = 'name: "MoseyApp"'
idx = text.find(needle)

if idx == -1:
    sys.exit(2)

# Find start of containing Soong module: nearest "<module_type> {" before the name.
brace_start = text.rfind("{", 0, idx)
if brace_start == -1:
    sys.exit(2)

line_start = text.rfind("\n", 0, brace_start)
if line_start == -1:
    line_start = 0
else:
    line_start += 1

# Include any directly attached comment lines immediately above the module.
comment_start = line_start
while comment_start > 0:
    prev_end = comment_start - 1
    prev_start = text.rfind("\n", 0, prev_end)
    if prev_start == -1:
        prev_start = 0
    else:
        prev_start += 1

    prev_line = text[prev_start:prev_end].strip()
    if prev_line.startswith("//") or prev_line == "":
        comment_start = prev_start
    else:
        break

# Walk forward from the opening brace to matching closing brace.
depth = 0
end = None
for pos in range(brace_start, len(text)):
    ch = text[pos]
    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0:
            end = pos + 1
            break

if end is None:
    sys.exit(2)

# Include following whitespace/newline.
while end < len(text) and text[end] in " \t\r\n":
    end += 1

new_text = text[:comment_start] + text[end:]

if new_text == text:
    sys.exit(2)

bp.write_text(new_text)
PY

    case "$?" in
        0)
            show_success "Removed duplicate MoseyApp module from ${device_bp}"
            ;;
        2)
            show_error "MoseyApp was found, but the containing module block could not be removed"
            return 1
            ;;
        *)
            show_error "Failed while editing ${device_bp}"
            return 1
            ;;
    esac

    if grep -q 'name:[[:space:]]*"MoseyApp"' "$device_bp"; then
        show_error "MoseyApp still exists in ${device_bp}"
        return 1
    fi

    return 0
}

ensure_vendor_blobs() {
    local device_codename="$1"
    local primary_device_path="$2"
    local google_family="$3"

    local manufacturer common_tree primary_vendor common_vendor

    manufacturer=$(resolve_manufacturer "$primary_device_path")
    common_tree=""

    if [[ "$manufacturer" != "google" ]]; then
        common_tree=$(detect_common_tree "$manufacturer" "$device_codename" "$primary_device_path" "true")
    fi

    primary_vendor="vendor/${manufacturer}/${device_codename}"
    common_vendor=""
    [[ -n "$common_tree" && "$manufacturer" != "google" ]] && common_vendor="vendor/${manufacturer}/${common_tree}"

    rewrite_roomservice_clean "$LOCAL_MANIFEST" "$manufacturer" "$device_codename" "$common_tree" || {
        show_error "Failed to rewrite ${LOCAL_MANIFEST}"
        return 1
    }

    show_success "Local manifest updated at ${LOCAL_MANIFEST}"
    grep -E "project name=|path=" "$LOCAL_MANIFEST" | tail -n 10

    sync_vendor_repo "$primary_vendor" || return 1
    verify_vendor_repo "$primary_vendor" "Primary vendor" || return 1

    if [[ -n "$common_vendor" ]]; then
        sync_vendor_repo "$common_vendor" || return 1
        verify_vendor_repo "$common_vendor" "Common vendor" || return 1
    else
        show_success "No common vendor verification needed"
    fi

    remove_duplicate_moseyapp_for_blazer "$device_codename" || return 1

    return 0
}

stash_device_changes() {
    local primary_device_path="$1"
    local google_family="$2"

    STASH_DIRS=()
    STASH_DIRS+=("$primary_device_path")

    if [[ -n "$google_family" && -d "device/google/$google_family" && "$primary_device_path" != "device/google/$google_family" ]]; then
        STASH_DIRS+=("device/google/$google_family")
    fi

    echo
    show_warning "Stashing local changes to protect device tree edits..."

    local stashed_changes=0
    local sdir

    for sdir in "${STASH_DIRS[@]}"; do
        if [[ -d "$sdir/.git" ]]; then
            if git -C "$sdir" status --porcelain | grep -q .; then
                echo "Stashing changes in $sdir"
                git -C "$sdir" stash push -m "Auto-stashed by device setup script"
                stashed_changes=1
            fi
        fi
    done

    if [[ "$stashed_changes" -eq 0 ]]; then
        show_success "No local changes to stash"
    else
        show_success "Local changes stashed successfully"
    fi

    return 0
}

restore_device_changes() {
    local restored_changes=0
    local sdir

    echo
    show_warning "Restoring stashed changes..."

    for sdir in "${STASH_DIRS[@]}"; do
        if [[ -d "$sdir/.git" ]]; then
            if git -C "$sdir" stash list | grep -q "Auto-stashed by device setup script"; then
                echo "Restoring changes in $sdir"
                git -C "$sdir" stash pop
                restored_changes=1
            fi
        fi
    done

    if [[ "$restored_changes" -eq 0 ]]; then
        show_success "No stashed changes to restore"
    else
        show_success "Stashed changes restored successfully"
    fi

    return 0
}

# ================================================================
# Setup logic
# ================================================================

setup_device_tree() {
    local device_codename="$1"
    local lunch_combo="$2"
    local build_variant="$3"
    local total_steps=7
    local current_step=0
    local lunch_result=0
    local google_family primary_device_path manufacturer

    require_repo_root || return 1

    ((current_step++))
    [[ "$DEBUG" -eq 0 ]] && clear
    show_progress "$current_step" "$total_steps" "Checking device configuration..."

    show_warning "Testing device configuration for: $device_codename"
    echo -e "${BLUE}Command:${RESET} lunch $lunch_combo"

    if lunch "$lunch_combo"; then
        lunch_result=0
    else
        lunch_result=$?
    fi

    if [[ "$lunch_result" -eq 0 ]]; then
        show_success "Device '$device_codename' is already configured."
    else
        show_warning "Device '$device_codename' needs initial setup..."

        ((current_step++))
        [[ "$DEBUG" -eq 0 ]] && clear
        show_progress "$current_step" "$total_steps" "Running initial device setup..."
        breakfast "$device_codename" >/dev/null 2>&1 || true
    fi

    ((current_step++))
    [[ "$DEBUG" -eq 0 ]] && clear
    show_progress "$current_step" "$total_steps" "Locating device tree..."

    google_family=$(get_google_family "$device_codename")
    primary_device_path=$(find_device_tree "$device_codename" "$google_family")

    if [[ -z "$primary_device_path" ]]; then
        echo
        show_error "Could not locate device tree for '$device_codename'."
        return 1
    fi

    manufacturer=$(resolve_manufacturer "$primary_device_path")

    echo
    show_success "Resolved device tree: $primary_device_path"
    show_success "Resolved manufacturer: $manufacturer"
    [[ -n "$google_family" ]] && show_success "Resolved Google family: $google_family"

    ((current_step++))
    [[ "$DEBUG" -eq 0 ]] && clear
    show_progress "$current_step" "$total_steps" "Ensuring vendor blobs..."

    if ! ensure_vendor_blobs "$device_codename" "$primary_device_path" "$google_family"; then
        return 1
    fi

    ((current_step++))
    [[ "$DEBUG" -eq 0 ]] && clear
    show_progress "$current_step" "$total_steps" "Checking fragile repo projects..."

    repair_external_iptables || return 1

    ((current_step++))
    [[ "$DEBUG" -eq 0 ]] && clear
    show_progress "$current_step" "$total_steps" "Protecting local device changes..."

    stash_device_changes "$primary_device_path" "$google_family" || return 1

    ((current_step++))
    [[ "$DEBUG" -eq 0 ]] && clear
    show_progress "$current_step" "$total_steps" "Final device configuration..."

    echo
    show_warning "Running breakfast to verify environment..."
    breakfast "$device_codename" || return 1

    restore_device_changes

    if [[ -n "$build_variant" ]]; then
        echo
        show_warning "Setting build variant to: $build_variant"
        export TARGET_BUILD_VARIANT="$build_variant"
        export TARGET_BUILD_TYPE="$build_variant"
    fi

    return 0
}

# ================================================================
# ccache
# ================================================================

CCACHE_LINK="prebuilts/misc/linux-x86/ccache/ccache"
if [[ ! -L "$CCACHE_LINK" ]]; then
    echo
    echo -n "Do you have ccache installed? (y/n): "
    read -r has_ccache
    if [[ "$has_ccache" =~ ^[Yy]$ ]]; then
        show_warning "Creating ccache symlink..."
        mkdir -p prebuilts/misc/linux-x86/ccache
        ln -s /usr/bin/ccache "$CCACHE_LINK"
        show_success "Symlink created at $CCACHE_LINK"
    else
        show_warning "Skipping ccache symlink creation."
    fi
else
    show_success "ccache symlink already exists at $CCACHE_LINK"
    echo
fi

# ================================================================
# Device selection loop
# ================================================================

section_header "Device Selection"
while true; do
    prompt_user "Enter the codename of your Android device (e.g., 'marlin', 'tissot'):"
    read -r USER_INPUT

    if [[ -z "$USER_INPUT" ]]; then
        echo
        show_error "Device codename cannot be empty. Please try again."
        continue
    fi

    if [[ "$USER_INPUT" == lineage_*-*-* ]]; then
        DEVICE_CODENAME=$(echo "$USER_INPUT" | sed 's/lineage_\([^-]*\)-.*/\1/')
        LUNCH_COMBO="$USER_INPUT"
        BUILD_VARIANT=$(echo "$USER_INPUT" | sed 's/.*-//')
    else
        DEVICE_CODENAME="$USER_INPUT"
        prompt_user "Build variant - user or userdebug? (default: userdebug)"
        read -r BUILD_VARIANT
        BUILD_VARIANT="${BUILD_VARIANT:-userdebug}"
        LUNCH_COMBO="${ROM_PRODUCT_PREFIX}_${DEVICE_CODENAME}-${ROM_FLAVOR}-${BUILD_VARIANT}"
    fi

    [[ "$DEBUG" -eq 0 ]] && clear

    if setup_device_tree "$DEVICE_CODENAME" "$LUNCH_COMBO" "$BUILD_VARIANT"; then
        [[ "$DEBUG" -eq 0 ]] && clear
        show_success "Successfully configured device $DEVICE_CODENAME"

        echo
        show_warning "Forcing build variant to: $BUILD_VARIANT"
        export TARGET_BUILD_VARIANT="$BUILD_VARIANT"
        export TARGET_BUILD_TYPE="$BUILD_VARIANT"
        export TARGET_PRODUCT="${ROM_PRODUCT_PREFIX}_${DEVICE_CODENAME}"

        LUNCH_COMBO="${ROM_PRODUCT_PREFIX}_${DEVICE_CODENAME}-${ROM_FLAVOR}-${BUILD_VARIANT}"
        lunch "$LUNCH_COMBO"

        [[ "$DEBUG" -eq 0 ]] && clear
        break
    else
        echo
        show_error "Failed to setup device $DEVICE_CODENAME"
        prompt_user "Try another device? (Y/N)"
        read -r retry
        if [[ "$retry" =~ ^[Nn]$ ]]; then
            if is_sourced; then
                return 1
            else
                exit 1
            fi
        fi
    fi
done

add_separator

# ================================================================
# BoardConfig discovery
# ================================================================

GOOGLE_FAMILY=$(get_google_family "$DEVICE_CODENAME")
DEVICE_TREE_PATH=$(find_device_tree "$DEVICE_CODENAME" "$GOOGLE_FAMILY")

if [[ -z "$DEVICE_TREE_PATH" ]]; then
    echo
    show_error "Could not locate device tree for $DEVICE_CODENAME"
    show_warning "Please ensure your device tree is properly synced"
    show_warning "Common locations: device/<vendor>/$DEVICE_CODENAME or device/google/<family>/$DEVICE_CODENAME"
    if is_sourced; then
        return 1
    else
        exit 1
    fi
fi

echo
show_success "Found device tree at: $DEVICE_TREE_PATH"

TARGET_BOARD_CONFIG=$(find_primary_boardconfig "$DEVICE_CODENAME" "$GOOGLE_FAMILY" "$DEVICE_TREE_PATH")

if [[ -z "$TARGET_BOARD_CONFIG" ]]; then
    echo
    show_error "No BoardConfig*.mk found."
    show_warning "Device codename: $DEVICE_CODENAME"
    show_warning "Google family: ${GOOGLE_FAMILY:-<none>}"
    show_warning "Resolved device tree path: ${DEVICE_TREE_PATH:-<none>}"
    if is_sourced; then
        return 1
    else
        exit 1
    fi
fi

[[ "$DEBUG" -eq 0 ]] && clear
show_success "Using configuration file: $TARGET_BOARD_CONFIG"

# ================================================================
# Automatic Build Configurations
# ================================================================

AUTO_CONFIG=(
    "# Automatic build optimizations"
    "BUILD_BROKEN_DISABLE_BAZEL :="
    "BUILD_BROKEN_DUP_RULES := true"
    "DISABLE_ARTIFACT_PATH_REQUIREMENTS := true"
    "SPOOF_FIRST_API_LEVEL_32 := true"
    ""
    "# Debug and optimization flags"
    "ANDROID_COMPILE_WITH_JACK := false"
    ""
    "# Dexpreopt configurations"
    "WITH_DEXPREOPT := false"
    "DONT_DEXPREOPT_PREBUILTS := true"
    ""
)

SKIP_QUESTIONS=false

if grep -q "# Build Optimization Configurations" "$TARGET_BOARD_CONFIG"; then
    echo
    prompt_user "Existing build configuration found in BoardConfig.mk. Skip and use it? (Y/n)"
    read -r use_existing
    [[ "$DEBUG" -eq 0 ]] && clear
    if [[ ! "$use_existing" =~ ^[Nn]$ ]]; then
        show_success "Skipping interactive setup. Existing settings will be used."
        SKIP_QUESTIONS=true
    else
        show_warning "Proceeding with manual configuration. Existing settings will be overwritten."
    fi
fi

add_separator

declare -a FINAL_CONFIG_LINES=()

if [[ "$SKIP_QUESTIONS" == false ]]; then
    [[ "$DEBUG" -eq 0 ]] && clear

    section_header "LTO Configuration"
    while true; do
        prompt_user "Build with LTO? (Thin/Full/None) (T/F/N) [Default: F]"
        read -r response
        response=$(echo "${response:-F}" | tr '[:lower:]' '[:upper:]')
        case "$response" in
            T)
                LTO_CONFIG=("GLOBAL_THINLTO := true" "USE_THINLTO_CACHE := true" "WITH_LTO := false")
                echo; show_success "Building with ThinLTO"
                break
                ;;
            F)
                LTO_CONFIG=("GLOBAL_THINLTO := false" "USE_THINLTO_CACHE := false" "WITH_LTO := true")
                echo; show_success "Building with Full LTO"
                break
                ;;
            N)
                LTO_CONFIG=("GLOBAL_THINLTO := false" "USE_THINLTO_CACHE := false" "WITH_LTO := false")
                echo; show_success "Building without LTO"
                break
                ;;
            *)
                echo; show_error "Invalid input."
                ;;
        esac
    done
    add_separator
    [[ "$DEBUG" -eq 0 ]] && clear

    section_header "ABI Checks Configuration"
    while true; do
        prompt_user "Skip ABI checks during build? (Y/N) [Default: Y]"
        read -r response
        response="${response:-Y}"
        if validate_yn "$response"; then
            if [[ "$(echo "$response" | tr '[:upper:]' '[:lower:]')" == "y" ]]; then
                ABI_CONFIG=("SKIP_ABI_CHECKS := true")
                echo; show_success "ABI checks will be skipped"
            else
                ABI_CONFIG=("SKIP_ABI_CHECKS := false")
                echo; show_success "ABI checks will be enforced"
            fi
            break
        else
            echo; show_error "Invalid input. Please enter 'Y' or 'N'"
        fi
    done
    add_separator
    [[ "$DEBUG" -eq 0 ]] && clear

    section_header "EPPE Configuration"
    while true; do
        prompt_user "Disable Enhanced Privacy Preserving Estimators (EPPE)? (Y/N) [Default: Y]"
        read -r response
        response="${response:-Y}"
        if validate_yn "$response"; then
            if [[ "$(echo "$response" | tr '[:upper:]' '[:lower:]')" == "y" ]]; then
                EPPE_CONFIG=("TARGET_DISABLE_EPPE := true")
                echo; show_success "EPPE will be disabled"
            else
                EPPE_CONFIG=("TARGET_DISABLE_EPPE := false")
                echo; show_success "EPPE will remain enabled"
            fi
            break
        else
            echo; show_error "Invalid input. Please enter 'Y' or 'N'"
        fi
    done
    add_separator
    [[ "$DEBUG" -eq 0 ]] && clear

    section_header "Library Dependency Check"
    while true; do
        prompt_user "Relax library dependency checks? (Y/N) [Default: Y]"
        read -r response
        response="${response:-Y}"
        if validate_yn "$response"; then
            if [[ "$(echo "$response" | tr '[:upper:]' '[:lower:]')" == "y" ]]; then
                LIBRARY_CHECK_CONFIG=("RELAX_USES_LIBRARY_CHECK := true")
                echo; show_success "Library dependency checks will be relaxed"
            else
                LIBRARY_CHECK_CONFIG=("RELAX_USES_LIBRARY_CHECK := false")
                echo; show_success "Strict library dependency checks will be enforced"
            fi
            break
        else
            echo; show_error "Invalid input. Please enter 'Y' or 'N'"
        fi
    done
    add_separator
    [[ "$DEBUG" -eq 0 ]] && clear

    section_header "DEX2OAT Memory Configuration"
    TOTAL_RAM_GB=$(( $(getconf _PHYS_PAGES) * $(getconf PAGE_SIZE) / (1024 * 1024 * 1024) ))
    BASE_MEM=4
    ADDITIONAL_MEM=$(( TOTAL_RAM_GB / 8 ))
    RECOMMENDED_GB=$(( BASE_MEM + ADDITIONAL_MEM ))
    [[ "$RECOMMENDED_GB" -lt 4 ]] && RECOMMENDED_GB=4
    RECOMMENDED_DEX2OAT="${RECOMMENDED_GB}G"

    echo
    echo -e "Detected System RAM: ${GREEN}${TOTAL_RAM_GB}GB${RESET}"

    while true; do
        echo -e "\n${BLUE}Configure DEX2OAT Memory:${RESET}"
        echo "1) Use formula-based recommendation: ${YELLOW}-Xmx${RECOMMENDED_DEX2OAT}${RESET} [Default]"
        echo "2) Enter a custom value"
        echo "3) Use Android's default setting"
        prompt_user "Your choice [1-3]:"
        read -r choice
        choice="${choice:-1}"
        case "$choice" in
            1)
                DEX2OAT_CONFIG=("DEX2OAT_XMX := -Xmx${RECOMMENDED_DEX2OAT}")
                echo; show_success "Set DEX2OAT_XMX=-Xmx${RECOMMENDED_DEX2OAT}"
                break
                ;;
            2)
                prompt_user "Enter custom DEX2OAT heap size (e.g., 6G):"
                read -r dex2oat_heap
                if [[ "$dex2oat_heap" =~ ^[0-9]+[MG]$ ]]; then
                    DEX2OAT_CONFIG=("DEX2OAT_XMX := -Xmx${dex2oat_heap}")
                    echo; show_success "Set DEX2OAT_XMX=-Xmx${dex2oat_heap}"
                    break
                else
                    echo; show_error "Invalid format! Use format like '6G' or '4096M'"
                fi
                ;;
            3)
                DEX2OAT_CONFIG=("")
                echo; show_success "Using Android default for DEX2OAT."
                break
                ;;
            *)
                echo; show_error "Invalid option."
                ;;
        esac
    done
    add_separator

    FINAL_CONFIG_LINES+=( "${AUTO_CONFIG[@]}" )
    FINAL_CONFIG_LINES+=( "${LTO_CONFIG[@]}" )
    FINAL_CONFIG_LINES+=( "${ABI_CONFIG[@]}" )
    FINAL_CONFIG_LINES+=( "${EPPE_CONFIG[@]}" )
    FINAL_CONFIG_LINES+=( "${LIBRARY_CHECK_CONFIG[@]}" )
    FINAL_CONFIG_LINES+=( "${DEX2OAT_CONFIG[@]}" )

    section_header "Writing Configurations to BoardConfig"

    BACKUP_FILE="${TARGET_BOARD_CONFIG}.bak"
    cp "$TARGET_BOARD_CONFIG" "$BACKUP_FILE"
    [[ "$DEBUG" -eq 0 ]] && clear
    echo
    show_success "Created backup of $(basename "$TARGET_BOARD_CONFIG") as $(basename "$BACKUP_FILE")"

    sed -i '/# Build Optimization Configurations/,/# End of Build Optimization Configurations/d' "$TARGET_BOARD_CONFIG"

    echo
    show_warning "Writing new build configurations to $(basename "$TARGET_BOARD_CONFIG")"
    {
        echo ""
        echo "# Build Optimization Configurations"
        echo "# Automatically generated on $(date)"
        echo ""
        printf "%s\n" "${FINAL_CONFIG_LINES[@]}"
        echo ""
        echo "# End of Build Optimization Configurations"
        echo ""
    } >> "$TARGET_BOARD_CONFIG"

    echo
    show_success "All configurations have been written to $(basename "$TARGET_BOARD_CONFIG")"
fi

add_separator
[[ "$DEBUG" -eq 0 ]] && clear

# ================================================================
# Mobile services and launcher configuration
# ================================================================

section_header "Mobile Services Configuration"

while true; do
    echo -e "\n${BLUE}Choose the mobile services implementation:${RESET}"
    echo "1) Google Mobile Services (GMS) [Default]"
    echo "2) microG"
    echo "3) Vanilla — no Google services"

    prompt_user "Your choice [1-3]:"
    read -r services_choice
    services_choice="${services_choice:-1}"

    case "$services_choice" in
        1)
            LOSP_GMS_TYPE="gms"
            export WITH_GMS=true

            echo
            show_success "Google Mobile Services will be included"
            break
            ;;
        2)
            LOSP_GMS_TYPE="microg"
            export WITH_GMS=false

            echo
            show_success "microG will be included"
            break
            ;;
        3)
            LOSP_GMS_TYPE="vanilla"
            export WITH_GMS=false

            echo
            show_success "No Google services will be included"
            break
            ;;
        *)
            echo
            show_error "Invalid option. Please select 1, 2, or 3."
            ;;
    esac
done

export LOSP_GMS_TYPE

add_separator
[[ "$DEBUG" -eq 0 ]] && clear

section_header "Launcher Configuration"

if [[ "$LOSP_GMS_TYPE" != "gms" ]]; then
    TARGET_INCLUDE_PIXEL_LAUNCHER=false
    export TARGET_INCLUDE_PIXEL_LAUNCHER

    echo
    show_success "Pixel Launcher requires GMS; using LOSP Special Launcher"
else
    while true; do
        echo -e "\n${BLUE}Choose default launcher:${RESET}"
        echo "1) LOSP Special Launcher [Default]"
        echo "2) Google Pixel Launcher / Nexus Launcher"

        prompt_user "Your choice [1-2]:"
        read -r launcher_choice
        launcher_choice="${launcher_choice:-1}"

        case "$launcher_choice" in
            1)
                TARGET_INCLUDE_PIXEL_LAUNCHER=false
                echo
                show_success "Using LOSP Special Launcher"
                break
                ;;
            2)
                TARGET_INCLUDE_PIXEL_LAUNCHER=true
                echo
                show_success "Using Google Pixel Launcher / Nexus Launcher"
                break
                ;;
            *)
                echo
                show_error "Invalid option."
                ;;
        esac
    done

    export TARGET_INCLUDE_PIXEL_LAUNCHER
fi

write_losp_build_config \
    "$LOSP_GMS_TYPE" \
    "$TARGET_INCLUDE_PIXEL_LAUNCHER" || return 1

add_separator
[[ "$DEBUG" -eq 0 ]] && clear

# ================================================================
# Final build instructions
# ================================================================

CPU_CORES=$(nproc)

case "${LOSP_GMS_TYPE:-gms}" in
    gms)
        BUILD_FLAVOR="GMS"
        ;;
    microg)
        BUILD_FLAVOR="microG"
        ;;
    vanilla)
        BUILD_FLAVOR="Vanilla"
        ;;
    *)
        BUILD_FLAVOR="Unknown"
        ;;
esac

echo
echo -e "${GREEN}================================================"
echo -e "         Build Configuration Complete!          "
echo -e "================================================${RESET}"
echo
echo -e "ROM: ${CYAN}${ROM_NAME}${RESET}"
echo -e "Device: ${CYAN}${DEVICE_CODENAME}${RESET}"
echo -e "Build variant: ${CYAN}${BUILD_VARIANT}${RESET}"
echo "Build type: $BUILD_FLAVOR"
echo -e "Config file modified: ${CYAN}${TARGET_BOARD_CONFIG}${RESET}"
if [[ "$SKIP_QUESTIONS" == false ]]; then
    echo -e "Backup created: ${CYAN}${BACKUP_FILE}${RESET}"
fi
echo -e "\n${YELLOW}You can now start your build by running:${RESET}"
echo -e "${GREEN}m ${ROM_BUILD_TARGET} -j${CPU_CORES}${RESET}\n"

export PRODUCT_MINIMIZE_JAVA_DEBUG_INFO=true
export ANDROID_JACK_VM_ARGS="-Xmx4g -Dfile.encoding=UTF-8"
export LOGGING=true
export SHOW_COMMANDS=true
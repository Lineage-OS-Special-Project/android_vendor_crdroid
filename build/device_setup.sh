#!/bin/bash

# ================================================================
# LOSP Device Setup Script
# ================================================================

# Default DEBUG if unset
DEBUG="${DEBUG:-0}"

# Use colors only when output is interactive and the terminal supports them.
init_colors() {
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    LOSP_TEAL=''
    RESET=''

    if [[ -t 1 && ! -v NO_COLOR && "${TERM:-}" != "dumb" ]]; then
        RESET=$'\033[0m'
        # Require an explicit true-colour signal; TERM alone is not enough.
        case "${COLORTERM:-}" in
            truecolor|24bit)
                LOSP_TEAL=$'\033[38;2;16;200;200m'
                GREEN=$'\033[38;2;16;200;200m'
                YELLOW=$'\033[38;2;201;150;50m'
                RED=$'\033[38;2;201;87;87m'
                BLUE=$'\033[38;2;129;143;232m'
                ;;
            *)
                LOSP_TEAL=$'\033[36m'
                GREEN=$'\033[32m'
                YELLOW=$'\033[33m'
                RED=$'\033[31m'
                BLUE=$'\033[34m'
                ;;
        esac
    fi
}

init_colors

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
LOSP_GENERATED_CONFIG="${ROM_VENDOR_CONFIG_PATH}/.losp_build_config.mk"

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
    init_colors
    printf '%s✗ %s%s\n' "$RED" "$1" "$RESET" >&2
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
    init_colors
    printf '%s=== %s ===%s\n' "$LOSP_TEAL" "$1" "$RESET"
}

prompt_user() {
    init_colors
    printf '%s» %s%s\n' "$LOSP_TEAL" "$1" "$RESET"
    printf '%s➤ %s' "$LOSP_TEAL" "$RESET"
}

# Read one interactive value and distinguish an empty answer from EOF or an
# interrupted input stream. Clear the destination first so a failed read can
# never leave a previous answer available to its caller.
read_user_input() {
    local input_variable="$1"
    printf -v "$input_variable" '%s' ''
    if ! read -r "$input_variable"; then
        printf '\n'
        printf -v "$input_variable" '%s' ''
        show_error "Input stream closed; aborting LOSP device setup"
        return 1
    fi
    return 0
}

show_warning() {
    init_colors
    printf '%s⚠ %s%s\n' "$YELLOW" "$1" "$RESET"
}

show_success() {
    init_colors
    printf '%s✓ %s%s\n' "$GREEN" "$1" "$RESET"
}

show_error() {
    init_colors
    printf '%s✗ %s%s\n' "$RED" "$1" "$RESET"
}

validate_yn() {
    local input="$1"
    [[ "$input" =~ ^[YyNn]$ ]]
}

add_separator() {
    init_colors
    printf '\n%s------------------------------------------------%s\n\n' "$BLUE" "$RESET"
}

show_progress() {
    init_colors
    local current="$1"
    local total="$2"
    local task="$3"
    local width=50 percentage completed remaining

    [[ "$total" -eq 0 ]] && total=1
    [[ "$current" -gt "$total" ]] && current="$total"

    percentage=$((current * 100 / total))
    completed=$((current * width / total))
    remaining=$((width - completed))

    printf '\r%s[' "$LOSP_TEAL"
    printf '%*s' "$completed" '' | tr ' ' '='
    printf '%*s' "$remaining" '' | tr ' ' '.'
    printf '%s]%s %s%3d%%%s %s%s%s' "$LOSP_TEAL" "$RESET" "$LOSP_TEAL" "$percentage" "$RESET" "$LOSP_TEAL" "$task" "$RESET"

    if [[ "$current" -eq "$total" ]]; then
        printf ' %s✓%s\n' "$GREEN" "$RESET"
    fi
}

# End an in-progress bar before a command or message writes directly to the
# terminal. Completed bars already end with a newline in show_progress.
finish_progress_line() {
    [[ "$1" -lt "$2" ]] && printf '\n'
}

repo_target_exists() {
    local path="$1"

    [[ -e "$path/.git" ]] || return 1
    git --no-pager -C "$path" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
    git --no-pager -C "$path" rev-parse HEAD >/dev/null 2>&1 || return 1

    return 0
}

repo_project_known() {
    local path="$1"
    repo list "$path" >/dev/null 2>&1
}

# Return the LOSP-managed checkout paths that the next manifest would remove.
# Read the old manifest before replacing it so dirty or ambiguous projects are
# never handed to repo's force-removal behavior.
losp_paths_to_remove() {
    local manifest_file="$1" manufacturer="$2" device_codename="$3" common_tree="$4"
    local line checkout_path in_block=0 current_paths project_lists project_list
    local -a new_paths=("vendor/${manufacturer}/${device_codename}")
    [[ -n "$common_tree" && "$manufacturer" != google ]] && new_paths+=("vendor/${manufacturer}/${common_tree}")
    if [[ -e "$manifest_file" && ! -r "$manifest_file" ]]; then
        show_error "Cannot read current LOSP manifest while checking outgoing vendor checkouts: ${manifest_file}"
        return 1
    fi

    if [[ -e "$manifest_file" ]]; then
        while IFS= read -r line || [[ -n "$line" ]]; do
            case "$line" in
                *'<!-- LOSP managed begin -->'*) in_block=1; continue ;;
                *'<!-- LOSP managed end -->'*) in_block=0; continue ;;
            esac
            (( in_block )) || continue
            if [[ "$line" == *'path="'* ]]; then
                checkout_path="${line#*path=\"}"
                checkout_path="${checkout_path%%\"*}"
            else
                continue
            fi
            local kept=0 candidate
            for candidate in "${new_paths[@]}"; do
                [[ "$checkout_path" == "$candidate" ]] && kept=1
            done
            (( kept )) || printf '%s\n' "$checkout_path"
        done < "$manifest_file"
    fi

    # On a retry, roomservice.xml may already name the new device while repo's
    # recorded project.list still contains the outgoing checkout. Compare that
    # recorded state with the current manifest before repo sync reconciles it.
    current_paths=$(repo list -p) || {
        show_error "Cannot enumerate current repo projects before switching devices"
        return 1
    }
    project_lists=$(find .repo -type f -name project.list -print) || {
        show_error "Cannot enumerate repo's recorded project lists before switching devices"
        return 1
    }
    while IFS= read -r project_list; do
        [[ -n "$project_list" ]] || continue
        [[ -r "$project_list" ]] || {
            show_error "Cannot read repo's recorded project list: ${project_list}"
            return 1
        }
        while IFS= read -r checkout_path || [[ -n "$checkout_path" ]]; do
            [[ "$checkout_path" == vendor/* ]] || continue
            if ! printf '%s\n' "$current_paths" | grep -Fqx -- "$checkout_path"; then
                printf '%s\n' "$checkout_path"
            fi
        done < "$project_list"
    done <<< "$project_lists"
}

guard_old_losp_checkouts() {
    local manifest_file="$1" manufacturer="$2" device_codename="$3" common_tree="$4"
    local checkout_path checkout_status bp backup staged_diff other_status ignored_files
    local removed_paths
    removed_paths=$(losp_paths_to_remove "$manifest_file" "$manufacturer" "$device_codename" "$common_tree") || {
        show_error "Failed to enumerate outgoing LOSP-managed repo checkouts; leaving ${manifest_file} unchanged"
        return 1
    }

    while IFS= read -r checkout_path; do
        [[ -n "$checkout_path" ]] || continue
        [[ -e "$checkout_path" ]] || continue
        if ! repo_target_exists "$checkout_path"; then
            show_error "Cannot safely switch devices; inspect and back up local changes, move this checkout aside, then rerun setup: ${checkout_path}"
            return 1
        fi

        checkout_status=$(git --no-pager -C "$checkout_path" status --porcelain=v1 --untracked-files=all 2>/dev/null) || checkout_status='unknown'
        ignored_files=$(git --no-pager -C "$checkout_path" ls-files --others --ignored --exclude-standard 2>/dev/null) || ignored_files='unknown'
        if [[ -n "$ignored_files" ]]; then
            show_error "Cannot safely switch devices; ignored local files may be removed. Inspect and back up local changes, move this checkout outside the source tree, then rerun setup: ${checkout_path}"
            return 1
        fi
        bp="${checkout_path}/Android.bp"
        backup="${bp}.losp-mosey.bak"

        # Restore and remove the backup only when the tracked file contains
        # exactly the wizard edit, with no staged or unrelated local changes.
        if [[ -f "$backup" && -f "$bp" ]] && \
            cmp -s "$backup" <(git --no-pager -C "$checkout_path" show "HEAD:Android.bp") && \
            ! git --no-pager -C "$checkout_path" diff --quiet -- Android.bp; then
            staged_diff=$(git --no-pager -C "$checkout_path" diff --cached --name-only)
            other_status=$(git --no-pager -C "$checkout_path" status --porcelain=v1 --untracked-files=all | awk 'substr($0,4) != "Android.bp" && substr($0,4) != "Android.bp.losp-mosey.bak"')
            if [[ -z "$staged_diff" && -z "$other_status" ]] && \
                cmp -s "$backup" <(git --no-pager -C "$checkout_path" show "HEAD:Android.bp") && \
                python3 - "$bp" "$backup" <<'PY'
import sys
from pathlib import Path

current, original = (Path(p).read_text() for p in sys.argv[1:])
needle = 'name: "MoseyApp"'
if current.count(needle) != 0 or original.count(needle) != 1:
    raise SystemExit(1)
start = original.find(needle)
brace = original.rfind("{", 0, start)
depth = 0
end = None
for pos in range(brace, len(original)):
    if original[pos] == "{":
        depth += 1
    elif original[pos] == "}":
        depth -= 1
        if depth == 0:
            end = pos + 1
            break
if end is None:
    raise SystemExit(1)
while end < len(original) and original[end] in " \t\r\n":
    end += 1
if original[:original.rfind("\n", 0, brace) + 1] + original[end:] != current:
    raise SystemExit(1)
PY
            then
                cp -p "$backup" "$bp" || return 1
                checkout_status=$(git --no-pager -C "$checkout_path" status --porcelain=v1 --untracked-files=all 2>/dev/null) || checkout_status='unknown'
                if [[ -z "$(printf '%s\n' "$checkout_status" | awk 'NF && substr($0,4) != "Android.bp.losp-mosey.bak"')" ]]; then
                    rm -- "$backup" || return 1
                    checkout_status=$(git --no-pager -C "$checkout_path" status --porcelain=v1 --untracked-files=all 2>/dev/null) || checkout_status='unknown'
                fi
            fi
        fi
        if [[ -n "$checkout_status" ]]; then
            show_error "Cannot safely switch devices; inspect and back up local changes, move this checkout outside the source tree, then rerun setup: ${checkout_path}"
            return 1
        fi
    done <<< "$removed_paths"
    return 0
}

refresh_repo_manifest_view() {
    local manifest_file="$1"
    shift
    local -a project_paths=("$@")

    show_warning "Refreshing repo manifest view for LOSP-managed projects..."
    if [[ "${#project_paths[@]}" -eq 0 ]]; then
        show_error "No LOSP-managed project paths were supplied for manifest refresh"
        return 1
    fi

    repo sync -n --no-tags --no-clone-bundle -j1 "${project_paths[@]}" || {
        show_error "Repo could not refresh projects declared by ${manifest_file}"
        return 1
    }
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
                git --no-pager -C "$project_path" fsck --connectivity-only >/dev/null 2>&1 || {
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
        mu64x|sdk_phone_x86_64)
            echo ""
            ;;
        *)
            load_device_mappings google "$device" 2>/dev/null || true
            ;;
    esac
}

load_losp_build_config() {
    local config_file="${1:-$LOSP_GENERATED_CONFIG}"
    local key value
    local valid_keys=0

    WITH_GMS=true
    TARGET_INCLUDE_PIXEL_LAUNCHER=false
    LOSP_PERSISTED_CONFIG_FOUND=false

    if [[ -f "$config_file" ]]; then
        for key in WITH_GMS TARGET_INCLUDE_PIXEL_LAUNCHER; do
            value=$(
                sed -n -E \
                    "s/^[[:space:]]*${key}[[:space:]]*:?=[[:space:]]*(true|false)[[:space:]]*$/\1/p" \
                    "$config_file" | tail -n 1
            )

            if [[ -n "$value" ]]; then
                printf -v "$key" '%s' "$value"
                ((valid_keys++))
            fi
        done

        if [[ "$valid_keys" -eq 2 ]]; then
            LOSP_PERSISTED_CONFIG_FOUND=true
        else
            show_warning "Ignoring incomplete LOSP build configuration: $config_file"
        fi
    fi

    if [[ "$WITH_GMS" != "true" ]]; then
        TARGET_INCLUDE_PIXEL_LAUNCHER=false
    fi

    export WITH_GMS TARGET_INCLUDE_PIXEL_LAUNCHER
}

persist_losp_build_config() {
    local config_file="${1:-$LOSP_GENERATED_CONFIG}"
    local tmp_file="${config_file}.tmp"

    {
        echo "# Generated by vendor/lineage/build/device_setup.sh; do not commit."
        echo "WITH_GMS := ${WITH_GMS:-true}"
        echo "TARGET_INCLUDE_PIXEL_LAUNCHER := ${TARGET_INCLUDE_PIXEL_LAUNCHER:-false}"
    } > "$tmp_file" || return 1

    mv "$tmp_file" "$config_file" || return 1
    LOSP_PERSISTED_CONFIG_FOUND=true
}

load_boardconfig_variant() {
    local board_config="$1"
    local key value
    local config_block

    WITH_GMS=true
    TARGET_INCLUDE_PIXEL_LAUNCHER=false

    config_block=$(
        sed -n \
            '/^[[:space:]]*# Build Optimization Configurations[[:space:]]*$/,/^[[:space:]]*# End of Build Optimization Configurations[[:space:]]*$/p' \
            "$board_config"
    )

    [[ -n "$config_block" ]] || return 1

    for key in WITH_GMS TARGET_INCLUDE_PIXEL_LAUNCHER; do
        value=$(
            printf '%s\n' "$config_block" |
                sed -n -E \
                    "s/^[[:space:]]*${key}[[:space:]]*:?=[[:space:]]*(true|false)[[:space:]]*$/\1/p" |
                tail -n 1
        )

        if [[ -n "$value" ]]; then
            printf -v "$key" '%s' "$value"
        fi
    done

    if [[ "$WITH_GMS" != "true" ]]; then
        TARGET_INCLUDE_PIXEL_LAUNCHER=false
    fi

    export WITH_GMS TARGET_INCLUDE_PIXEL_LAUNCHER
}

find_device_tree() {
    local device_codename="$1"
    local google_family="$2"

    # A mapped Google family is a dependency/common tree, not the product tree.
    # Prefer the exact top-level product tree used by current Pixel sources.
    if [[ -d "device/google/${device_codename}" ]]; then
        echo "device/google/${device_codename}"
        return 0
    fi

    # Some older layouts genuinely nest the product below its family.
    if [[ -n "$google_family" && -d "device/google/${google_family}/${device_codename}" ]]; then
        echo "device/google/${google_family}/${device_codename}"
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

# Restore LOSP-owned choices whenever this helper is sourced. This does not run
# the interactive setup; it only makes the optional generated config visible to
# the current shell (including envsetup.sh --skip-setup).
load_losp_build_config

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
    local managed_begin='  <!-- LOSP managed begin -->'
    local managed_end='  <!-- LOSP managed end -->'

    mkdir -p "$(dirname "$manifest_file")"

    if [[ -f "$manifest_file" ]]; then
        local begin_count end_count
        begin_count=$(grep -Fxc "$managed_begin" "$manifest_file" || true)
        end_count=$(grep -Fxc "$managed_end" "$manifest_file" || true)
        if [[ "$begin_count" -ne "$end_count" || "$begin_count" -gt 1 ]]; then
            show_error "Malformed LOSP managed block in ${manifest_file}; expected one matching begin/end pair"
            return 1
        fi
    fi

    {
        echo '<?xml version="1.0" encoding="UTF-8"?>'
        echo '<manifest>'

        if [[ -f "$manifest_file" ]]; then
            awk -v begin="$managed_begin" -v end="$managed_end" '
                BEGIN { in_managed = 0 }
                index($0, begin) { in_managed = 1; next }
                index($0, end) { in_managed = 0; next }
                in_managed { next }
                /^<\?xml/ || /^<manifest>$/ || /^<\/manifest>$/ { next }
                # Legacy device_setup.sh output: only its exact Muppets vendor
                # project shape is removed. Other projects remain user-owned.
                /<project[[:space:]][^>]*name="TheMuppets\/proprietary_vendor_[^"]+"[[:space:]][^>]*path="vendor\/[^"]+"[^>]*\/>/ { next }
                { print }
            ' "$manifest_file"
        fi

        echo "$managed_begin"
        printf '  <project name="TheMuppets/proprietary_vendor_%s_%s" path="vendor/%s/%s" remote="github" />\n' \
            "$manufacturer" "$device_codename" "$manufacturer" "$device_codename"

        if [[ -n "$common_tree" && "$manufacturer" != "google" ]]; then
            printf '  <project name="TheMuppets/proprietary_vendor_%s_%s" path="vendor/%s/%s" remote="github" />\n' \
                "$manufacturer" "$common_tree" "$manufacturer" "$common_tree"
        fi
        echo "$managed_end"

        echo '</manifest>'
    } > "$tmp_file"

    mv "$tmp_file" "$manifest_file"
}

validate_losp_manifest_projects() {
    local manifest_file="$1"
    local line path marker_begin='<!-- LOSP managed begin -->' marker_end='<!-- LOSP managed end -->'
    local begin_count=0 end_count=0 in_block=0 project_count=0 failed=0
    local path_count remainder

    if [[ ! -r "$manifest_file" ]]; then
        show_error "Cannot read LOSP-managed manifest ${manifest_file}"
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" == *"$marker_begin"* ]]; then
            ((begin_count += 1))
            if (( begin_count != 1 || end_count != 0 || in_block != 0 )); then
                show_error "Malformed LOSP managed markers in ${manifest_file}"
                return 1
            fi
            in_block=1
            # Markers must occupy a line by themselves (allowing indentation).
            [[ "$line" =~ ^[[:space:]]*\<!--[[:space:]]LOSP[[:space:]]managed[[:space:]]begin[[:space:]]--\>[[:space:]]*$ ]] || {
                show_error "Malformed LOSP managed begin marker in ${manifest_file}"
                return 1
            }
            continue
        fi
        if [[ "$line" == *"$marker_end"* ]]; then
            ((end_count += 1))
            if (( end_count != 1 || begin_count != 1 || in_block != 1 )); then
                show_error "Malformed LOSP managed markers in ${manifest_file}"
                return 1
            fi
            [[ "$line" =~ ^[[:space:]]*\<!--[[:space:]]LOSP[[:space:]]managed[[:space:]]end[[:space:]]--\>[[:space:]]*$ ]] || {
                show_error "Malformed LOSP managed end marker in ${manifest_file}"
                return 1
            }
            in_block=0
            continue
        fi
        (( in_block )) || continue

        # Only project elements are permitted in the managed block. Parse path
        # attributes in bash, rejecting malformed XML-ish project lines before
        # any value can reach repo commands.
        [[ "$line" =~ ^[[:space:]]*\<project[[:space:]] ]] || {
            [[ "$line" =~ ^[[:space:]]*$ ]] && continue
            show_error "Malformed entry in LOSP managed block: ${line}"
            return 1
        }
        [[ "$line" =~ ^[[:space:]]*\<project[[:space:]][^\>]*\/[[:space:]]*\>[[:space:]]*$ ]] || {
            show_error "Malformed project entry in LOSP managed block: ${line}"
            return 1
        }
        remainder="$line"
        path_count=0
        while [[ "$remainder" == *'path="'* ]]; do
            remainder="${remainder#*path=\"}"
            ((path_count += 1))
        done
        if [[ "$path_count" -ne 1 ]]; then
            show_error "Malformed project path in LOSP managed block: ${line}"
            return 1
        fi
        path="${line#*path=\"}"
        path="${path%%\"*}"
        if [[ -z "$path" ]]; then
            show_error "Malformed project path in LOSP managed block: ${line}"
            return 1
        fi
        if [[ "$path" == /* || "$path" == *//* || "$path" == . || "$path" == .. || "$path" == ../* || "$path" == */../* || "$path" == */.. ]]; then
            show_error "Unsafe LOSP-managed project path: ${path}"
            return 1
        fi
        ((project_count += 1))
        if ! repo_project_known "$path"; then
            show_error "LOSP-managed project ${path} is not present in the repo manifest"
            failed=1
        elif ! repo_target_exists "$path"; then
            show_error "LOSP-managed project ${path} has no valid checkout after sync"
            failed=1
        fi
    done < "$manifest_file"

    if (( begin_count != 1 || end_count != 1 || in_block != 0 )); then
        show_error "Missing, duplicate, reversed, or unmatched LOSP managed markers in ${manifest_file}"
        return 1
    fi
    if (( project_count == 0 )); then
        show_error "LOSP managed block in ${manifest_file} is empty"
        return 1
    fi

    [[ "$failed" -eq 0 ]]
}

sync_vendor_repo() {
    local repo_path="$1"

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
    show_error "${repo_path} exists but is not a valid checkout; inspect and back up local changes, move this checkout aside, then rerun setup: ${repo_path}"
    return 1
fi

    find .repo -name "*.lock" -type f -delete 2>/dev/null || true

    if repo sync \
        --force-sync \
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

remove_duplicate_moseyapp_for_pixel10() {
    local device_codename="$1"
    local device_bp="vendor/google/${device_codename}/Android.bp"

    case "$device_codename" in
        frankel|blazer|mustang|rango)
            ;;
        *)
            return 0
            ;;
    esac
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

    if ! cp -n "$device_bp" "${device_bp}.losp-mosey.bak"; then
        show_error "Failed to back up ${device_bp}"
        return 1
    fi

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

    guard_old_losp_checkouts "$LOCAL_MANIFEST" "$manufacturer" "$device_codename" "$common_tree" || return 1

    primary_vendor="vendor/${manufacturer}/${device_codename}"
    common_vendor=""
    [[ -n "$common_tree" && "$manufacturer" != "google" ]] && common_vendor="vendor/${manufacturer}/${common_tree}"

    rewrite_roomservice_clean "$LOCAL_MANIFEST" "$manufacturer" "$device_codename" "$common_tree" || {
        show_error "Failed to rewrite ${LOCAL_MANIFEST}"
        return 1
    }

    show_success "Local manifest updated at ${LOCAL_MANIFEST}"
    grep -E "project name=|path=" "$LOCAL_MANIFEST" | tail -n 10

    local -a losp_vendor_projects=("$primary_vendor")
    [[ -n "$common_vendor" ]] && losp_vendor_projects+=("$common_vendor")

    refresh_repo_manifest_view "$LOCAL_MANIFEST" "${losp_vendor_projects[@]}" || {
        show_error "Failed to refresh the repo manifest view after updating ${LOCAL_MANIFEST}"
        return 1
    }

    sync_vendor_repo "$primary_vendor" || return 1
    verify_vendor_repo "$primary_vendor" "Primary vendor" || return 1

    if [[ -n "$common_vendor" ]]; then
        sync_vendor_repo "$common_vendor" || return 1
        verify_vendor_repo "$common_vendor" "Common vendor" || return 1
    else
        show_success "No common vendor verification needed"
    fi

    validate_losp_manifest_projects "$LOCAL_MANIFEST" || {
        show_error "LOSP-managed manifest validation failed; stopping device setup"
        return 1
    }

    remove_duplicate_moseyapp_for_pixel10 "$device_codename" || return 1

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
            if git --no-pager -C "$sdir" status --porcelain | grep -q .; then
                echo "Stashing changes in $sdir"
                git --no-pager -C "$sdir" stash push -m "Auto-stashed by device setup script"
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
            if git --no-pager -C "$sdir" stash list | grep -q "Auto-stashed by device setup script"; then
                echo "Restoring changes in $sdir"
                git --no-pager -C "$sdir" stash pop
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
    finish_progress_line "$current_step" "$total_steps"

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
        finish_progress_line "$current_step" "$total_steps"
        breakfast "$device_codename" >/dev/null 2>&1 || true
    fi

    ((current_step++))
    [[ "$DEBUG" -eq 0 ]] && clear
    show_progress "$current_step" "$total_steps" "Locating device tree..."
    finish_progress_line "$current_step" "$total_steps"

    google_family=$(get_google_family "$device_codename")
    primary_device_path=$(find_device_tree "$device_codename" "$google_family")

    if [[ -z "$primary_device_path" ]]; then
        show_error "Could not locate device tree for '$device_codename'."
        return 1
    fi

    manufacturer=$(resolve_manufacturer "$primary_device_path")

    show_success "Resolved device tree: $primary_device_path"
    show_success "Resolved manufacturer: $manufacturer"
    [[ -n "$google_family" ]] && show_success "Resolved Google family: $google_family"

    ((current_step++))
    [[ "$DEBUG" -eq 0 ]] && clear
    show_progress "$current_step" "$total_steps" "Ensuring vendor blobs..."
    finish_progress_line "$current_step" "$total_steps"

    if ! ensure_vendor_blobs "$device_codename" "$primary_device_path" "$google_family"; then
        return 1
    fi

    ((current_step++))
    [[ "$DEBUG" -eq 0 ]] && clear
    show_progress "$current_step" "$total_steps" "Checking fragile repo projects..."
    finish_progress_line "$current_step" "$total_steps"

    repair_external_iptables || return 1

    ((current_step++))
    [[ "$DEBUG" -eq 0 ]] && clear
    show_progress "$current_step" "$total_steps" "Protecting local device changes..."
    finish_progress_line "$current_step" "$total_steps"

    stash_device_changes "$primary_device_path" "$google_family" || return 1

    ((current_step++))
    [[ "$DEBUG" -eq 0 ]] && clear
    show_progress "$current_step" "$total_steps" "Final device configuration..."
    finish_progress_line "$current_step" "$total_steps"

    show_warning "Running breakfast to verify environment..."
    if ! breakfast "$device_codename"; then
        restore_device_changes
        return 1
    fi

    restore_device_changes || return 1

    if [[ -n "$build_variant" ]]; then
        echo
        show_warning "Setting build variant to: $build_variant"
        export TARGET_BUILD_VARIANT="$build_variant"
        export TARGET_BUILD_TYPE="$build_variant"
    fi

    return 0
}

# Sourcing this file is interactive-setup-free. build/envsetup.sh invokes this
# function automatically unless --skip-setup is supplied.
losp_device_setup() {
export NINJA_STATUS=$'[\033[1;32m%f\033[0m/\033[1;36m%t\033[0m (\033[1;34m%p\033[0m) Elapsed: \033[1;33m%es\033[0m]                                          '
[[ "$DEBUG" -eq 0 ]] && clear

# ================================================================
# ccache
# ================================================================

CCACHE_LINK="prebuilts/misc/linux-x86/ccache/ccache"
if [[ -L "$CCACHE_LINK" && ! -e "$CCACHE_LINK" ]]; then
    show_warning "Removing broken ccache symlink at $CCACHE_LINK"
    rm "$CCACHE_LINK"
fi

if [[ ! -e "$CCACHE_LINK" ]]; then
    echo
    echo -n "Do you have ccache installed? (y/n): "
    read_user_input has_ccache || return 1
    if [[ "$has_ccache" =~ ^[Yy]$ ]]; then
        local ccache_binary
        ccache_binary=$(command -v ccache 2>/dev/null)
        if [[ -n "$ccache_binary" && -x "$ccache_binary" ]]; then
            show_warning "Creating ccache symlink..."
            mkdir -p prebuilts/misc/linux-x86/ccache
            ln -s "$ccache_binary" "$CCACHE_LINK"
            show_success "Symlink created at $CCACHE_LINK"
        else
            show_warning "ccache was requested but no executable was found in PATH"
        fi
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
    read_user_input USER_INPUT || return 1

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
        read_user_input BUILD_VARIANT || return 1
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

        if ! lunch "$LUNCH_COMBO"; then
            show_error "Final lunch configuration failed: $LUNCH_COMBO"
            return 1
        fi

        [[ "$DEBUG" -eq 0 ]] && clear
        break
    else
        echo
        show_error "Failed to setup device $DEVICE_CODENAME"
        prompt_user "Try another device? (Y/N)"
        read_user_input retry || return 1
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
    "# LOSP build options selected by the device setup wizard"
    "BUILD_BROKEN_DUP_RULES := true"
    ""
)

SKIP_QUESTIONS=false

if grep -q "# Build Optimization Configurations" "$TARGET_BOARD_CONFIG"; then
    echo
    prompt_user "Existing build configuration found in BoardConfig.mk. Skip and use it? (Y/n)"
    read_user_input use_existing || return 1
    [[ "$DEBUG" -eq 0 ]] && clear
    if [[ ! "$use_existing" =~ ^[Nn]$ ]]; then
        show_success "Skipping interactive setup. Existing settings will be used."
        SKIP_QUESTIONS=true
    else
        show_warning "Proceeding with manual configuration. Existing settings will be overwritten."
    fi
fi

if [[ "$SKIP_QUESTIONS" == true && "$LOSP_PERSISTED_CONFIG_FOUND" != true ]]; then
    load_boardconfig_variant "$TARGET_BOARD_CONFIG"
    persist_losp_build_config || {
        show_error "Could not persist LOSP build selection to $LOSP_GENERATED_CONFIG"
        return 1
    }
fi

add_separator

declare -a FINAL_CONFIG_LINES=()

if [[ "$SKIP_QUESTIONS" == false ]]; then
    [[ "$DEBUG" -eq 0 ]] && clear

    section_header "LTO Configuration"
    while true; do
        prompt_user "Build with LTO? (Thin/Full/None) (T/F/N) [Default: F]"
        read_user_input response || return 1
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
        read_user_input response || return 1
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
        read_user_input response || return 1
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
        read_user_input response || return 1
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

    section_header "GMS Configuration"
    while true; do
        prompt_user "Include GMS? (Y/N) [Default: Y]"
        read_user_input response || return 1
        response="${response:-Y}"
        if validate_yn "$response"; then
            if [[ "$(echo "$response" | tr '[:upper:]' '[:lower:]')" == "y" ]]; then
                GMS_CONFIG=("WITH_GMS := true")
                export WITH_GMS=true
                echo
                show_success "GMS will be included"
            else
                GMS_CONFIG=("WITH_GMS := false")
                export WITH_GMS=false
                export TARGET_INCLUDE_PIXEL_LAUNCHER=false
                echo
                show_success "GMS will be excluded"
            fi
            break
        else
            echo
            show_error "Invalid input. Please enter 'Y' or 'N'"
        fi
    done
    add_separator
    [[ "$DEBUG" -eq 0 ]] && clear

    section_header "Launcher Configuration"
    if [[ "${WITH_GMS:-false}" != "true" ]]; then
        LAUNCHER_CONFIG=("TARGET_INCLUDE_PIXEL_LAUNCHER := false")
        export TARGET_INCLUDE_PIXEL_LAUNCHER=false
        echo
        show_success "GMS disabled; forcing LOSP Special Launcher"
    else
        while true; do
            echo -e "\n${BLUE}Choose default launcher:${RESET}"
            echo "1) LOSP Special Launcher [Default]"
            echo "2) Google Pixel Launcher / Nexus Launcher"
            prompt_user "Your choice [1-2]:"
            read_user_input launcher_choice || return 1
            launcher_choice="${launcher_choice:-1}"

            case "$launcher_choice" in
                1)
                    LAUNCHER_CONFIG=("TARGET_INCLUDE_PIXEL_LAUNCHER := false")
                    export TARGET_INCLUDE_PIXEL_LAUNCHER=false
                    echo
                    show_success "Using LOSP Special Launcher"
                    break
                    ;;
                2)
                    LAUNCHER_CONFIG=("TARGET_INCLUDE_PIXEL_LAUNCHER := true")
                    export TARGET_INCLUDE_PIXEL_LAUNCHER=true
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
    fi
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
        read_user_input choice || return 1
        choice="${choice:-1}"
        case "$choice" in
            1)
                DEX2OAT_CONFIG=("DEX2OAT_XMX := -Xmx${RECOMMENDED_DEX2OAT}")
                echo; show_success "Set DEX2OAT_XMX=-Xmx${RECOMMENDED_DEX2OAT}"
                break
                ;;
            2)
                prompt_user "Enter custom DEX2OAT heap size (e.g., 6G):"
                read_user_input dex2oat_heap || return 1
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
    FINAL_CONFIG_LINES+=( "${GMS_CONFIG[@]}" )
    FINAL_CONFIG_LINES+=( "${LAUNCHER_CONFIG[@]}" )
    FINAL_CONFIG_LINES+=( "${DEX2OAT_CONFIG[@]}" )

    persist_losp_build_config || {
        show_error "Could not persist LOSP build selection to $LOSP_GENERATED_CONFIG"
        return 1
    }

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

# ================================================================
# Final build instructions
# ================================================================

CPU_CORES=$(nproc)

if [[ "${WITH_GMS:-false}" == "true" ]]; then
    BUILD_FLAVOR="GMS"
else
    BUILD_FLAVOR="Vanilla"
fi

echo
echo -e "${GREEN}================================================"
echo -e "         Build Configuration Complete!          "
echo -e "================================================${RESET}"
echo
init_colors
printf 'ROM: %s%s%s\n' "$LOSP_TEAL" "$ROM_NAME" "$RESET"
printf 'Device: %s%s%s\n' "$LOSP_TEAL" "$DEVICE_CODENAME" "$RESET"
printf 'Build variant: %s%s%s\n' "$LOSP_TEAL" "$BUILD_VARIANT" "$RESET"
echo "Build type: $BUILD_FLAVOR"
printf 'Config file modified: %s%s%s\n' "$LOSP_TEAL" "$TARGET_BOARD_CONFIG" "$RESET"
if [[ "$SKIP_QUESTIONS" == false ]]; then
    printf 'Backup created: %s%s%s\n' "$LOSP_TEAL" "$BACKUP_FILE" "$RESET"
fi
echo -e "\n${YELLOW}You can now start your build by running:${RESET}"
echo -e "${GREEN}m ${ROM_BUILD_TARGET} -j${CPU_CORES}${RESET}\n"

export PRODUCT_MINIMIZE_JAVA_DEBUG_INFO=true
export LOGGING=true
export SHOW_COMMANDS=true
}

if ! is_sourced; then
    losp_device_setup "$@"
fi

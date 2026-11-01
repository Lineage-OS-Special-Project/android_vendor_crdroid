#!/bin/bash

# Print a best-effort summary for the exact package produced by losp.mk.
# Arguments are the package path and its already-generated .sha256sum sidecar.
set +e

package=${1-}
checksum_file=${2-}
[ -n "$package" ] || exit 0

# Only use terminal colors when output is interactive and the terminal can
# provide the requested semantic colors. Keep redirected/CI output plain.
color_heading=
color_success=
color_reset=
if [ -t 1 ] && [ -z "${NO_COLOR+x}" ] && [ "${TERM-}" != dumb ]; then
    color_reset=$(printf '\033[0m')
    case "${COLORTERM-}" in
        truecolor|24bit)
            color_heading=$(printf '\033[38;2;16;200;200m')
            color_success=$(printf '\033[38;2;69;169;120m')
            ;;
        *)
            color_heading=$(printf '\033[36m')
            color_success=$(printf '\033[32m')
            ;;
    esac
fi

size=
if [ -f "$package" ]; then
    size=$(du -h "$package" 2>/dev/null | awk 'NR == 1 { print $1 }')
fi

checksum=
if [ -n "$checksum_file" ] && [ -r "$checksum_file" ]; then
    # The sidecar format is "<hash>  <filename>"; display only the hash.
    checksum=$(awk 'NR == 1 { print $1; exit }' "$checksum_file" 2>/dev/null)
fi

printf '%sLOSP package ready%s\n' "$color_heading" "$color_reset"
printf '%sArtifact:%s %s\n' "$color_success" "$color_reset" "$package"
[ -n "$size" ] && printf 'Size:     %s\n' "$size"
if [ -n "$checksum" ]; then
    printf 'SHA-256:  %s\n' "$checksum"
else
    printf 'SHA-256:  unavailable\n'
fi

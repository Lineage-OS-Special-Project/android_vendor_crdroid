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
if [ -t 1 ] && [ -z "${NO_COLOR+x}" ] && [ -n "${TERM-}" ] && [ "$TERM" != dumb ] && command -v tput >/dev/null 2>&1; then
    if [ "$(tput colors 2>/dev/null)" -ge 8 ] 2>/dev/null; then
        color_heading=$(tput setaf 6 2>/dev/null)
        color_success=$(tput setaf 2 2>/dev/null)
        color_reset=$(tput sgr0 2>/dev/null)
    fi
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

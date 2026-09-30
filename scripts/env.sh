#!/usr/bin/env bash
# Print pinned values (versions/common.env + versions/<gcc>.env) with ${...}
# references expanded.
#
#   scripts/env.sh                        all KEY=VALUE lines (default GCC)
#   scripts/env.sh GCC_SHA256             just one value
#   scripts/env.sh --github               KEY=VALUE lines for $GITHUB_ENV/$GITHUB_OUTPUT
#   scripts/env.sh --list                 GCC versions that have a pin file
#   PA_GCC_VERSION=15.3.0 scripts/env.sh  select a version
#
# Used by the workflows so that YAML never duplicates a pin.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${here}/lib/common.sh"

if [ "${1:-}" = --list ]; then
    pa_versions_available
    exit 0
fi

pa_load_versions

keys() {
    cat "${PA_ROOT}/versions/common.env" "${PA_ROOT}/versions/${PA_GCC_VERSION}.env" \
        | grep -E '^[A-Z_][A-Za-z0-9_]*=' | cut -d= -f1 | awk '!seen[$0]++'
}

case "${1:-}" in
    ""|--github)
        for k in $(keys); do printf '%s=%s\n' "$k" "${!k}"; done
        printf 'PA_GCC_VERSION=%s\n' "${PA_GCC_VERSION}"
        printf 'PA_HG_VERSION=%s\n' "${PA_HG_VERSION}"
        printf 'PA_ARCHIVE_NAME_PATTERN=gnat-<arch>-<os>-%s\n' "${GCC_VERSION}"
        ;;
    *)
        [ -n "${!1:-}" ] || pa_die "unknown key: $1"
        printf '%s\n' "${!1}"
        ;;
esac

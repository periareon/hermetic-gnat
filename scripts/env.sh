#!/usr/bin/env bash
# Print pinned values from versions.env with ${...} references expanded.
#
#   scripts/env.sh                 -> all KEY=VALUE lines
#   scripts/env.sh GCC_VERSION     -> just the value
#   scripts/env.sh --github        -> KEY=VALUE lines suitable for $GITHUB_ENV
#
# Used by the workflows so that YAML never duplicates a pin.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${here}/lib/common.sh"
pa_load_versions

keys() {
    grep -E '^[A-Z_][A-Za-z0-9_]*=' "${PA_ROOT}/versions.env" | cut -d= -f1
}

case "${1:-}" in
    ""|--github)
        for k in $(keys); do printf '%s=%s\n' "$k" "${!k}"; done
        printf 'PA_RELEASE_VERSION=%s\n' "${PA_RELEASE_VERSION}"
        printf 'PA_RELEASE_TAG=%s\n' "${PA_RELEASE_TAG}"
        ;;
    *)
        [ -n "${!1:-}" ] || pa_die "unknown key: $1"
        printf '%s\n' "${!1}"
        ;;
esac

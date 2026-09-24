#!/usr/bin/env bash
# Verify a release archive: checksum sidecar, extraction into a fresh
# temporary directory (so nothing about the build location can help), then
# scripts/check.sh on the result.
#
#   scripts/ci/test-archive.sh path/to/gnat-<arch>-<os>-<ver>.tar.gz

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${here}/../lib/common.sh"

[ $# -eq 1 ] || pa_die "usage: $0 <archive.tar.gz>"
archive="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
[ -f "${archive}" ] || pa_die "no such file: ${archive}"
name="$(basename "${archive}" .tar.gz)"

if [ -f "${archive}.sha256" ]; then
    expected="$(cut -d' ' -f1 "${archive}.sha256")"
    pa_verify_sha256 "${archive}" "${expected}"
    pa_log "checksum sidecar verified"
else
    pa_warn "no .sha256 sidecar next to ${archive}"
fi

# Somewhere with a short, unrelated path.  TMPDIR is honoured.
tmp="$(mktemp -d "${TMPDIR:-/tmp}/pa-check-XXXXXX")"
trap 'rm -rf "${tmp}"' EXIT
pa_log "extracting to ${tmp}"
tar -xzf "${archive}" -C "${tmp}"
[ -d "${tmp}/${name}" ] || pa_die "archive does not contain a top-level ${name}/ directory"

# The top-level directory must be the only entry (rules_ada strips it).
entries="$(ls -A "${tmp}" | wc -l | tr -d ' ')"
[ "${entries}" = 1 ] || pa_die "archive has ${entries} top-level entries, expected exactly ${name}/"

bash "${here}/../check.sh" "${tmp}/${name}"

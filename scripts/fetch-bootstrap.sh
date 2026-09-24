#!/usr/bin/env bash
# Install the pinned bootstrap GNAT (macOS and Windows only).
#
# On Linux the bootstrap compiler is the distribution GNAT inside the pinned
# build container, so this script is a no-op there.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${here}/lib/common.sh"
pa_init

if [ "${PA_OS}" = linux ]; then
    pa_log "linux: bootstrap GNAT comes from the build container; nothing to fetch"
    command -v gnatmake >/dev/null 2>&1 || pa_die "no gnatmake in PATH; run inside the container (scripts/linux/docker-build.sh)"
    exit 0
fi

var="BOOTSTRAP_SHA256_${PA_OS}_${PA_ARCH}"
sha="${!var:-}"
[ -n "${sha}" ] || pa_die "no bootstrap archive pinned for ${PA_PLATFORM} (${var})"

name="gnat-${PA_ARCH}-${PA_OSNAME}-${BOOTSTRAP_GNAT_VERSION}"
tarball="${PA_DOWNLOADS}/${name}.tar.gz"
pa_fetch "${BOOTSTRAP_BASE_URL}/${name}.tar.gz" "${sha}" "${tarball}"

if [ -x "${PA_BOOTSTRAP}/bin/gnatmake${PA_EXE}" ]; then
    pa_log "bootstrap already installed at ${PA_BOOTSTRAP}"
else
    rm -rf "${PA_BOOTSTRAP}"
    pa_extract "${tarball}" "${PA_BOOTSTRAP}" 1
fi

pa_setup_path
pa_log "bootstrap compiler: $(gcc --version | head -1)"
gnatmake --version | head -1 >&2

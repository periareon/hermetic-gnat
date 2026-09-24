#!/usr/bin/env bash
# Build, package and verify the GNAT toolchain for the machine this runs on.
#
#   scripts/build-all.sh                 everything
#   PA_STAGES="gcc package" scripts/build-all.sh
#                                        only the named stages
#   PA_SKIP_CHECK=1                      do not run the archive checks
#   PA_WORK=/big/disk                    scratch location (default ./work)
#   PA_JOBS=8                            parallelism
#
# Linux builds must run inside the pinned container; use
# scripts/linux/docker-build.sh, which wraps this script.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${here}/lib/common.sh"
pa_init

pa_log "platform ${PA_PLATFORM}, GCC ${GCC_VERSION} release ${PKG_RELEASE}, ${PA_JOBS} jobs"
pa_log "work dir ${PA_WORK}"

case "${PA_OS}" in
    linux)   default_stages="fetch bootstrap deps binutils gcc package check" ;;
    darwin)  default_stages="fetch bootstrap deps gcc package check" ;;
    windows) default_stages="fetch bootstrap deps binutils mingw gcc package check" ;;
esac
stages="${PA_STAGES:-${default_stages}}"

start_all=$(date +%s)
for stage in ${stages}; do
    start=$(date +%s)
    pa_log "===== stage: ${stage} ====="
    case "${stage}" in
        fetch)     "${here}/fetch-sources.sh" ;;
        bootstrap) "${here}/fetch-bootstrap.sh" ;;
        deps)      "${here}/build-deps.sh" ;;
        binutils)  "${here}/build-binutils.sh" ;;
        mingw)     "${here}/build-mingw.sh" ;;
        gcc)       "${here}/build-gcc.sh" ;;
        package)   "${here}/package.sh" ;;
        check)
            if [ -n "${PA_SKIP_CHECK:-}" ]; then
                pa_log "PA_SKIP_CHECK set; skipping"
            else
                "${here}/ci/test-archive.sh" "${PA_OUT}/$(pa_release_name).tar.gz"
            fi
            ;;
        *) pa_die "unknown stage: ${stage}" ;;
    esac
    pa_log "===== stage ${stage} done in $(( $(date +%s) - start ))s ====="
done
pa_log "all done in $(( $(date +%s) - start_all ))s; archives in ${PA_OUT}"
ls -la "${PA_OUT}" >&2

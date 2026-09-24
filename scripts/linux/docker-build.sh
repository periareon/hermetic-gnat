#!/usr/bin/env bash
# Run the Linux build inside the pinned container (versions.env:
# LINUX_CONTAINER).  Works identically on a laptop and on a GitHub runner.
#
#   scripts/linux/docker-build.sh                 native architecture
#   PA_DOCKER_PLATFORM=linux/arm64 scripts/linux/docker-build.sh
#                                                 cross-arch via qemu (slow)
#   PA_WORK=/big/disk PA_JOBS=8 scripts/linux/docker-build.sh
#
# The repository is mounted read-only at /src; everything is written to the
# work directory, which is chowned back to the invoking user at the end.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${here}/../lib/common.sh"
pa_load_versions

PA_WORK="${PA_WORK:-${PA_ROOT}/work}"
mkdir -p "${PA_WORK}"
PA_WORK="$(cd "${PA_WORK}" && pwd)"

docker_args=(run --rm --init)
if [ -n "${PA_DOCKER_PLATFORM:-}" ]; then
    docker_args+=(--platform "${PA_DOCKER_PLATFORM}")
fi
if [ -t 1 ]; then
    docker_args+=(-t)
fi

pa_log "container: ${LINUX_CONTAINER}"
pa_log "work dir:  ${PA_WORK}"

exec docker "${docker_args[@]}" \
    -v "${PA_ROOT}:/src:ro" \
    -v "${PA_WORK}:/work" \
    -e "PA_JOBS=${PA_JOBS:-$(pa_nproc)}" \
    -e "PA_STAGES=${PA_STAGES:-}" \
    -e "PA_SKIP_CHECK=${PA_SKIP_CHECK:-}" \
    -e "PA_REPO_URL=${PA_REPO_URL:-}" \
    -e "GITHUB_REPOSITORY=${GITHUB_REPOSITORY:-}" \
    -e "SOURCE_DATE_EPOCH=$(pa_source_date_epoch)" \
    -e "PA_GIT_SHA=$(pa_git_sha)" \
    -e "PA_HOST_UID=$(id -u)" \
    -e "PA_HOST_GID=$(id -g)" \
    "${LINUX_CONTAINER}" \
    bash /src/scripts/linux/container-entry.sh

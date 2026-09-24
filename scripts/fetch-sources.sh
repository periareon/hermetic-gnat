#!/usr/bin/env bash
# Download (with checksum verification) and unpack every source tarball the
# current platform needs, then fix the GCC target triple for this build.
#
# Idempotent: cached tarballs are re-verified, unpacked trees are reused.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${here}/lib/common.sh"
pa_init

# fetch_and_unpack NAME URL SHA256 SRCDIR_NAME
fetch_and_unpack() {
    local name="$1" url="$2" sha="$3" srcdir="$4"
    local tarball
    tarball="${PA_DOWNLOADS}/$(basename "${url}")"
    pa_fetch "${url}" "${sha}" "${tarball}"
    if [ -d "${PA_SRC}/${srcdir}" ]; then
        pa_log "already unpacked: ${srcdir}"
    else
        pa_extract "${tarball}" "${PA_SRC}"
        [ -d "${PA_SRC}/${srcdir}" ] || pa_die "${name}: expected ${PA_SRC}/${srcdir} after extraction"
    fi
}

# GCC itself: FSF release tarball everywhere except macOS.
if [ "${PA_OS}" = darwin ]; then
    fetch_and_unpack gcc "${GCC_DARWIN_URL}" "${GCC_DARWIN_SHA256}" "${GCC_DARWIN_SRCDIR}"
    GCC_SRCDIR="${GCC_DARWIN_SRCDIR}"
else
    fetch_and_unpack gcc "${GCC_URL}" "${GCC_SHA256}" "gcc-${GCC_VERSION}"
    GCC_SRCDIR="gcc-${GCC_VERSION}"
fi
# Stable pointer used by the other stages (a file, not a symlink: msys2
# turns directory symlinks into full copies).
printf '%s' "${GCC_SRCDIR}" > "${PA_WORK}/gcc-srcdir"
gcc_src="$(pa_gcc_src)"

# Sanity: the fork must be the same GCC version we claim to ship.
base_ver="$(tr -d '[:space:]' < "${gcc_src}/gcc/BASE-VER")"
[ "${base_ver}" = "${GCC_VERSION}" ] || pa_die "source tree is GCC ${base_ver}, versions.env says ${GCC_VERSION}"

fetch_and_unpack gmp  "${GMP_URL}"  "${GMP_SHA256}"  "gmp-${GMP_VERSION}"
fetch_and_unpack mpfr "${MPFR_URL}" "${MPFR_SHA256}" "mpfr-${MPFR_VERSION}"
fetch_and_unpack mpc  "${MPC_URL}"  "${MPC_SHA256}"  "mpc-${MPC_VERSION}"
if [ "${PA_OS}" != darwin ]; then
    fetch_and_unpack isl "${ISL_URL}" "${ISL_SHA256}" "isl-${ISL_VERSION}"
    fetch_and_unpack binutils "${BINUTILS_URL}" "${BINUTILS_SHA256}" "binutils-${BINUTILS_VERSION}"
fi
if [ "${PA_OS}" = windows ]; then
    fetch_and_unpack mingw "${MINGW_URL}" "${MINGW_SHA256}" "mingw-w64-v${MINGW_VERSION}"
fi

# ---------------------------------------------------------------------------
# Target triple.  Canonical config.guess output on Linux/macOS (matches what
# a plain native GCC configure would choose), fixed on Windows where the
# shell environment's guess is not what GCC expects.
# ---------------------------------------------------------------------------
case "${PA_OS}" in
    windows)
        [ "${PA_ARCH}" = x86_64 ] || pa_die "no GNAT target exists for Windows on ${PA_ARCH} (see README)"
        triple=x86_64-w64-mingw32
        ;;
    *)
        guessed="$("${gcc_src}/config.guess")"
        triple="$("${gcc_src}/config.sub" "${guessed}")"
        ;;
esac
printf '%s' "${triple}" > "${PA_WORK}/triple"
pa_log "target triple: ${triple}"

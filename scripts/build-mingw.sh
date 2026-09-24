#!/usr/bin/env bash
# Build the mingw-w64 headers and CRT (Windows only) into $PA_WORK/mingw64.
#
# Mirrors the GNAT-FSF-builds recipe: msvcrt as the default C runtime (present
# on every Windows since XP, no redistributable needed) and Windows 7 as the
# minimum API level.  build-gcc.sh merges the result into the GCC tree.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${here}/lib/common.sh"
pa_init
pa_setup_path
triple="$(pa_triple)"

[ "${PA_OS}" = windows ] || { pa_log "${PA_OS}: mingw-w64 not needed"; exit 0; }

MINGW_PREFIX="${PA_WORK}/mingw64"
export MINGW_PREFIX
if [ -f "${MINGW_PREFIX}/.done" ]; then
    pa_log "mingw-w64 already built in ${MINGW_PREFIX}"
    exit 0
fi
rm -rf "${MINGW_PREFIX}"; mkdir -p "${MINGW_PREFIX}"

src="${PA_SRC}/mingw-w64-v${MINGW_VERSION}"

# --- headers -----------------------------------------------------------------
# Installed first and separately so the CRT is compiled against exactly these
# headers rather than whatever the bootstrap compiler ships.
bld="${PA_BUILD}/mingw-headers"
rm -rf "${bld}"; mkdir -p "${bld}"
(
    cd "${bld}"
    pa_run "${src}/mingw-w64-headers/configure" \
        "--prefix=${MINGW_PREFIX}" \
        "--build=${triple}" "--host=${triple}" \
        --enable-sdk=all --enable-idl --without-widl \
        "--with-default-win32-winnt=${MINGW_WINNT}" \
        --with-default-msvcrt=msvcrt
    pa_run make install
)
rm -rf "${bld}"
# The winpthreads compatibility shims are not wanted with --enable-threads=win32.
rm -f "${MINGW_PREFIX}/include/pthread_time.h" \
      "${MINGW_PREFIX}/include/pthread_signal.h" \
      "${MINGW_PREFIX}/include/pthread_unistd.h"

# --- crt ----------------------------------------------------------------------
bld="${PA_BUILD}/mingw-crt"
rm -rf "${bld}"; mkdir -p "${bld}"
(
    cd "${bld}"
    pa_run "${src}/mingw-w64-crt/configure" \
        "--prefix=${MINGW_PREFIX}" \
        "--with-sysroot=${MINGW_PREFIX}" \
        "--build=${triple}" "--host=${triple}" \
        --enable-wildcard \
        --disable-dependency-tracking \
        --with-default-msvcrt=msvcrt \
        CFLAGS="-O2 -Wno-expansion-to-defined"
    # The CRT build is not reliably parallel-safe.
    pa_run make -j1
    pa_run make install -j1
)
rm -rf "${bld}"

# GCC provides its own crtbegin/crtend.
rm -f "${MINGW_PREFIX}/lib/crtbegin.o" "${MINGW_PREFIX}/lib/crtend.o"
touch "${MINGW_PREFIX}/.done"
pa_log "mingw-w64 ${MINGW_VERSION} installed in ${MINGW_PREFIX}"

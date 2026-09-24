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
# Note: pthread_time.h / pthread_signal.h / pthread_unistd.h are one-line
# placeholders that unistd.h, time.h and signal.h include unconditionally
# (winpthreads would replace them).  They must stay: without winpthreads
# (--enable-threads=win32) nothing else provides them, and libgcc fails to
# compile.

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
    # msys2 builds the CRT in parallel; serial took 30 minutes on a runner.
    pa_run make -j"${PA_JOBS}"
    pa_run make install -j1
)
rm -rf "${bld}"

# GCC provides its own crtbegin/crtend.
rm -f "${MINGW_PREFIX}/lib/crtbegin.o" "${MINGW_PREFIX}/lib/crtend.o"
touch "${MINGW_PREFIX}/.done"
pa_log "mingw-w64 ${MINGW_VERSION} installed in ${MINGW_PREFIX}"

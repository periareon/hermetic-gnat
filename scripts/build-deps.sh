#!/usr/bin/env bash
# Build GMP, MPFR, MPC and (except on macOS) ISL as static, PIC libraries
# into $PA_DEPS.  They are linked into the compiler proper, so the shipped
# toolchain has no runtime dependency on them.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${here}/lib/common.sh"
pa_init
pa_setup_path
triple="$(pa_triple)"

if [ -f "${PA_DEPS}/.done" ]; then
    pa_log "deps already built in ${PA_DEPS}"
    exit 0
fi

# Common configure options.  --with-pic matters: stage 2/3 of the GCC
# bootstrap are compiled by a compiler that defaults to PIE on Linux, and
# non-PIC static archives cannot be linked into PIE executables.
common=(
    "--prefix=${PA_DEPS}"
    "--build=${triple}" "--host=${triple}"
    --disable-shared --enable-static --with-pic
    --disable-dependency-tracking
)

build_one() {
    local name="$1"; shift
    local src="${PA_SRC}/${name}"
    local bld="${PA_BUILD}/${name}"
    pa_log "building ${name}"
    rm -rf "${bld}"; mkdir -p "${bld}"
    (
        cd "${bld}"
        pa_run "${src}/configure" "${common[@]}" "$@"
        pa_run make -j"${PA_JOBS}"
        pa_run make install
    )
    rm -rf "${bld}"
}

# gmp: -std=gnu17 keeps 6.3.0 building with GCC >= 15 (C23 default).
build_one "gmp-${GMP_VERSION}" CFLAGS="-O2 -std=gnu17"
build_one "mpfr-${MPFR_VERSION}" "--with-gmp=${PA_DEPS}"
build_one "mpc-${MPC_VERSION}"  "--with-gmp=${PA_DEPS}" "--with-mpfr=${PA_DEPS}"
if [ "${PA_OS}" != darwin ]; then
    build_one "isl-${ISL_VERSION}" "--with-gmp-prefix=${PA_DEPS}"
fi

# No libtool archives: they embed absolute build paths and confuse later links.
find "${PA_DEPS}" -name '*.la' -delete
touch "${PA_DEPS}/.done"

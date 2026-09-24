#!/usr/bin/env bash
# Build GNU binutils straight into the toolchain prefix (Linux and Windows).
#
# The assembler and linker land in bin/ and <triple>/bin/ as usual;
# package.sh additionally copies as/ld into libexec/gcc/<triple>/<version>/
# so that gcc finds them without consulting PATH (that is the first place the
# driver looks, and it is inside the file set rules_ada hands to the sandbox).

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${here}/lib/common.sh"
pa_init
pa_setup_path
triple="$(pa_triple)"

case "${PA_OS}" in
    linux|windows) ;;
    *) pa_log "${PA_OS}: system assembler/linker are used; skipping binutils"; exit 0 ;;
esac

if [ -x "${PA_PREFIX}/bin/ld${PA_EXE}" ]; then
    pa_log "binutils already installed in ${PA_PREFIX}"
    exit 0
fi

src="${PA_SRC}/binutils-${BINUTILS_VERSION}"
bld="${PA_BUILD}/binutils"
rm -rf "${bld}"; mkdir -p "${bld}" "${PA_PREFIX}"

args=(
    "--prefix=${PA_PREFIX}"
    "--build=${triple}" "--host=${triple}" "--target=${triple}"
    --disable-nls
    --disable-werror
    --disable-multilib
    --disable-shared --enable-static
    --enable-lto --enable-plugins            # LTO plugin for ld/ar/nm
    --enable-deterministic-archives          # ar/ranlib produce reproducible .a
    --disable-gprofng
    --disable-gdb --disable-gdbserver --disable-sim --disable-readline
    --disable-libdecnumber
    --disable-install-libbfd --disable-install-libiberty   # no dev libs in the package
    --with-system-zlib=no                    # use the bundled zlib, statically
)
if [ "${PA_OS}" = linux ]; then
    args+=(--enable-new-dtags --enable-relro)
fi

(
    cd "${bld}"
    pa_run "${src}/configure" "${args[@]}"
    pa_run make -j"${PA_JOBS}" MAKEINFO=true
    pa_run make install-strip MAKEINFO=true
)
rm -rf "${bld}"
pa_log "binutils: $("${PA_PREFIX}/bin/ld${PA_EXE}" --version | head -1)"

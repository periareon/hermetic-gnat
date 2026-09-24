#!/usr/bin/env bash
# Configure, bootstrap and install GCC with the Ada front end into $PA_PREFIX.
#
# Native builds run GCC's standard 3-stage bootstrap: stage 1 is compiled by
# the bootstrap compiler, stage 2 by stage 1, stage 3 by stage 2, and stages
# 2 and 3 must be bit-identical.  The installed compiler is therefore built
# by itself; the bootstrap GNAT leaves no trace in the output.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${here}/lib/common.sh"
pa_init
pa_setup_path
triple="$(pa_triple)"
src="$(pa_gcc_src)"
bld="${PA_BUILD}/gcc"
libsubdir="$(pa_libsubdir)"
libexecsubdir="$(pa_libexecsubdir)"

if [ -x "${PA_PREFIX}/bin/gnatbind${PA_EXE}" ]; then
    pa_log "GCC already installed in ${PA_PREFIX}"
    exit 0
fi

pa_log "bootstrap compiler in use: $(command -v gcc) ($(gcc -dumpversion))"
command -v gnatmake >/dev/null || pa_die "gnatmake not found; run fetch-bootstrap.sh first"

repo_url="${PA_REPO_URL:-https://github.com/${GITHUB_REPOSITORY:-periareon/portable-ada}}"

args=(
    "--prefix=${PA_PREFIX}"
    "--build=${triple}" "--host=${triple}" "--target=${triple}"
    "--enable-languages=c,c++,ada"
    --enable-libada
    --enable-libstdcxx --enable-libstdcxx-threads
    --disable-libstdcxx-pch
    --disable-nls
    --disable-multilib
    --enable-lto
    --enable-checking=release
    --without-libiconv-prefix
    --without-zstd                    # never pick up a system libzstd
    --disable-libsanitizer            # tied to the build host's libc internals
    --disable-libvtv
    --disable-libitm
    --disable-libgomp
    --disable-libquadmath
    "--with-gmp=${PA_DEPS}" "--with-mpfr=${PA_DEPS}" "--with-mpc=${PA_DEPS}"
    "--with-pkgversion=portable-ada ${PA_RELEASE_VERSION}"
    "--with-bugurl=${repo_url}/issues"
    "--with-stage1-cflags=${GCC_STAGE1_CFLAGS}"
    "--with-boot-cflags=${GCC_BOOT_CFLAGS}"
)

case "${PA_OS}" in
    linux)
        args+=(
            "--with-isl=${PA_DEPS}"
            --enable-threads=posix
            --enable-default-pie
            --enable-linker-build-id
            # Search both /usr/lib/<triplet> (Debian family) and /usr/lib64
            # (RHEL family) for the system's crt files and libc.
            --enable-multiarch
            --with-gnu-as --with-gnu-ld
            "--with-build-time-tools=${PA_PREFIX}/${triple}/bin"
        )
        if [ "${PA_ARCH}" = aarch64 ]; then
            # Erratum workarounds distributions enable so that generated code
            # also runs on early Cortex-A53 parts (Raspberry Pi 3 era).
            args+=(--enable-fix-cortex-a53-835769 --enable-fix-cortex-a53-843419)
        fi
        ;;
    darwin)
        sdk="$(xcrun --show-sdk-path)"
        [ -d "${sdk}" ] || pa_die "no macOS SDK (xcrun --show-sdk-path)"
        clt_sdk=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
        xcode_sdk=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
        args+=(
            "--with-build-sysroot=${sdk}"
            # At run time: honour an explicit --sysroot / -isysroot (rules_ada
            # passes one) or the SDKROOT variable (handled by the driver
            # itself); otherwise fall back to whichever SDK the machine has.
            "--with-specs=%{!-sysroot=*:%{!isysroot*:--sysroot=%:if-exists-else(${clt_sdk} ${xcode_sdk})}}"
            --enable-darwin-at-rpath
        )
        ;;
    windows)
        MINGW_PREFIX="${PA_WORK}/mingw64"
        [ -f "${MINGW_PREFIX}/.done" ] || pa_die "mingw-w64 not built; run build-mingw.sh first"
        args+=(
            "--with-isl=${PA_DEPS}"
            --enable-threads=win32
            --disable-win32-registry
            --with-gnu-as --with-gnu-ld
            "--with-build-time-tools=${PA_PREFIX}/${triple}/bin"
            # Rewritten relative to the prefix at run time by GCC's own
            # relocation logic, like every other prefix-derived path.
            "--with-native-system-header-dir=${PA_PREFIX}/include"
        )
        # https://gcc.gnu.org/git/?p=gcc.git;a=commit;h=902c755930326cb4405672aa3ea13c35c653cbff
        export CPPFLAGS="-DCOM_NO_WINDOWS_H"
        ;;
esac

rm -rf "${bld}"; mkdir -p "${bld}" "${PA_PREFIX}"

if [ "${PA_OS}" = windows ]; then
    # The freshly built xgcc must see the mingw-w64 headers and CRT while the
    # target libraries are compiled, before anything is installed.
    mkdir -p "${bld}/${libsubdir}/include" "${bld}/gcc"
    cp -a "${MINGW_PREFIX}/include/." "${bld}/${libsubdir}/include/"
    cp -a "${MINGW_PREFIX}/lib/."     "${bld}/${libsubdir}/"
    cp -a "${bld}/lib"                "${bld}/gcc/lib"
fi

printf '%s\n' "${args[@]}" > "${PA_WORK}/gcc-configure-args.txt"

(
    cd "${bld}"
    pa_run "${src}/configure" "${args[@]}"
    pa_run make -j"${PA_JOBS}" MAKEINFO=true
    pa_run make -j1 install-strip MAKEINFO=true
)

case "${PA_OS}" in
    windows)
        # Runtime DLLs next to the executables, and the mingw-w64 SDK into the
        # installed tree where the driver's default search paths expect it.
        cp "${PA_PREFIX}/${libsubdir}/adalib/"*.dll "${PA_PREFIX}/bin/"
        mkdir -p "${PA_PREFIX}/${triple}/include"
        cp -a "${MINGW_PREFIX}/include/." "${PA_PREFIX}/${triple}/include/"
        cp -a "${MINGW_PREFIX}/lib/."     "${PA_PREFIX}/${libsubdir}/"
        ;;
    darwin)
        # Prefer Apple's classic linker when available (see the wrapper).
        install -m 0755 "${here}/darwin/ld-wrapper.sh" "${PA_PREFIX}/${libexecsubdir}/ld"
        ;;
esac

rm -rf "${bld}"
pa_log "installed: $("${PA_PREFIX}/bin/gcc${PA_EXE}" --version | head -1)"

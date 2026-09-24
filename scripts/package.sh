#!/usr/bin/env bash
# Turn the installed prefix into a release archive.
#
#   1. prune documentation, libtool files and build-host-specific headers
#   2. Linux: fold lib64/ into lib/ (rules_ada globs lib/**)
#   3. Linux/Windows: copy as/ld/nm into libexec so gcc never needs PATH
#   4. add license texts and a build manifest
#   5. macOS: make sure every Mach-O carries a valid (ad hoc) signature
#   6. write a deterministic <name>.tar.gz plus a .sha256 sidecar

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${here}/lib/common.sh"
pa_init
triple="$(pa_triple)"
libsubdir="$(pa_libsubdir)"
libexecsubdir="$(pa_libexecsubdir)"
name="$(pa_release_name)"

[ -x "${PA_PREFIX}/bin/gnatbind${PA_EXE}" ] || pa_die "nothing installed in ${PA_PREFIX}"
cd "${PA_PREFIX}"

# --- 1. prune -----------------------------------------------------------------
rm -rf share/info share/man share/locale
rm -rf "${libexecsubdir}/install-tools" "${libsubdir}/install-tools"
rm -rf "${libsubdir}/plugin/include"      # GCC plugin dev headers, ~10 MB
rm -f "bin/lto-dump${PA_EXE}"             # LTO bytecode inspector, ~45 MB, compiler-dev only
find . -name '*.la' -delete
rm -f lib/libbfd* lib/libopcodes* lib/libctf* lib/libsframe* lib/libgprofng* lib/libiberty.a
rm -f lib64/libbfd* lib64/libopcodes* lib64/libctf* lib64/libsframe* lib64/libgprofng* 2>/dev/null || true

# include-fixed holds copies of *build host* system headers that fixincludes
# decided to patch.  On a different machine they shadow the real headers and
# break C compilation, so only GCC's own limits.h survives.  On Windows the
# headers they fix are the mingw-w64 ones we ship, so they stay consistent.
if [ -d "${libsubdir}/include-fixed" ]; then
    case "${PA_OS}" in
        windows) rm -f "${libsubdir}/include-fixed/pthread.h" ;;
        *)
            find "${libsubdir}/include-fixed" -mindepth 1 \
                ! -name limits.h ! -name syslimits.h ! -name README -exec rm -rf {} +
            ;;
    esac
fi

# --- 2. lib64 -> lib (Linux) -----------------------------------------------------
if [ "${PA_OS}" = linux ] && [ -d lib64 ] && [ ! -L lib64 ]; then
    cp -a lib64/. lib/
    rm -rf lib64
    ln -s lib lib64     # the driver still searches <prefix>/lib64
fi

# --- 3. binutils reachable without PATH (Linux/Windows) --------------------------
if [ "${PA_OS}" != darwin ]; then
    for tool in as ld ld.bfd nm; do
        if [ -f "bin/${tool}${PA_EXE}" ]; then
            cp -f "bin/${tool}${PA_EXE}" "${libexecsubdir}/${tool}${PA_EXE}"
        fi
    done
fi

# --- 4. licenses + manifest -----------------------------------------------------
gcc_src="$(pa_gcc_src)"
add_licenses() {
    local pkg="$1" dir="$2"; shift 2
    [ -d "${dir}" ] || return 0
    mkdir -p "share/licenses/${pkg}"
    local f
    for f in "$@"; do
        [ -f "${dir}/${f}" ] && cp "${dir}/${f}" "share/licenses/${pkg}/"
    done
    return 0
}
add_licenses gcc      "${gcc_src}" COPYING COPYING3 COPYING.LIB COPYING3.LIB COPYING.RUNTIME
add_licenses gmp      "${PA_SRC}/gmp-${GMP_VERSION}"   COPYING COPYINGv2 COPYINGv3 COPYING.LESSERv3
add_licenses mpfr     "${PA_SRC}/mpfr-${MPFR_VERSION}" COPYING COPYING.LESSER
add_licenses mpc      "${PA_SRC}/mpc-${MPC_VERSION}"   COPYING.LESSER
add_licenses isl      "${PA_SRC}/isl-${ISL_VERSION}"   LICENSE
add_licenses binutils "${PA_SRC}/binutils-${BINUTILS_VERSION}" COPYING COPYING3 COPYING.LIB COPYING3.LIB
add_licenses mingw-w64 "${PA_SRC}/mingw-w64-v${MINGW_VERSION}" COPYING COPYING.MinGW-w64-runtime
mkdir -p share/licenses
cp "${PA_ROOT}/LICENSE" share/licenses/portable-ada.LICENSE

mkdir -p share/portable-ada
configure_args_json="$(python3 -c 'import json,sys; print(json.dumps([l.rstrip("\n") for l in open(sys.argv[1]) if l.strip()]))' "${PA_WORK}/gcc-configure-args.txt")"
gcc_source_url="${GCC_URL}"; gcc_source_sha="${GCC_SHA256}"
if [ "${PA_OS}" = darwin ]; then gcc_source_url="${GCC_DARWIN_URL}"; gcc_source_sha="${GCC_DARWIN_SHA256}"; fi
case "${PA_OS}" in
    linux)  floor_json="\"glibc_floor\": \"${LINUX_GLIBC_FLOOR}\"" ;;
    darwin) floor_json="\"macos_deployment_target\": \"${MACOS_DEPLOYMENT_TARGET}\"" ;;
    *)      floor_json="\"windows_min_version\": \"${MINGW_WINNT}\", \"msvcrt\": \"msvcrt\"" ;;
esac
cat > share/portable-ada/manifest.json <<EOF
{
  "name": "${name}",
  "gcc_version": "${GCC_VERSION}",
  "package_release": "${PKG_RELEASE}",
  "platform": "${PA_PLATFORM}",
  "target_triple": "${triple}",
  "build_prefix": "${PA_PREFIX}",
  "source_date_epoch": ${SOURCE_DATE_EPOCH},
  "portable_ada_commit": "${PA_GIT_SHA:-$(pa_git_sha)}",
  ${floor_json},
  "sources": {
    "gcc": {"url": "${gcc_source_url}", "sha256": "${gcc_source_sha}"},
    "gmp": {"url": "${GMP_URL}", "sha256": "${GMP_SHA256}"},
    "mpfr": {"url": "${MPFR_URL}", "sha256": "${MPFR_SHA256}"},
    "mpc": {"url": "${MPC_URL}", "sha256": "${MPC_SHA256}"},
    "isl": {"url": "${ISL_URL}", "sha256": "${ISL_SHA256}"},
    "binutils": {"url": "${BINUTILS_URL}", "sha256": "${BINUTILS_SHA256}"},
    "mingw-w64": {"url": "${MINGW_URL}", "sha256": "${MINGW_SHA256}"}
  },
  "configure_args": ${configure_args_json}
}
EOF
python3 -c 'import json,sys; json.load(open(sys.argv[1]))' share/portable-ada/manifest.json

# --- 5. macOS code signatures --------------------------------------------------
if [ "${PA_OS}" = darwin ]; then
    # The linker signs ad hoc; strip normally preserves that, but verify and
    # re-sign anything that lost its signature rather than ship a binary
    # macOS will refuse to exec.
    while IFS= read -r -d '' f; do
        case "$(od -An -N4 -tx1 "${f}" | tr -d ' \n')" in
            cffaedfe|cefaedfe|cafebabe|feedfacf|feedface) ;;   # Mach-O only
            *) continue ;;
        esac
        if ! codesign --verify "${f}" >/dev/null 2>&1; then
            pa_log "re-signing $(basename "${f}")"
            codesign --force --sign - "${f}"
        fi
    done < <(find bin libexec lib -type f \( -perm -u+x -o -name '*.dylib' \) -print0)
fi

# --- 6. archive -----------------------------------------------------------------
mkdir -p "${PA_OUT}"
out="${PA_OUT}/${name}.tar.gz"
python3 "${here}/mktar.py" --output "${out}" --root-name "${name}" --mtime "${SOURCE_DATE_EPOCH}" "${PA_PREFIX}"
(cd "${PA_OUT}" && printf '%s  %s\n' "$(pa_sha256 "${name}.tar.gz")" "${name}.tar.gz" > "${name}.tar.gz.sha256")
cp share/portable-ada/manifest.json "${PA_OUT}/${name}.manifest.json"
pa_log "wrote ${out} ($(du -h "${out}" | cut -f1))"
cat "${PA_OUT}/${name}.tar.gz.sha256" >&2

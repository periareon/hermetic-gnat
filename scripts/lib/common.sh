# shellcheck shell=bash
# Shared helpers for the portable-ada build scripts.  Source, do not execute.
#
# Every script that sources this gets:
#   PA_ROOT       repository root
#   PA_OS         linux | darwin | windows
#   PA_ARCH       x86_64 | aarch64
#   PA_PLATFORM   "${PA_OS}-${PA_ARCH}"
#   PA_OSNAME     archive name component: linux | darwin | windows64
#   PA_EXE        ".exe" on Windows, "" elsewhere
#   PA_WORK       scratch root (default: $PA_ROOT/work)
#   PA_DOWNLOADS  pinned source tarballs
#   PA_SRC        extracted sources
#   PA_BUILD      out-of-tree build directories
#   PA_DEPS       static gmp/mpfr/mpc/isl prefix
#   PA_BOOTSTRAP  bootstrap GNAT prefix (macOS/Windows)
#   PA_PREFIX     install prefix of the toolchain being built
#   PA_OUT        finished archives
#   PA_JOBS       parallelism
# plus all variables from versions.env.

set -euo pipefail

pa_log()  { printf '\033[1;34m[portable-ada]\033[0m %s\n' "$*" >&2; }
pa_warn() { printf '\033[1;33m[portable-ada] warning:\033[0m %s\n' "$*" >&2; }
pa_die()  { printf '\033[1;31m[portable-ada] error:\033[0m %s\n' "$*" >&2; exit 1; }

# Print the command, then run it.
pa_run() { printf '+ %s\n' "$*" >&2; "$@"; }

_pa_common_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PA_ROOT="$(cd "${_pa_common_dir}/../.." && pwd)"
export PA_ROOT

# ---------------------------------------------------------------------------
# versions.env
# ---------------------------------------------------------------------------
pa_load_versions() {
    [ -f "${PA_ROOT}/versions.env" ] || pa_die "versions.env not found at ${PA_ROOT}"
    set -a
    # shellcheck disable=SC1091
    . "${PA_ROOT}/versions.env"
    set +a
    PA_RELEASE_VERSION="${GCC_VERSION}-${PKG_RELEASE}"
    PA_RELEASE_TAG="gnat-${PA_RELEASE_VERSION}"
    export PA_RELEASE_VERSION PA_RELEASE_TAG
}

# ---------------------------------------------------------------------------
# Platform detection
# ---------------------------------------------------------------------------
pa_detect_platform() {
    local uname_s uname_m
    uname_s="$(uname -s)"
    uname_m="$(uname -m)"

    case "${uname_s}" in
        Linux)                        PA_OS=linux ;;
        Darwin)                       PA_OS=darwin ;;
        MINGW*|MSYS*|CYGWIN*|Windows_NT) PA_OS=windows ;;
        *) pa_die "unsupported operating system: ${uname_s}" ;;
    esac

    case "${uname_m}" in
        x86_64|amd64|AMD64)  PA_ARCH=x86_64 ;;
        aarch64|arm64|ARM64) PA_ARCH=aarch64 ;;
        *) pa_die "unsupported architecture: ${uname_m}" ;;
    esac

    # Allow an explicit override (used by the Windows-on-ARM emulation test).
    PA_OS="${PA_OS_OVERRIDE:-${PA_OS}}"
    PA_ARCH="${PA_ARCH_OVERRIDE:-${PA_ARCH}}"

    PA_PLATFORM="${PA_OS}-${PA_ARCH}"
    case "${PA_OS}" in
        windows) PA_OSNAME=windows64; PA_EXE=.exe ;;
        *)       PA_OSNAME="${PA_OS}"; PA_EXE="" ;;
    esac
    export PA_OS PA_ARCH PA_PLATFORM PA_OSNAME PA_EXE
}

# Name of the release archive (without extension) for the current platform.
pa_release_name() {
    printf 'gnat-%s-%s-%s' "${PA_ARCH}" "${PA_OSNAME}" "${PA_RELEASE_VERSION}"
}

# ---------------------------------------------------------------------------
# Directories
# ---------------------------------------------------------------------------
pa_setup_dirs() {
    PA_WORK="${PA_WORK:-${PA_ROOT}/work}"
    mkdir -p "${PA_WORK}"
    PA_WORK="$(cd "${PA_WORK}" && pwd)"
    PA_DOWNLOADS="${PA_DOWNLOADS:-${PA_WORK}/downloads}"
    PA_SRC="${PA_WORK}/src"
    PA_BUILD="${PA_WORK}/build"
    PA_DEPS="${PA_WORK}/deps"
    PA_BOOTSTRAP="${PA_WORK}/bootstrap"
    PA_PREFIX="${PA_WORK}/prefix"
    PA_OUT="${PA_OUT:-${PA_WORK}/out}"
    mkdir -p "${PA_DOWNLOADS}" "${PA_SRC}" "${PA_BUILD}" "${PA_DEPS}" "${PA_OUT}"
    export PA_WORK PA_DOWNLOADS PA_SRC PA_BUILD PA_DEPS PA_BOOTSTRAP PA_PREFIX PA_OUT

    if [ -z "${PA_JOBS:-}" ]; then
        PA_JOBS="$(pa_nproc)"
    fi
    export PA_JOBS
}

pa_nproc() {
    if command -v nproc >/dev/null 2>&1; then
        nproc
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.ncpu
    else
        echo 4
    fi
}

# The target triple is fixed once sources are unpacked (see fetch-sources.sh).
pa_triple() {
    if [ -n "${PA_TRIPLE:-}" ]; then
        printf '%s' "${PA_TRIPLE}"
    elif [ -f "${PA_WORK}/triple" ]; then
        cat "${PA_WORK}/triple"
    else
        pa_die "target triple not determined yet (run fetch-sources.sh first)"
    fi
}

# Absolute path of the unpacked GCC source tree.
pa_gcc_src() {
    [ -f "${PA_WORK}/gcc-srcdir" ] || pa_die "GCC sources not unpacked yet (run fetch-sources.sh first)"
    printf '%s/%s' "${PA_SRC}" "$(cat "${PA_WORK}/gcc-srcdir")"
}

# lib/gcc/<triple>/<version> relative to the prefix.
pa_libsubdir() { printf 'lib/gcc/%s/%s' "$(pa_triple)" "${GCC_VERSION}"; }
# libexec/gcc/<triple>/<version> relative to the prefix.
pa_libexecsubdir() { printf 'libexec/gcc/%s/%s' "$(pa_triple)" "${GCC_VERSION}"; }

# ---------------------------------------------------------------------------
# Hashing, downloading, extracting
# ---------------------------------------------------------------------------
pa_sha256() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "$1" | cut -d' ' -f1
    else
        python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$1"
    fi
}

pa_verify_sha256() {
    local file="$1" expected="$2" actual
    actual="$(pa_sha256 "${file}")"
    if [ "${actual}" != "${expected}" ]; then
        pa_die "checksum mismatch for ${file}
  expected: ${expected}
  actual:   ${actual}"
    fi
}

# pa_fetch URL SHA256 DEST
pa_fetch() {
    local url="$1" sha="$2" dest="$3"
    if [ -f "${dest}" ]; then
        if [ "$(pa_sha256 "${dest}")" = "${sha}" ]; then
            pa_log "cached: $(basename "${dest}")"
            return 0
        fi
        pa_warn "checksum mismatch on cached $(basename "${dest}"); re-downloading"
        rm -f "${dest}"
    fi
    pa_log "fetching ${url}"
    mkdir -p "$(dirname "${dest}")"
    # (no --retry-all-errors: the Debian 10 curl does not know it)
    curl --fail --location --silent --show-error \
         --retry 5 --retry-delay 5 --retry-connrefused \
         --output "${dest}.part" "${url}"
    mv "${dest}.part" "${dest}"
    pa_verify_sha256 "${dest}" "${sha}"
}

# pa_extract TARBALL DESTDIR [STRIP_COMPONENTS]
pa_extract() {
    local tarball="$1" dest="$2" strip="${3:-0}"
    mkdir -p "${dest}"
    pa_log "extracting $(basename "${tarball}") -> ${dest}"
    tar -xf "${tarball}" -C "${dest}" --strip-components="${strip}"
}

# ---------------------------------------------------------------------------
# Misc
# ---------------------------------------------------------------------------
# Source date for reproducible archives: the commit date if in git, else now.
pa_source_date_epoch() {
    if [ -n "${SOURCE_DATE_EPOCH:-}" ]; then
        printf '%s' "${SOURCE_DATE_EPOCH}"
    elif git -C "${PA_ROOT}" rev-parse --git-dir >/dev/null 2>&1; then
        git -C "${PA_ROOT}" log -1 --format=%ct 2>/dev/null || date +%s
    else
        date +%s
    fi
}

pa_git_sha() {
    git -C "${PA_ROOT}" rev-parse HEAD 2>/dev/null || echo unknown
}

# Put the bootstrap compiler (if any) first in PATH and keep the rest minimal.
pa_setup_path() {
    local base
    case "${PA_OS}" in
        darwin)  base="/usr/bin:/bin:/usr/sbin:/sbin" ;;
        windows) base="${PATH}" ;;   # msys2 / Git Bash environment as given
        *)       base="/usr/local/bin:/usr/bin:/bin" ;;
    esac
    if [ -d "${PA_BOOTSTRAP}/bin" ]; then
        PATH="${PA_BOOTSTRAP}/bin:${base}"
    else
        PATH="${base}"
    fi
    export PATH
}

pa_init() {
    pa_load_versions
    pa_detect_platform
    pa_setup_dirs

    SOURCE_DATE_EPOCH="$(pa_source_date_epoch)"
    export SOURCE_DATE_EPOCH

    if [ "${PA_OS}" = darwin ]; then
        # Read by GCC's own driver (bootstrap and shipped compiler alike) and
        # by Apple's tools: everything built targets at least this macOS.
        export MACOSX_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET}"
    fi
}

#!/usr/bin/env bash
# Verify an unpacked toolchain: relocatability, a working Ada/C compiler and
# runtime, and the portability guarantees promised in the README.
#
#   scripts/check.sh <toolchain-dir>
#
# The directory should be somewhere unrelated to where the toolchain was
# built (scripts/ci/test-archive.sh extracts into a fresh temporary
# directory).  Needs bash, tar-less: only the toolchain itself plus the
# platform's system linker inputs (libc6-dev / Xcode CLT / nothing on
# Windows).  Runs under Git Bash on Windows as well as msys2.
#
# Checks:
#   1. version, self-location of gnat1/libgcc/adalib (no PATH, relative argv0)
#   2. every program under test/ compiled two ways (the way rules_ada does
#      it, and with gnatmake) and its output compared
#   3. dynamic dependencies of every executable against a per-OS allowlist,
#      the glibc symbol-version ceiling (Linux), the deployment target and
#      code signature (macOS), DLL imports (Windows)
#   4. no build-prefix leakage in the driver's search paths

set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${here}/lib/common.sh"
set +e   # common.sh enables -e; this script collects failures instead
pa_load_versions
pa_detect_platform

[ $# -eq 1 ] || pa_die "usage: $0 <toolchain-dir>"
# Physical path: GCC reports resolved paths, and on macOS /var is a symlink
# to /private/var.
TC="$(cd "$1" && pwd -P)" || pa_die "no such directory: $1"
TESTS="${PA_ROOT}/test"
EXE="${PA_EXE}"

failures=0
pass() { printf '  \033[32mok\033[0m   %s\n' "$*"; }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$*"; failures=$((failures + 1)); }
section() { printf '\n\033[1m== %s ==\033[0m\n' "$*"; }

# Windows tools print C:/... paths; compare in that form.
norm() {
    if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}
TCN="$(norm "${TC}")"

# version_le A B : true if A <= B (dotted numeric versions)
version_le() {
    local IFS=. a b i
    read -r -a a <<< "$1"; read -r -a b <<< "$2"
    for ((i = 0; i < ${#a[@]} || i < ${#b[@]}; i++)); do
        local x="${a[i]:-0}" y="${b[i]:-0}"
        if ((10#$x < 10#$y)); then return 0; fi
        if ((10#$x > 10#$y)); then return 1; fi
    done
    return 0
}

magic() { od -An -N4 -tx1 "$1" 2>/dev/null | tr -d ' \n'; }
is_elf()   { [ "$(magic "$1")" = 7f454c46 ]; }
is_macho() { case "$(magic "$1")" in cffaedfe|cefaedfe|cafebabe|feedfacf|feedface) return 0 ;; *) return 1 ;; esac; }
is_pe()    { case "$(magic "$1")" in 4d5a*) return 0 ;; *) return 1 ;; esac; }

manifest="${TC}/share/portable-ada/manifest.json"
manifest_get() { grep -o "\"$1\": *\"[^\"]*\"" "${manifest}" 2>/dev/null | head -1 | sed 's/.*: *"\(.*\)"/\1/'; }

# Architecture of the archive, not of the host (Windows-on-ARM runs the
# x86_64 toolchain under emulation).
ARCH="$(manifest_get platform | cut -d- -f2)"
ARCH="${ARCH:-${PA_ARCH}}"

GCC="${TC}/bin/gcc${EXE}"
GNATBIND="${TC}/bin/gnatbind${EXE}"
GNATMAKE="${TC}/bin/gnatmake${EXE}"

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

# ---------------------------------------------------------------------------
section "toolchain at ${TC}"
# ---------------------------------------------------------------------------
[ -x "${GCC}" ]      || pa_die "missing ${GCC}"
[ -x "${GNATBIND}" ] || pa_die "missing ${GNATBIND}"
ver_line="$("${GCC}" --version 2>&1 | head -1)"
echo "  ${ver_line}"
if [ -f "${manifest}" ]; then
    echo "  manifest: $(manifest_get name) ($(manifest_get platform), $(manifest_get target_triple))"
fi
case "${ver_line}" in
    *"${GCC_VERSION}"*) pass "gcc reports ${GCC_VERSION}" ;;
    *) fail "gcc version line does not mention ${GCC_VERSION}: ${ver_line}" ;;
esac

triple="$("${GCC}" -dumpmachine)"
echo "  target: ${triple}"

gnat1="$("${GCC}" -print-prog-name=gnat1)"
case "$(norm "${gnat1}")" in
    "${TCN}"/*) [ -f "${gnat1}" ] && pass "gnat1 resolved inside the toolchain" || fail "gnat1 path does not exist: ${gnat1}" ;;
    *) fail "gnat1 resolved outside the toolchain: ${gnat1}" ;;
esac

libgcc="$("${GCC}" -print-libgcc-file-name)"
case "$(norm "${libgcc}")" in
    "${TCN}"/*) [ -f "${libgcc}" ] && pass "libgcc.a resolved inside the toolchain" || fail "libgcc.a missing: ${libgcc}" ;;
    *) fail "libgcc.a resolved outside the toolchain: ${libgcc}" ;;
esac
GCCLIB="$(dirname "${libgcc}")"
LIBEXEC="$(dirname "${gnat1}")"

ADALIB="$(find "${TC}/lib/gcc" -type d -name adalib | head -1)"
ADAINCLUDE="$(find "${TC}/lib/gcc" -type d -name adainclude | head -1)"
[ -n "${ADALIB}" ] && [ -f "${ADALIB}/libgnat.a" ] && [ -f "${ADALIB}/libgnarl.a" ] \
    && pass "adalib with static libgnat/libgnarl" || fail "adalib/libgnat.a/libgnarl.a not found under lib/gcc"
[ -n "${ADAINCLUDE}" ] && [ -f "${ADAINCLUDE}/ada.ads" ] && pass "adainclude present" || fail "adainclude missing"
[ -d "${TC}/lib64" ] && [ ! -L "${TC}/lib64" ] && fail "lib64/ is a real directory (should be folded into lib/)"

[ -x "${TC}/bin/gcov${EXE}" ] && pass "bin/gcov present" || fail "bin/gcov missing (rules_ada uses it)"
if [ "${PA_OS}" = darwin ]; then
    # No binutils on macOS; rules_ada falls back to the CC toolchain's ar.
    [ -x "${TC}/bin/ar" ] && pass "bin/ar present" || echo "  --   bin/ar not bundled (Apple's ar is used)"
else
    [ -x "${TC}/bin/ar${EXE}" ] && pass "bin/ar present" || fail "bin/ar missing (rules_ada uses it)"
fi

# rules_ada links these three archives by path.  Order matters for GNU ld:
# libgnarl (tasking) pulls symbols from libgnat, so it must come first, which
# is also the order gnatlink uses (-lgnarl -lgnat).  On glibc < 2.34 the
# thread/rt/dl libraries are separate and must be named explicitly.
# (bash 3.2 on macOS cannot expand an empty array under set -u, hence the
# scalar string for the extras.)
link_libs=("${ADALIB}/libgnarl.a" "${ADALIB}/libgnat.a" "${GCCLIB}/libgcc.a")
extra_link=""
case "${PA_OS}" in
    linux) extra_link="-lpthread -ldl -lrt -lm" ;;
esac

# ---------------------------------------------------------------------------
section "compile and run test programs"
# ---------------------------------------------------------------------------
run_and_compare() {   # exe expected label
    local out
    out="$("$1" 2>&1 | tr -d '\r')"
    if [ "${out}" = "$(tr -d '\r' < "$2")" ]; then
        pass "$3"
    else
        fail "$3: unexpected output"
        printf '%s\n' "${out}" | sed 's/^/        | /'
    fi
}

for dir in "${TESTS}"/*/; do
    name="$(basename "${dir}")"
    expected="${dir}/expected.txt"

    # (a) the rules_ada way: separate compiles, gnatbind, compile binder
    #     output, link with explicit archives.
    w="${tmp}/manual/${name}"; mkdir -p "${w}"
    (
        set -e
        cd "${w}"
        objs=()
        for c in "${dir}"/*.c; do
            [ -f "${c}" ] || continue
            "${GCC}" -c -O2 "${c}" -o "$(basename "${c%.c}").o"
            objs+=("$(basename "${c%.c}").o")
        done
        for src in "${dir}"/*.adb; do
            unit="$(basename "${src%.adb}")"
            "${GCC}" -c -O2 -I"${dir}" "${src}" -o "${unit}.o"
            objs+=("${unit}.o")
        done
        "${GNATBIND}" -x -I. "${name}.ali" -o "b~${name}.adb"
        "${GCC}" -c "b~${name}.adb" -o "b~${name}.o"
        # shellcheck disable=SC2086
        "${GCC}" "b~${name}.o" "${objs[@]}" "${link_libs[@]}" ${extra_link} -o "${name}${EXE}"
    ) > "${w}/build.log" 2>&1
    if [ $? -eq 0 ]; then
        run_and_compare "${w}/${name}${EXE}" "${expected}" "${name} (gcc/gnatbind/gcc)"
    else
        fail "${name} (gcc/gnatbind/gcc): build failed"; sed 's/^/        | /' "${w}/build.log"
    fi

    # (b) gnatmake, which exercises gnatlink and the binder's option list.
    w="${tmp}/gnatmake/${name}"; mkdir -p "${w}"
    (
        set -e
        cd "${w}"
        largs=()
        for c in "${dir}"/*.c; do
            [ -f "${c}" ] || continue
            "${GCC}" -c -O2 "${c}" -o "$(basename "${c%.c}").o"
            largs+=("$(basename "${c%.c}").o")
        done
        if [ ${#largs[@]} -gt 0 ]; then
            "${GNATMAKE}" -q -O2 -I"${dir}" -o "${name}${EXE}" "${name}" -largs "${largs[@]}"
        else
            "${GNATMAKE}" -q -O2 -I"${dir}" -o "${name}${EXE}" "${name}"
        fi
    ) > "${w}/build.log" 2>&1
    if [ $? -eq 0 ]; then
        run_and_compare "${w}/${name}${EXE}" "${expected}" "${name} (gnatmake)"
    else
        fail "${name} (gnatmake): build failed"; sed 's/^/        | /' "${w}/build.log"
    fi
done

# ---------------------------------------------------------------------------
section "relocation and PATH independence"
# ---------------------------------------------------------------------------
# Relative argv[0] from a sibling directory, the way Bazel runs tools.
w="${tmp}/relative"; mkdir -p "${w}"
( cd "$(dirname "${TC}")" && "$(basename "${TC}")/bin/gcc${EXE}" -c "${TESTS}/hello/hello.adb" -I"${TESTS}/hello" -o "${w}/hello.o" ) > "${w}/log" 2>&1 \
    && pass "compile via relative path" || { fail "compile via relative path"; sed 's/^/        | /' "${w}/log"; }

# No PATH at all: the assembler and linker must be found inside the toolchain.
# macOS necessarily uses Apple's as/ld from /usr/bin, so only require that
# nothing *else* is needed there.
w="${tmp}/nopath"; mkdir -p "${w}"
case "${PA_OS}" in
    darwin) nopath_env=(env PATH=/usr/bin:/bin) ;;
    *)      nopath_env=(env PATH=/nonexistent) ;;
esac
(
    set -e
    cd "${w}"
    "${nopath_env[@]}" "${GCC}" -c "${TESTS}/hello/greeter.adb" -o greeter.o
    "${nopath_env[@]}" "${GCC}" -c -I"${TESTS}/hello" "${TESTS}/hello/hello.adb" -o hello.o
    "${nopath_env[@]}" "${GNATBIND}" -x -I. hello.ali -o "b~hello.adb"
    "${nopath_env[@]}" "${GCC}" -c "b~hello.adb" -o "b~hello.o"
    # shellcheck disable=SC2086
    "${nopath_env[@]}" "${GCC}" "b~hello.o" hello.o greeter.o "${link_libs[@]}" ${extra_link} -o "hello${EXE}"
) > "${w}/log" 2>&1
if [ $? -eq 0 ]; then
    run_and_compare "${w}/hello${EXE}" "${TESTS}/hello/expected.txt" "build and link with PATH=${nopath_env[1]#PATH=}"
else
    fail "build with PATH=${nopath_env[1]#PATH=}"; sed 's/^/        | /' "${w}/log"
fi

if [ -f "${manifest}" ] && [ "${PA_OS}" != windows ]; then
    build_prefix="$(manifest_get build_prefix)"
    if [ -n "${build_prefix}" ] && [ "${build_prefix}" != "${TC}" ]; then
        if "${GCC}" -print-search-dirs | grep -qF "${build_prefix}"; then
            fail "gcc -print-search-dirs still mentions the build prefix ${build_prefix}"
        else
            pass "no build-prefix leakage in search dirs"
        fi
    fi
fi

# ---------------------------------------------------------------------------
section "dynamic dependencies of shipped executables"
# ---------------------------------------------------------------------------
# Only real executables matter; wrappers, .la leftovers and the like are skipped.
candidates=()
while IFS= read -r f; do candidates+=("${f}"); done < <(
    find "${TC}/bin" "${LIBEXEC}" -maxdepth 1 -type f \( -perm -u+x -o -name '*.dll' -o -name '*.exe' \) 2>/dev/null | sort
)

case "${PA_OS}" in
linux)
    READELF="${TC}/bin/readelf"
    [ -x "${READELF}" ] || READELF=readelf
    case "${ARCH}" in
        x86_64)  loader='ld-linux-x86-64\.so\.2' ;;
        aarch64) loader='ld-linux-aarch64\.so\.1' ;;
        *)       loader='ld-linux.*' ;;
    esac
    allowed="^(libc\.so\.6|libm\.so\.6|libdl\.so\.2|libpthread\.so\.0|librt\.so\.1|${loader})$"
    bad_needed=0; bad_glibc=0; worst="0"; checked=0
    for f in "${candidates[@]}"; do
        is_elf "${f}" || continue
        checked=$((checked + 1))
        while IFS= read -r lib; do
            [ -z "${lib}" ] && continue
            if ! [[ "${lib}" =~ ${allowed} ]]; then
                echo "        $(basename "${f}") needs ${lib}"; bad_needed=$((bad_needed + 1))
            fi
        done < <("${READELF}" -d "${f}" | awk '/\(NEEDED\)/ {gsub(/[][]/, "", $NF); print $NF}')
        max="$("${READELF}" -W --dyn-syms "${f}" | grep -o 'GLIBC_[0-9.]*' | sed 's/GLIBC_//' \
               | sort -u -t. -k1,1n -k2,2n -k3,3n | tail -1)"
        [ -z "${max}" ] && max=0
        if ! version_le "${max}" "${LINUX_GLIBC_FLOOR}"; then
            echo "        $(basename "${f}") requires GLIBC_${max}"; bad_glibc=$((bad_glibc + 1))
        fi
        version_le "${worst}" "${max}" && worst="${max}"
        if "${READELF}" -W --dyn-syms "${f}" | grep -q GLIBC_PRIVATE; then
            echo "        $(basename "${f}") uses GLIBC_PRIVATE"; bad_glibc=$((bad_glibc + 1))
        fi
    done
    [ "${checked}" -gt 0 ] || fail "no ELF executables found to inspect"
    [ "${bad_needed}" -eq 0 ] && pass "${checked} executables link only libc/libm/libdl/libpthread/librt" || fail "${bad_needed} unexpected shared-library dependencies"
    [ "${bad_glibc}" -eq 0 ] && pass "highest glibc symbol version ${worst} <= ${LINUX_GLIBC_FLOOR}" || fail "glibc floor ${LINUX_GLIBC_FLOOR} exceeded (highest ${worst})"
    ;;
darwin)
    bad_dep=0; bad_min=0; bad_sig=0; checked=0; worst="0"
    for f in "${candidates[@]}"; do
        is_macho "${f}" || continue
        checked=$((checked + 1))
        while IFS= read -r dep; do
            case "${dep}" in
                /usr/lib/*|/System/Library/*|@rpath/*|"${TC}"/*) ;;
                *) echo "        $(basename "${f}") loads ${dep}"; bad_dep=$((bad_dep + 1)) ;;
            esac
        done < <(otool -L "${f}" | tail -n +2 | awk '{print $1}')
        minos="$(otool -l "${f}" | awk '$1=="minos"{print $2; exit} /LC_VERSION_MIN_MACOSX/{m=1} m&&$1=="version"{print $2; exit}')"
        if [ -n "${minos}" ]; then
            if ! version_le "${minos}" "${MACOS_DEPLOYMENT_TARGET}"; then
                echo "        $(basename "${f}") minos ${minos}"; bad_min=$((bad_min + 1))
            fi
            version_le "${worst}" "${minos}" && worst="${minos}"
        fi
        if ! codesign --verify "${f}" >/dev/null 2>&1; then
            echo "        $(basename "${f}") has no valid code signature"; bad_sig=$((bad_sig + 1))
        fi
    done
    [ "${checked}" -gt 0 ] || fail "no Mach-O executables found to inspect"
    [ "${bad_dep}" -eq 0 ] && pass "${checked} executables load only system libraries" || fail "${bad_dep} unexpected dylib dependencies"
    [ "${bad_min}" -eq 0 ] && pass "highest minimum macOS ${worst} <= ${MACOS_DEPLOYMENT_TARGET}" || fail "deployment target ${MACOS_DEPLOYMENT_TARGET} exceeded (highest ${worst})"
    [ "${bad_sig}" -eq 0 ] && pass "all executables carry valid signatures" || fail "${bad_sig} executables fail codesign --verify"
    ;;
windows)
    OBJDUMP="${TC}/bin/objdump.exe"
    system_dlls='^(kernel32|user32|advapi32|shell32|msvcrt|ws2_32|wsock32|ole32|oleaut32|bcrypt|ntdll|iphlpapi|dbghelp|psapi|shlwapi|version|userenv|rpcrt4|crypt32|api-ms-win-.*|ucrtbase)\.dll$'
    shipped="$(cd "${TC}/bin" && ls -- *.dll 2>/dev/null | tr '[:upper:]' '[:lower:]' | tr '\n' ' ')"
    bad=0; checked=0
    for f in "${candidates[@]}"; do
        is_pe "${f}" || continue
        checked=$((checked + 1))
        while IFS= read -r dll; do
            dll="$(printf '%s' "${dll}" | tr '[:upper:]' '[:lower:]' | tr -d '\r')"
            [ -z "${dll}" ] && continue
            if [[ "${dll}" =~ ${system_dlls} ]]; then continue; fi
            case " ${shipped} " in *" ${dll} "*) continue ;; esac
            echo "        $(basename "${f}") imports ${dll}"; bad=$((bad + 1))
        done < <("${OBJDUMP}" -p "${f}" | awk '/DLL Name:/ {print $3}')
    done
    [ "${checked}" -gt 0 ] || fail "no PE executables found to inspect"
    [ "${bad}" -eq 0 ] && pass "${checked} executables import only Windows system DLLs or bundled ones" || fail "${bad} imports of DLLs that are neither system nor bundled"
    ;;
esac

# ---------------------------------------------------------------------------
section "result"
# ---------------------------------------------------------------------------
if [ "${failures}" -eq 0 ]; then
    echo "  all checks passed"
    exit 0
fi
echo "  ${failures} check(s) failed"
exit 1

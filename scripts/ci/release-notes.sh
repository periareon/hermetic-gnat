#!/usr/bin/env bash
# Generate the GitHub release notes (Markdown) for a hermetic-gnat release:
# every GCC version in versions/, every platform.
#
#   scripts/ci/release-notes.sh <dist-dir> <tag>

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${here}/../lib/common.sh"

dist="$1"; tag="$2"
repo="${GITHUB_REPOSITORY:-periareon/hermetic-gnat}"
server="${GITHUB_SERVER_URL:-https://github.com}"
versions="$(pa_versions_available | tr '\n' ' ')"

# Shared pins (identical for every version).
pa_load_versions

runs_on() {
    case "$1" in
        *-linux-*)     echo "glibc >= ${LINUX_GLIBC_FLOOR} (RHEL 8, Debian 10, Ubuntu 18.10 and newer)" ;;
        *-darwin-*)    echo "macOS ${MACOS_DEPLOYMENT_TARGET}+ with Xcode or Command Line Tools" ;;
        *-windows64-*) echo "Windows 7+ x64; Windows 11 on ARM via x64 emulation" ;;
    esac
}

cat <<EOF
hermetic-gnat ${tag}: relocatable, self-contained GNAT toolchains (GCC with the Ada front end) for [rules_ada](https://github.com/periareon/rules_ada).

GCC versions in this release: ${versions}. All archives were built by the same recipe at commit \`${GITHUB_SHA:-unknown}\` and verified on machines other than the ones that built them.

EOF

for gcc in ${versions}; do
    cat <<EOF
### GCC ${gcc}

| Archive | Runs on | SHA-256 |
|---|---|---|
EOF
    for f in "${dist}"/gnat-*-"${gcc}".tar.gz; do
        name="$(basename "${f}")"
        printf '| `%s` | %s | `%s` |\n' "${name}" "$(runs_on "${name}")" "$(cut -d' ' -f1 "${f}.sha256")"
    done
    (
        export PA_GCC_VERSION="${gcc}"
        # shellcheck disable=SC1091
        . "${here}/../lib/common.sh"; pa_load_versions
        cat <<EOF

Sources: GCC ${GCC_VERSION} \`${GCC_SHA256}\`; Darwin branch ${GCC_DARWIN_TAG} \`${GCC_DARWIN_SHA256}\`. Bootstrapped from GNAT-FSF-builds ${BOOTSTRAP_GNAT_VERSION} (macOS, Windows) and Debian 10's gnat-8 (Linux, stage 1 of a 3-stage bootstrap only).

EOF
    )
done

cat <<EOF
### rules_ada

Generated \`ada/private/versions.bzl\` content for this release (\`bazel run //tools/update_versions\` in rules_ada produces the same):

\`\`\`python
$(python3 "${here}/../../tools/rules_ada_versions.py" --repo "${repo}" --server "${server}" --tag "${tag}" "${dist}")
\`\`\`

### What is inside every archive

* \`gcc\`, \`gnat1\`, \`gnatbind\`, \`gnatmake\`, \`gnatlink\`, \`gcov\`, ..., with the C and C++ front ends
* static \`libgnat.a\` / \`libgnarl.a\`, \`adainclude\`, \`libgcc.a\`, \`libstdc++\`, \`libatomic\`
* Linux/Windows: GNU binutils ${BINUTILS_VERSION}, also copied into \`libexec/gcc/<triple>/<version>/\` so the driver never needs \`PATH\`
* Windows: mingw-w64 ${MINGW_VERSION} headers and CRT (msvcrt, win32 threads)
* \`share/hermetic-gnat/manifest.json\`: every source URL, checksum and configure flag used
* \`share/licenses/\`: license texts of everything included

Shared pins: binutils ${BINUTILS_VERSION} \`${BINUTILS_SHA256}\`; GMP ${GMP_VERSION} \`${GMP_SHA256}\`; MPFR ${MPFR_VERSION} \`${MPFR_SHA256}\`; MPC ${MPC_VERSION} \`${MPC_SHA256}\`; ISL ${ISL_VERSION} \`${ISL_SHA256}\`; mingw-w64 ${MINGW_VERSION} \`${MINGW_SHA256}\`.
EOF

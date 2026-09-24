#!/usr/bin/env bash
# Generate the GitHub release notes (Markdown) for a set of built archives.
#
#   scripts/ci/release-notes.sh <dist-dir> <tag>

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "${here}/../lib/common.sh"
pa_load_versions

dist="$1"; tag="$2"
repo="${GITHUB_REPOSITORY:-OWNER/portable-ada}"
server="${GITHUB_SERVER_URL:-https://github.com}"

cat <<EOF
GNAT (GCC ${GCC_VERSION} with the Ada front end), package release ${PKG_RELEASE}.
Relocatable, self-contained archives for use with [rules_ada](https://github.com/periareon/rules_ada).

| Archive | Runs on | SHA-256 |
|---|---|---|
EOF
for f in "${dist}"/gnat-*.tar.gz; do
    name="$(basename "${f}")"
    sha="$(cut -d' ' -f1 "${f}.sha256")"
    case "${name}" in
        *-linux-*)     runs="glibc >= ${LINUX_GLIBC_FLOOR} (RHEL 8, Debian 10, Ubuntu 18.10 and newer)" ;;
        *-darwin-*)    runs="macOS ${MACOS_DEPLOYMENT_TARGET}+ with Xcode or Command Line Tools" ;;
        *-windows64-*) runs="Windows 7+ x64; Windows 11 on ARM via x64 emulation" ;;
        *)             runs="" ;;
    esac
    printf '| `%s` | %s | `%s` |\n' "${name}" "${runs}" "${sha}"
done

cat <<EOF

### rules_ada

Add this entry to \`GNAT_VERSIONS\` in \`ada/private/versions.bzl\` (or point
\`tools/update_versions\` at \`${repo}\`):

\`\`\`python
$(python3 "${here}/../../tools/rules_ada_versions.py" --repo "${repo}" --server "${server}" "${dist}")
\`\`\`

### What is inside

* GCC ${GCC_VERSION} (\`gcc\`, \`gnat1\`, \`gnatbind\`, \`gnatmake\`, \`gnatlink\`, \`gcov\`, ...), C and C++ front ends included
* static \`libgnat.a\` / \`libgnarl.a\`, \`adainclude\`, \`libgcc.a\`, \`libstdc++\`, \`libatomic\`
* Linux/Windows: GNU binutils ${BINUTILS_VERSION}, also copied into \`libexec/gcc/<triple>/<version>/\` so the driver never needs \`PATH\`
* Windows: mingw-w64 ${MINGW_VERSION} headers and CRT (msvcrt, win32 threads)
* \`share/portable-ada/manifest.json\`: every source URL, checksum and configure flag used
* \`share/licenses/\`: license texts of everything included

### Pinned sources

| Component | Version | SHA-256 |
|---|---|---|
| GCC | ${GCC_VERSION} | \`${GCC_SHA256}\` |
| GCC (Darwin branch) | ${GCC_DARWIN_TAG} | \`${GCC_DARWIN_SHA256}\` |
| binutils | ${BINUTILS_VERSION} | \`${BINUTILS_SHA256}\` |
| GMP | ${GMP_VERSION} | \`${GMP_SHA256}\` |
| MPFR | ${MPFR_VERSION} | \`${MPFR_SHA256}\` |
| MPC | ${MPC_VERSION} | \`${MPC_SHA256}\` |
| ISL | ${ISL_VERSION} | \`${ISL_SHA256}\` |
| mingw-w64 | ${MINGW_VERSION} | \`${MINGW_SHA256}\` |

Bootstrapped from GNAT-FSF-builds ${BOOTSTRAP_GNAT_VERSION} (macOS, Windows) and Debian 10's gnat-8 (Linux, stage 1 of a 3-stage bootstrap only).
Built by [${repo}](${server}/${repo}) at commit \`${GITHUB_SHA:-unknown}\` from tag \`${tag}\`.
EOF

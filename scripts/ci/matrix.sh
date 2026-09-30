#!/usr/bin/env bash
# Emit the GitHub Actions job matrices as JSON.
#
#   scripts/ci/matrix.sh [platforms] [gcc-versions]
#
#   platforms     space-separated subset of
#                 linux-x86_64 linux-aarch64 darwin-x86_64 darwin-aarch64 windows-x86_64
#                 (empty = all)
#   gcc-versions  space-separated subset of versions/<gcc>.env, or "all"
#                 (empty = versions/DEFAULT)
#
# Prints key=value lines for $GITHUB_OUTPUT: linux, darwin, windows (build
# jobs) and test_native, test_container (verification jobs).  Every entry
# carries "gcc" and "artifact" (gnat-<arch>-<os>-<gcc>).  Empty selections
# are emitted as [] and the jobs skip themselves.

set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

all_platforms="linux-x86_64 linux-aarch64 darwin-x86_64 darwin-aarch64 windows-x86_64"
platforms="${1:-}"
[ -n "${platforms}" ] || platforms="${all_platforms}"
for p in ${platforms}; do
    case " ${all_platforms} " in *" ${p} "*) ;; *) echo "unknown platform: ${p}" >&2; exit 1 ;; esac
done

all_versions="$("${here}/../env.sh" --list | tr '\n' ' ')"
case "${2:-}" in
    "")  versions="$(tr -d '[:space:]' < "${here}/../../versions/DEFAULT")" ;;
    all) versions="${all_versions}" ;;
    *)   versions="$2" ;;
esac
for v in ${versions}; do
    case " ${all_versions} " in *" ${v} "*) ;; *) echo "unknown GCC version: ${v} (have: ${all_versions})" >&2; exit 1 ;; esac
done

want() { case " ${platforms} " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

linux='[]'; darwin='[]'; windows='[]'; native='[]'; container='[]'

# add VAR JSON : append an object, injecting the gcc version and artifact name.
add() {
    local cur="${!1}" gcc="$2" arch_os="$3" json="$4"
    printf -v "$1" '%s' "$(jq -c --argjson e "${json}" --arg gcc "${gcc}" --arg art "gnat-${arch_os}-${gcc}" \
        '. + [$e + {gcc: $gcc, artifact: $art}]' <<< "${cur}")"
}

# Debian 10 is end-of-life: its packages now live on archive.debian.org.
# The security repo is required too: the image's libc6 comes from it, and
# libc6-dev must match that exact version.
deb10_setup="{ echo 'deb http://archive.debian.org/debian buster main'; echo 'deb http://archive.debian.org/debian-security buster/updates main'; } > /etc/apt/sources.list && apt-get -o Acquire::Check-Valid-Until=false update -qq && apt-get install -y -qq --no-install-recommends libc6-dev"

for gcc in ${versions}; do
    if want linux-x86_64; then
        add linux "${gcc}" x86_64-linux '{"arch":"x86_64","runner":"ubuntu-24.04"}'
        # Newer host than the build container, and the glibc floor itself.
        add native    "${gcc}" x86_64-linux '{"platform":"linux-x86_64","runner":"ubuntu-22.04","label":"ubuntu-22.04 host"}'
        add container "${gcc}" x86_64-linux '{"platform":"linux-x86_64","runner":"ubuntu-24.04","image":"debian:10","setup":"'"${deb10_setup}"'","label":"debian 10 (glibc 2.28)"}'
        add container "${gcc}" x86_64-linux '{"platform":"linux-x86_64","runner":"ubuntu-24.04","image":"almalinux:8","setup":"dnf install -y -q glibc-devel","label":"almalinux 8 (glibc 2.28)"}'
    fi
    if want linux-aarch64; then
        add linux "${gcc}" aarch64-linux '{"arch":"aarch64","runner":"ubuntu-24.04-arm"}'
        add native    "${gcc}" aarch64-linux '{"platform":"linux-aarch64","runner":"ubuntu-22.04-arm","label":"ubuntu-22.04-arm host"}'
        add container "${gcc}" aarch64-linux '{"platform":"linux-aarch64","runner":"ubuntu-24.04-arm","image":"debian:10","setup":"'"${deb10_setup}"'","label":"debian 10 arm64 (glibc 2.28)"}'
    fi
    if want darwin-x86_64; then
        add darwin "${gcc}" x86_64-darwin '{"arch":"x86_64","runner":"macos-15-intel"}'
        add native "${gcc}" x86_64-darwin '{"platform":"darwin-x86_64","runner":"macos-26-intel","label":"macos-26-intel host"}'
    fi
    if want darwin-aarch64; then
        add darwin "${gcc}" aarch64-darwin '{"arch":"aarch64","runner":"macos-15"}'
        add native "${gcc}" aarch64-darwin '{"platform":"darwin-aarch64","runner":"macos-26","label":"macos-26 host"}'
    fi
    if want windows-x86_64; then
        add windows "${gcc}" x86_64-windows64 '{"arch":"x86_64","runner":"windows-2025"}'
        # Git Bash only: proves no msys2 runtime is needed.
        add native "${gcc}" x86_64-windows64 '{"platform":"windows-x86_64","runner":"windows-2022","label":"windows-2022 host (Git Bash)","experimental":false}'
        # No native GNAT exists for Windows on ARM (see README); this is the
        # supported route: the x86_64 toolchain under Windows' x64 emulation.
        add native "${gcc}" x86_64-windows64 '{"platform":"windows-x86_64","runner":"windows-11-arm","label":"windows-11-arm host (x64 emulation)","experimental":true}'
    fi
done

printf 'versions=%s\n' "$(printf '%s' "${versions}" | tr -s ' ' | sed 's/ *$//')"
printf 'linux=%s\n' "${linux}"
printf 'darwin=%s\n' "${darwin}"
printf 'windows=%s\n' "${windows}"
printf 'test_native=%s\n' "${native}"
printf 'test_container=%s\n' "${container}"

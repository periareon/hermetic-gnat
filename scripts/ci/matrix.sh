#!/usr/bin/env bash
# Emit the GitHub Actions job matrices as JSON, optionally restricted to a
# space-separated list of platforms.
#
#   scripts/ci/matrix.sh [platforms] > $GITHUB_OUTPUT-style key=value lines
#
# Keys: linux, darwin, windows (build jobs), test_native, test_container.
# Empty selections are emitted as [] and the jobs skip themselves.

set -euo pipefail
selected="${1:-}"
all="linux-x86_64 linux-aarch64 darwin-x86_64 darwin-aarch64 windows-x86_64"
[ -n "${selected}" ] || selected="${all}"

want() { case " ${selected} " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

for p in ${selected}; do
    case " ${all} " in *" ${p} "*) ;; *) echo "unknown platform: ${p}" >&2; exit 1 ;; esac
done

linux='[]'; darwin='[]'; windows='[]'; native='[]'; container='[]'

add() { # var json
    local cur="${!1}"
    printf -v "$1" '%s' "$(jq -c --argjson e "$2" '. + [$e]' <<< "${cur}")"
}

if want linux-x86_64; then
    add linux   '{"arch":"x86_64","runner":"ubuntu-24.04"}'
    # Newer host than the build container, and the glibc floor itself.
    add native    '{"platform":"linux-x86_64","artifact":"gnat-x86_64-linux","runner":"ubuntu-22.04","label":"ubuntu-22.04 host"}'
    add container '{"platform":"linux-x86_64","artifact":"gnat-x86_64-linux","runner":"ubuntu-24.04","image":"debian:10","setup":"apt-get update -qq && apt-get install -y -qq --no-install-recommends libc6-dev","label":"debian 10 (glibc 2.28)"}'
    add container '{"platform":"linux-x86_64","artifact":"gnat-x86_64-linux","runner":"ubuntu-24.04","image":"almalinux:8","setup":"dnf install -y -q glibc-devel","label":"almalinux 8 (glibc 2.28)"}'
fi
if want linux-aarch64; then
    add linux   '{"arch":"aarch64","runner":"ubuntu-24.04-arm"}'
    add native    '{"platform":"linux-aarch64","artifact":"gnat-aarch64-linux","runner":"ubuntu-22.04-arm","label":"ubuntu-22.04-arm host"}'
    add container '{"platform":"linux-aarch64","artifact":"gnat-aarch64-linux","runner":"ubuntu-24.04-arm","image":"debian:10","setup":"apt-get update -qq && apt-get install -y -qq --no-install-recommends libc6-dev","label":"debian 10 arm64 (glibc 2.28)"}'
fi
if want darwin-x86_64; then
    add darwin  '{"arch":"x86_64","runner":"macos-15-intel"}'
    add native  '{"platform":"darwin-x86_64","artifact":"gnat-x86_64-darwin","runner":"macos-26-intel","label":"macos-26-intel host"}'
fi
if want darwin-aarch64; then
    add darwin  '{"arch":"aarch64","runner":"macos-15"}'
    add native  '{"platform":"darwin-aarch64","artifact":"gnat-aarch64-darwin","runner":"macos-26","label":"macos-26 host"}'
fi
if want windows-x86_64; then
    add windows '{"arch":"x86_64","runner":"windows-2025"}'
    # Git Bash only: proves no msys2 runtime is needed.
    add native  '{"platform":"windows-x86_64","artifact":"gnat-x86_64-windows","runner":"windows-2022","label":"windows-2022 host (Git Bash)","experimental":false}'
    # No native GNAT exists for Windows on ARM (see README); this is the
    # supported route: the x86_64 toolchain under Windows' x64 emulation.
    add native  '{"platform":"windows-x86_64","artifact":"gnat-x86_64-windows","runner":"windows-11-arm","label":"windows-11-arm host (x64 emulation)","experimental":true}'
fi

printf 'linux=%s\n' "${linux}"
printf 'darwin=%s\n' "${darwin}"
printf 'windows=%s\n' "${windows}"
printf 'test_native=%s\n' "${native}"
printf 'test_container=%s\n' "${container}"

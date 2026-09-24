#!/usr/bin/env bash
# Entry point executed inside the Debian 10 build container.
#
# Installs the build prerequisites (including the distribution GNAT used
# only for stage 1 of the bootstrap), then runs the normal build pipeline
# with /work as the scratch directory.

set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

# Debian 10 is end-of-life: packages live on archive.debian.org and are
# frozen, which is exactly what a pinned build wants.
cat > /etc/apt/sources.list <<'EOF'
deb http://archive.debian.org/debian buster main
deb http://archive.debian.org/debian-security buster/updates main
EOF
apt-get -o Acquire::Check-Valid-Until=false -qq update
apt-get -qq install -y --no-install-recommends \
    gnat gnat-8 gcc g++ binutils libc6-dev \
    make m4 flex bison patch file \
    xz-utils bzip2 curl ca-certificates python3 \
    >/dev/null

# Unversioned tool names are what GCC's build system invokes.
for tool in gnatmake gnatbind gnatlink gnatls; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        ln -s "/usr/bin/${tool}-8" "/usr/bin/${tool}"
    fi
done

echo "glibc:     $(ldd --version | head -1)"
echo "bootstrap: $(gnatmake --version | head -1)"

# Never write into the read-only checkout.
export PA_WORK=/work
export PA_OUT=/work/out
export HOME=/work/home
mkdir -p "${HOME}"

status=0
bash /src/scripts/build-all.sh || status=$?

if [ -n "${PA_HOST_UID:-}" ]; then
    chown -R "${PA_HOST_UID}:${PA_HOST_GID:-${PA_HOST_UID}}" /work || true
fi
exit "${status}"

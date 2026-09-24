# hermetic-gnat

Relocatable, self-contained GNAT (GCC with the Ada front end) toolchains,
built and verified by GitHub Actions, for use with
[rules_ada](https://github.com/periareon/rules_ada).

Every release ships one archive per platform. An archive can be extracted
anywhere, needs nothing from the machine beyond the C library (and Xcode's
linker on macOS), and is what `rules_ada` downloads as a toolchain.

| Platform | Archive | Runs on | Built on |
|---|---|---|---|
| Linux x86_64 | `gnat-x86_64-linux-<ver>.tar.gz` | any glibc ≥ 2.28 distro (RHEL 8, Debian 10, Ubuntu 18.10 and newer) | Debian 10 container on `ubuntu-24.04` |
| Linux arm64 | `gnat-aarch64-linux-<ver>.tar.gz` | same | Debian 10 container on `ubuntu-24.04-arm` |
| macOS x86_64 | `gnat-x86_64-darwin-<ver>.tar.gz` | macOS 11.0+ with Xcode or Command Line Tools | `macos-15-intel` |
| macOS arm64 | `gnat-aarch64-darwin-<ver>.tar.gz` | macOS 11.0+ with Xcode or Command Line Tools | `macos-15` |
| Windows x86_64 | `gnat-x86_64-windows64-<ver>.tar.gz` | Windows 7+ x64; Windows 11 on ARM through x64 emulation | `windows-2025` + msys2 |
| Windows arm64 | not possible today, see [Windows on ARM](#windows-on-arm) | | |

`<ver>` is `<gcc version>-<package release>`, for example `16.1.0-1`. Names,
tags and `.sha256` sidecars follow the GNAT-FSF-builds convention that
`rules_ada` already parses.

## GCC versions

Several GCC versions are maintained side by side on `main`. Everything
specific to one version (source checksums, the Darwin branch tag, the
bootstrap archives, the package release number) lives in
`versions/<gcc>.env`; everything that is a property of the recipe rather
than of the version (prerequisite libraries, the build container, the glibc,
macOS and Windows floors) lives in [versions/common.env](versions/common.env).
[versions/DEFAULT](versions/DEFAULT) names the version built when none is
selected.

| File | Selects |
|---|---|
| `versions/16.1.0.env` | GCC 16.1.0 (default) |
| `versions/15.3.0.env` | GCC 15.3.0 |

The version is chosen by `PA_GCC_VERSION` locally, by the `gcc_version`
input of a manual build, and by the tag at release time: `gnat-15.3.0-1`
builds from `versions/15.3.0.env`.

The package release number is what makes this arrangement maintainable.
When the recipe improves (a hermeticity fix, a new floor), the change is in
the shared scripts and applies to every version. To republish, bump
`PKG_RELEASE` in each version file and push one tag per version:
`16.1.0-2` and `15.3.0-2` are the same GCC sources built by the newer
recipe. Earlier releases stay available and stay pinned by their full
`<gcc>-<release>` in `rules_ada`, so nothing breaks retroactively.

To add a version, copy the closest `versions/<gcc>.env`, update
`GCC_VERSION`, the FSF tarball checksum, the `iains/gcc-<major>-branch`
tag and checksum, and the bootstrap archives of the same major from
GNAT-FSF-builds, then run a manual build with that `gcc_version`.

## Why a separate build

`rules_ada` currently consumes [alire-project/GNAT-FSF-builds](https://github.com/alire-project/GNAT-FSF-builds).
Those builds are excellent, and the recipe here is derived from theirs, but
they are built on current GitHub runner images without a compatibility
floor. Their Linux executables require glibc 2.35 and a system `libzstd`,
and their macOS executables carry the build host's OS version as their
minimum. This repository builds the same GCC sources with three goals:

1. **Widest reach.** Linux binaries are built inside a Debian 10 container
   and link only libc (glibc ≥ 2.28). macOS binaries are built with
   `MACOSX_DEPLOYMENT_TARGET=11.0`. Windows binaries target Windows 7 and
   import only system DLLs.
2. **Hermetic inputs and outputs.** Every source tarball, bootstrap compiler,
   container image and GitHub Action is pinned by checksum, digest or commit
   in [versions/](versions/) and the workflows. The output links its
   prerequisites statically, carries its own assembler and linker, and
   depends on nothing else.
3. **Verified before publishing.** Each archive is extracted on a machine
   other than the one that built it, compiled against, run, and inspected
   ([scripts/check.sh](scripts/check.sh)). A release is only created if every
   platform passes.

## Guarantees and how they are enforced

| Property | Enforced by |
|---|---|
| Runs from any directory | `check.sh` extracts to a random temp dir, invokes `gcc` by relative path and with `PATH` unset, and checks `gnat1`, `libgcc.a` and the search dirs resolve inside the archive |
| Only libc at run time (Linux) | `check.sh` fails if any executable has a `NEEDED` entry beyond libc/libm/libdl/libpthread/librt/ld-linux, or references a `GLIBC_` symbol version above `LINUX_GLIBC_FLOOR` |
| Only system libraries at run time (macOS) | `check.sh` fails on any `otool -L` entry outside `/usr/lib` and `/System/Library`, on any `minos` above `MACOS_DEPLOYMENT_TARGET`, and on any invalid code signature |
| Only system DLLs at run time (Windows) | `check.sh` fails on any DLL import that is neither a Windows system DLL nor shipped in `bin/` |
| Assembler and linker inside the archive | binutils are installed in the prefix and additionally copied to `libexec/gcc/<triple>/<ver>/`, the first place the driver looks, and part of the file set `rules_ada` gives the sandbox |
| Static `libgnat.a`, `libgnarl.a`, `libgcc.a` in the layout `rules_ada` expects | `check.sh` locates them the same way `rules_ada`'s repository rule does and links test programs with exactly those archives |
| Working compiler and runtime | seven programs under [test/](test/) covering separate compilation, tasking, exceptions, containers, Ada 2022, numerics and C interop are built twice (the `rules_ada` way and with `gnatmake`) and their output compared |
| Reproducible archive bytes | `mktar.py` writes sorted entries, `SOURCE_DATE_EPOCH` timestamps, root ownership and normalised modes; GCC's 3-stage bootstrap compares stage 2 and 3 |
| Bootstrap compiler leaves no trace | native builds use the standard 3-stage bootstrap, so the installed compiler was compiled by itself |
| Provenance | `share/portable-ada/manifest.json` inside every archive lists every source URL, checksum and configure flag |

Things that are deliberately *not* hermetic, because a native toolchain
cannot be: the target C library and its headers (glibc, the macOS SDK), and
Apple's assembler and linker on macOS. On Windows the mingw-w64 headers and
CRT are bundled, so nothing at all is required there.

## Using with rules_ada

Each release's notes contain a ready-to-paste `GNAT_VERSIONS` entry
(generated by [tools/rules_ada_versions.py](tools/rules_ada_versions.py)).
Either add it to `ada/private/versions.bzl` by hand, or change the
repository name in `rules_ada`'s `tools/update_versions/update_versions.py`
from `alire-project/GNAT-FSF-builds` to this repository: the tag pattern,
asset names and `.sha256` sidecars are compatible.

Two things worth knowing when wiring these archives into Bazel rules:

* **Static archive order.** With GNU ld, `libgnarl.a` must precede
  `libgnat.a` on the link line (tasking code pulls symbols from libgnat);
  `gnatlink` uses `-lgnarl -lgnat`. `check.sh` links in that order. On
  systems with glibc older than 2.34, `-lpthread -lrt -ldl` must also be
  passed explicitly when the binder's option list is not used.
* **Windows on ARM.** There is no native archive. Register the
  `windows-x86_64` archive for an exec platform of `@platforms//os:windows`
  + `@platforms//cpu:aarch64`; Windows 11 runs it under x64 emulation. CI
  verifies exactly that combination on a `windows-11-arm` runner.

## Windows on ARM

No released GCC can build a GNAT for `aarch64-w64-mingw32`:

* GCC 15 added the target for C and C++ only. Its release notes state that
  exception handling is not implemented, and in GCC 16.2 the SEH unwinder
  (`libgcc/unwind-seh.c`) still has `#error "Unsupported architecture."` for
  anything but x86_64. Ada exceptions and tasking need a working unwinder.
* The GNAT runtime's Windows configuration (`gcc/ada/Makefile.rtl`) only
  selects x86 and x86_64 variants under mingw; there is no aarch64 wiring.

When a GCC release gains both, this repository can add the platform as a
Canadian cross (build on Linux, host and target Windows arm64) without
changing anything else in the pipeline. Until then the supported route is
the x86_64 archive under Windows' built-in x64 emulation, which the
`windows-11-arm` test job exercises on every build.

## Repository layout

```
versions/
  common.env                  pins shared by all GCC versions (prereqs, container, floors)
  <gcc>.env                   per-version pins: GCC sources, Darwin branch, bootstrap, PKG_RELEASE
  DEFAULT                     version used when none is selected
scripts/
  build-all.sh                orchestrates the stages below for the current OS
  fetch-sources.sh            download + verify + unpack; fixes the target triple
  fetch-bootstrap.sh          pinned bootstrap GNAT (macOS, Windows)
  build-deps.sh               static GMP/MPFR/MPC/ISL
  build-binutils.sh           binutils into the prefix (Linux, Windows)
  build-mingw.sh              mingw-w64 headers + CRT (Windows)
  build-gcc.sh                configure, 3-stage bootstrap, install-strip
  package.sh                  prune, relocate helpers, licenses, manifest, tar
  check.sh                    verification of an unpacked toolchain
  mktar.py                    deterministic tar.gz writer
  linux/docker-build.sh       runs the Linux build in the pinned container
  linux/container-entry.sh    what runs inside that container
  darwin/ld-wrapper.sh        prefers ld-classic when Xcode provides it
  ci/matrix.sh                job matrices for the workflows
  ci/test-archive.sh          extract an archive to a temp dir and run check.sh
  ci/release-notes.sh         release notes with the rules_ada fragment
  env.sh                      prints the pins of one version (used by workflows)
test/<name>/                  Ada/C programs and expected output used by check.sh
tools/rules_ada_versions.py   GNAT_VERSIONS entry generator
.github/workflows/build.yml   build + cross-machine verification
.github/workflows/release.yml tag -> build -> verify -> GitHub release
```

## Building locally

Linux (any distro with Docker; produces the same bytes as CI):

```sh
scripts/linux/docker-build.sh                 # native arch
PA_DOCKER_PLATFORM=linux/arm64 scripts/linux/docker-build.sh   # via qemu, slow
```

macOS (Xcode or Command Line Tools installed, nothing else):

```sh
scripts/build-all.sh
```

Windows (msys2 shell, `pacman -S base-devel python tar xz bzip2`; the prefix
must be reachable under the same path from POSIX and Windows, so mount it):

```sh
mkdir -p /c/pa && mount C:/pa /pa
PA_WORK=/pa/work PA_OUT=/pa/out scripts/build-all.sh
```

Useful variables: `PA_GCC_VERSION` (which `versions/<gcc>.env` to build,
default `versions/DEFAULT`), `PA_WORK` (scratch dir, default `./work`),
`PA_OUT` (archives), `PA_JOBS`, `PA_STAGES="gcc package check"` to rerun a
subset, `PA_SKIP_CHECK=1`. Downloads are cached in `$PA_WORK/downloads`.

To verify any archive, including one from a release (the version is read
from the archive name):

```sh
scripts/ci/test-archive.sh gnat-x86_64-linux-16.1.0-1.tar.gz
```

## Releasing

1. Edit the relevant `versions/<gcc>.env`: a new version gets a new file
   (see [GCC versions](#gcc-versions)); a rebuild of existing sources with
   the current recipe only bumps `PKG_RELEASE`. Open a PR; the build
   workflow runs the default version on it, and a manual run with
   `gcc_version` covers any other.
2. Run the **Release** workflow from the Actions tab and pick the GCC
   version. It builds and verifies all five platforms first, and only then
   creates the tag `gnat-<gcc>-<PKG_RELEASE>` on that commit together with
   the GitHub release (archives, `.sha256` sidecars, `SHA256SUMS`, manifests,
   and notes containing the `rules_ada` entry). A failed build leaves
   nothing behind. Pushing the tag by hand works too and triggers the same
   workflow; either way it refuses a tag or release that already exists, or
   a tag that does not match the pin file's `PKG_RELEASE`.

After a recipe change that should reach every version, repeat step 1 and 2
once per version. Manual dispatch of the build workflow accepts
`gcc_version` and `platforms` inputs to build a subset without releasing.

## Archive layout

```
gnat-<arch>-<os>-<ver>/
  bin/                gcc, gnatbind, gnatmake, gnatlink, ar, as, ld, gcov, ...
  lib/gcc/<triple>/<gcc>/
     adainclude/      Ada runtime sources
     adalib/          libgnat.a, libgnarl.a, *.ali (+ shared variants)
     libgcc.a, libgcc_eh.a, libgcov.a, crt*.o, include/
  lib/                libstdc++, libatomic, ... (lib64 is a symlink to lib on Linux)
  libexec/gcc/<triple>/<gcc>/
     gnat1, cc1, cc1plus, collect2, lto1, lto-wrapper, liblto_plugin
     as, ld, ld.bfd, nm        (Linux, Windows)   ld -> ld-classic wrapper (macOS)
  <triple>/bin, <triple>/lib   binutils' own copies and ld scripts
  include/, <triple>/include   mingw-w64 headers (Windows)
  share/licenses/              GPL, GCC Runtime Library Exception, LGPL, ...
  share/portable-ada/manifest.json
```

## License

The scripts and workflows in this repository are under the license in
[LICENSE](LICENSE). The archives contain GCC, binutils, GMP, MPFR, MPC, ISL
and mingw-w64 under their own licenses, all included under `share/licenses/`
in each archive. Programs built with these toolchains are covered by the GCC
Runtime Library Exception. The exact sources of every release are listed in
its notes and in each archive's manifest.

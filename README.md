# hermetic-gnat

Relocatable, self-contained GNAT (GCC with the Ada front end) toolchains,
built and verified by GitHub Actions, for use with
[rules_ada](https://github.com/periareon/rules_ada).

A release of this repository is a build of its recipe: it contains one
archive per platform for every supported GCC version, all produced by the
same scripts at the same commit. An archive can be extracted anywhere,
needs nothing from the machine beyond the C library (and Xcode's linker on
macOS), and is what `rules_ada` downloads as a toolchain.

| Platform | Archive | Runs on | Built on |
|---|---|---|---|
| Linux x86_64 | `gnat-x86_64-linux-<gcc>.tar.gz` | any glibc ≥ 2.28 distro (RHEL 8, Debian 10, Ubuntu 18.10 and newer) | Debian 10 container on `ubuntu-24.04` |
| Linux arm64 | `gnat-aarch64-linux-<gcc>.tar.gz` | same | Debian 10 container on `ubuntu-24.04-arm` |
| macOS x86_64 | `gnat-x86_64-darwin-<gcc>.tar.gz` | macOS 11.0+ with Xcode or Command Line Tools | `macos-15-intel` |
| macOS arm64 | `gnat-aarch64-darwin-<gcc>.tar.gz` | macOS 11.0+ with Xcode or Command Line Tools | `macos-15` |
| Windows x86_64 | `gnat-x86_64-windows64-<gcc>.tar.gz` | Windows 7+ x64; Windows 11 on ARM through x64 emulation | `windows-2025` + msys2 |
| Windows arm64 | not possible today, see [Windows on ARM](#windows-on-arm) | | |

`<gcc>` is the GCC version, for example `16.1.0`. The release tag (`v1.2.0`)
identifies the recipe that built the archive. Asset and directory names
otherwise follow the GNAT-FSF-builds convention that `rules_ada` parses.

## Versions

Two things are versioned, deliberately separately:

* **GCC versions** live in [versions/](versions/): one `versions/<gcc>.env`
  per supported GCC (source checksums, Darwin branch tag, bootstrap
  archives), shared recipe pins in [versions/common.env](versions/common.env)
  (prerequisite libraries, the build container, the glibc, macOS and
  Windows floors), and [versions/DEFAULT](versions/DEFAULT) naming the one
  built when none is selected.

  | File | GCC |
  |---|---|
  | `versions/16.1.0.env` | 16.1.0 (default) |
  | `versions/15.3.0.env` | 15.3.0 |

* **hermetic-gnat versions** are the release tags, `vMAJOR.MINOR.PATCH`.
  Every release builds every GCC version above. When the recipe changes (a
  hermeticity fix, a new floor, a new prerequisite), that is one new
  release, and all GCC versions get it at once. Adding or removing a GCC
  version is likewise just a release whose notes list what it contains.

`rules_ada` tracks one hermetic-gnat release at a time. Its `versions.bzl`
is generated from that release, keyed by GCC version (`"16.1.0"`,
`"15.3.0"`), and records the release it came from. Moving `rules_ada` to a
new toolchain generation is one commit that changes every version
consistently, and a user's `--@rules_ada//ada/settings:version=16.1.0`
keeps working across it.

Locally and in manual builds the GCC version is selected by
`PA_GCC_VERSION` or the `gcc_versions` workflow input; PRs build only the
default version, releases build all of them.

To add a GCC version, copy the closest `versions/<gcc>.env`, update
`GCC_VERSION`, the FSF tarball checksum, the `iains/gcc-<major>-branch`
tag and checksum, and the bootstrap archives of the same major from
GNAT-FSF-builds, then run a manual build with that version.

## Why a separate build

`rules_ada` originally consumed [alire-project/GNAT-FSF-builds](https://github.com/alire-project/GNAT-FSF-builds).
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
   archive of every GCC version passes.

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
| Provenance | `share/hermetic-gnat/manifest.json` inside every archive lists the hermetic-gnat version and commit, every source URL, checksum and configure flag |

Things that are deliberately *not* hermetic, because a native toolchain
cannot be: the target C library and its headers (glibc, the macOS SDK), and
Apple's assembler and linker on macOS. On Windows the mingw-w64 headers and
CRT are bundled, so nothing at all is required there.

## Using with rules_ada

`rules_ada`'s `tools/update_versions` reads the newest hermetic-gnat release
(or one named with `--release vX.Y.Z`) and regenerates
`ada/private/versions.bzl`; each release's notes also contain that content
ready to paste (generated by
[tools/rules_ada_versions.py](tools/rules_ada_versions.py)).

Two things worth knowing when wiring these archives into Bazel rules:

* **Static archive order.** With GNU ld, `libgnarl.a` must precede
  `libgnat.a` on the link line (tasking code pulls symbols from libgnat);
  `gnatlink` uses `-lgnarl -lgnat`. `check.sh` links in that order. On
  systems with glibc older than 2.34, `-lpthread -lrt -ldl` must also be
  passed explicitly when the binder's option list is not used, and `-lm`
  is needed for `Ada.Numerics`.
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
  <gcc>.env                   per-version pins: GCC sources, Darwin branch, bootstrap
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
  ci/matrix.sh                job matrices (platforms x GCC versions) for the workflows
  ci/test-archive.sh          extract an archive to a temp dir and run check.sh
  ci/release-notes.sh         release notes with the rules_ada versions.bzl content
  env.sh                      prints the pins of one GCC version (used by workflows)
test/<name>/                  Ada/C programs and expected output used by check.sh
tools/rules_ada_versions.py   versions.bzl generator for a set of archives
.github/workflows/build.yml   build + cross-machine verification
.github/workflows/release.yml version -> build all -> verify -> GitHub release
```

## Building locally

Linux (any distro with Docker; produces the same bytes as CI):

```sh
scripts/linux/docker-build.sh                 # native arch, default GCC
PA_GCC_VERSION=15.3.0 scripts/linux/docker-build.sh
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
default `versions/DEFAULT`), `PA_HG_VERSION` (recorded in the manifest and
`gcc --version`; `dev` unless set by a release), `PA_WORK` (scratch dir,
default `./work`), `PA_OUT` (archives), `PA_JOBS`,
`PA_STAGES="gcc package check"` to rerun a subset, `PA_SKIP_CHECK=1`.
Downloads are cached in `$PA_WORK/downloads`.

To verify any archive, including one from a release (the GCC version is
read from the archive name):

```sh
scripts/ci/test-archive.sh gnat-x86_64-linux-16.1.0.tar.gz
```

## Releasing

1. Merge whatever should go out: recipe changes in `scripts/` or
   `versions/common.env`, new or removed `versions/<gcc>.env` files. PRs
   build and verify the default GCC version; a manual run of the build
   workflow with `gcc_versions: all` covers the rest before releasing.
2. Run the **Release** workflow from the Actions tab and enter the version
   (`1.2.0`). It builds every GCC version on every platform, verifies each
   archive on other machines, and only then creates the tag `v1.2.0` on
   that commit together with the GitHub release: archives, `.sha256`
   sidecars, `SHA256SUMS`, manifests, and notes containing the `rules_ada`
   `versions.bzl` content. A failed build leaves nothing behind. Pushing the
   tag by hand triggers the same workflow; either way an existing tag or
   release is refused.
3. In `rules_ada`, `bazel run //tools/update_versions`, then buildifier,
   commit.

The release is published with the workflow's own `GITHUB_TOKEN`
(`contents: write`). If that token is refused (`HTTP 403: Resource not
accessible by integration`), an organisation policy caps the token or a tag
ruleset / tag protection rule denies it the right to create tags. Either
relax that rule for the GitHub Actions app, or store a token that is allowed
to create tags as the repository secret `RELEASE_TOKEN`: a fine-grained
personal access token limited to this repository with *Contents: read and
write*, or a GitHub App installation token. The release itself is created by
`softprops/action-gh-release`, pinned by commit like every other action.

## Archive layout

```
gnat-<arch>-<os>-<gcc>/
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
  share/hermetic-gnat/manifest.json
```

## License

The scripts and workflows in this repository are under the license in
[LICENSE](LICENSE). The archives contain GCC, binutils, GMP, MPFR, MPC, ISL
and mingw-w64 under their own licenses, all included under `share/licenses/`
in each archive. Programs built with these toolchains are covered by the GCC
Runtime Library Exception. The exact sources of every release are listed in
its notes and in each archive's manifest.

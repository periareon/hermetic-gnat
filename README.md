# hermetic-gnat

Prebuilt GNAT toolchains (GCC with the Ada front end) that run from any
directory on a wide range of machines. Built and verified by GitHub Actions,
consumed by [rules_ada](https://github.com/periareon/rules_ada).

| Platform | Archive | Runs on |
|---|---|---|
| Linux x86_64 | `gnat-x86_64-linux-<gcc>.tar.gz` | glibc ≥ 2.28 (RHEL 8, Debian 10, Ubuntu 18.10 and newer) |
| Linux arm64 | `gnat-aarch64-linux-<gcc>.tar.gz` | same |
| macOS x86_64 | `gnat-x86_64-darwin-<gcc>.tar.gz` | macOS 11+, with Xcode or Command Line Tools |
| macOS arm64 | `gnat-aarch64-darwin-<gcc>.tar.gz` | macOS 11+, with Xcode or Command Line Tools |
| Windows x86_64 | `gnat-x86_64-windows64-<gcc>.tar.gz` | Windows 7+; Windows 11 on ARM via x64 emulation |

There is no Windows arm64 archive: no released GCC has an exception unwinder
or a GNAT runtime for `aarch64-w64-mingw32`. The x86_64 archive under x64
emulation is the supported route and is tested in CI.

## What a release is

A release is a build of this repository's recipe, tagged with the UTC date
it was cut (`2026.09.30`, then `2026.09.30.1` for a second one that day).
It contains every supported GCC version on every platform, all built by the
same scripts at the same commit. Supported GCC versions are the
`versions/<gcc>.env` files; [versions/common.env](versions/common.env) holds
the pins shared by all of them, and [versions/DEFAULT](versions/DEFAULT)
names the one built when nothing is selected.

When the recipe changes, cut one release and every GCC version gets it.
Adding or dropping a GCC version is also just a release. `rules_ada` tracks
one release at a time; each release's notes include the generated
`versions.bzl`.

## How an archive is built

Each archive is produced by [scripts/build-all.sh](scripts/build-all.sh)
from sources pinned by checksum in `versions/`:

1. Static GMP, MPFR, MPC and ISL, then binutils (Linux, Windows) and the
   mingw-w64 headers and CRT (Windows) are built into the prefix.
2. GCC is configured with C, C++ and Ada and built with its standard
   3-stage bootstrap, so the shipped compiler was compiled by itself. Linux
   builds run inside a pinned Debian 10 container and bootstrap from its
   GNAT 8; macOS and Windows bootstrap from pinned GNAT-FSF-builds archives.
3. Packaging prunes docs and build-host headers, folds `lib64` into `lib`,
   copies the assembler and linker next to `gnat1` so the driver never needs
   `PATH`, adds license texts and a manifest, and writes a deterministic
   tarball.

What makes the result portable: Linux executables reference no glibc symbol
newer than 2.28 and no library but libc; macOS binaries are built for
macOS 11 and signed; Windows binaries import only system DLLs and bundle the
mingw-w64 CRT; all prerequisites are linked statically; nothing depends on
the install location.

## How an archive is verified

Every archive is downloaded on a machine other than the one that built it
(newer Ubuntu hosts, Debian 10 and AlmaLinux 8 containers, macOS 26 runners,
Windows 2022 with plain Git Bash, Windows 11 ARM under emulation) and run
through [scripts/check.sh](scripts/check.sh), which:

- extracts it to a random temporary directory and confirms `gcc` finds its
  own `gnat1`, `libgcc.a` and runtime there, also when invoked by relative
  path and with no `PATH`;
- builds and runs the programs under [test/](test/) (separate compilation,
  tasking, exceptions, containers, Ada 2022, numerics, C interop), once the
  way rules_ada links and once with `gnatmake`;
- inspects every executable: `NEEDED` entries and glibc symbol versions on
  Linux, linked libraries, minimum OS and code signature on macOS, DLL
  imports on Windows.

A release is only created if every archive of every GCC version passes.

## Releasing

Merge what should go out, then run the **Release** workflow from the
Actions tab. It builds all GCC versions on all platforms, verifies them,
and only then creates the tag and the GitHub release. Pushing a date tag by
hand triggers the same workflow. PRs build and verify the default GCC
version only; the build workflow can be run manually with `gcc_versions:
all` or a subset of `platforms`.

The release is published with the workflow's `GITHUB_TOKEN`. If that is
refused (`HTTP 403: Resource not accessible by integration`), an
organisation policy or tag rule is blocking it; either allow the GitHub
Actions app to create tags, or store a fine-grained personal access token
(this repository, *Contents: read and write*) as the `RELEASE_TOKEN` secret.

## Building locally

```sh
scripts/linux/docker-build.sh                       # Linux, native arch, in the pinned container
scripts/build-all.sh                                # macOS (needs Xcode or Command Line Tools)
PA_WORK=/pa/work PA_OUT=/pa/out scripts/build-all.sh   # Windows, msys2 shell, after: mkdir -p /c/pa && mount C:/pa /pa
```

`PA_GCC_VERSION=15.3.0` selects a GCC version, `PA_STAGES="gcc package
check"` reruns a subset of stages, `PA_JOBS` sets parallelism. To verify any
archive, including one from a release:

```sh
scripts/ci/test-archive.sh gnat-x86_64-linux-16.1.0.tar.gz
```

To add a GCC version, copy the closest `versions/<gcc>.env`, update the FSF
tarball checksum, the `iains/gcc-<major>-branch` tag and checksum, and the
same-major bootstrap archives from GNAT-FSF-builds, then run a manual build
with that version.

## License

The scripts and workflows in this repository are under the license in
[LICENSE](LICENSE). The archives contain GCC, binutils, GMP, MPFR, MPC, ISL
and mingw-w64 under their own licenses, included under `share/licenses/` in
each archive; programs built with these toolchains are covered by the GCC
Runtime Library Exception. Every archive's `share/hermetic-gnat/manifest.json`
lists the exact sources, checksums and configure flags it was built from.

#!/usr/bin/env python3
"""Print the rules_ada ``GNAT_VERSIONS`` entry for one release of this repo.

Reads the ``*.tar.gz.sha256`` sidecars produced by scripts/package.sh (or a
``SHA256SUMS`` file) and emits Starlark in exactly the shape used by
``ada/private/versions.bzl`` in periareon/rules_ada, so a release can be
consumed before (or instead of) teaching rules_ada's updater about this
repository.

    tools/rules_ada_versions.py --repo OWNER/portable-ada dist/

Asset names follow the GNAT-FSF-builds convention that rules_ada already
parses: gnat-<arch>-<linux|darwin|windows64>-<gcc>-<release>.tar.gz
"""

import argparse
import base64
import pathlib
import re
import sys

ASSET_RE = re.compile(
    r"^gnat-(x86_64|aarch64)-(linux|darwin|windows64)-(\d+\.\d+\.\d+-\d+)\.tar\.gz$"
)
PLATFORM = {
    ("x86_64", "linux"): "linux-x86_64",
    ("aarch64", "linux"): "linux-aarch64",
    ("x86_64", "darwin"): "darwin-x86_64",
    ("aarch64", "darwin"): "darwin-aarch64",
    ("x86_64", "windows64"): "windows-x86_64",
    ("aarch64", "windows64"): "windows-aarch64",
}


def integrity(hex_digest):
    return "sha256-" + base64.b64encode(bytes.fromhex(hex_digest)).decode()


def read_sums(directory):
    sums = {}
    sums_file = directory / "SHA256SUMS"
    files = [sums_file] if sums_file.exists() else sorted(directory.glob("*.tar.gz.sha256"))
    for f in files:
        for line in f.read_text().splitlines():
            parts = line.split()
            if len(parts) >= 2:
                sums[pathlib.Path(parts[-1]).name] = parts[0]
            elif len(parts) == 1 and f.name.endswith(".tar.gz.sha256"):
                sums[f.name[: -len(".sha256")]] = parts[0]
    return sums


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--repo", required=True, help="GitHub owner/name hosting the releases")
    ap.add_argument("--server", default="https://github.com")
    ap.add_argument("directory", type=pathlib.Path, help="directory with the .sha256 sidecars")
    args = ap.parse_args()

    entries = {}
    version = None
    for name, digest in read_sums(args.directory).items():
        m = ASSET_RE.match(name)
        if not m:
            continue
        arch, osname, ver = m.groups()
        if version and ver != version:
            sys.exit("mixed versions in %s: %s and %s" % (args.directory, version, ver))
        version = ver
        entries[PLATFORM[(arch, osname)]] = {
            "integrity": integrity(digest),
            "strip_prefix": name[: -len(".tar.gz")],
            "url": "%s/%s/releases/download/gnat-%s/%s" % (args.server, args.repo, ver, name),
        }
    if not entries:
        sys.exit("no gnat-*.tar.gz checksums found in %s" % args.directory)

    out = ['    "%s": {' % version]
    for platform in sorted(entries):
        e = entries[platform]
        out.append('        "%s": {' % platform)
        for key in ("integrity", "strip_prefix", "url"):
            out.append('            "%s": "%s",' % (key, e[key]))
        out.append("        },")
    out.append("    },")
    print("\n".join(out))


if __name__ == "__main__":
    main()

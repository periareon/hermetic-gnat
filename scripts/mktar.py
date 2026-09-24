#!/usr/bin/env python3
"""Write a deterministic .tar.gz of a directory tree.

Entries are sorted, timestamps are pinned to SOURCE_DATE_EPOCH, ownership is
root:root with empty names, modes are normalised to 0755/0644, symlinks are
kept as symlinks, hard links become regular files, and the gzip header
carries no name or timestamp.  Two runs over identical trees give identical
bytes on Linux, macOS and Windows (msys2 Python).

Usage: mktar.py --output OUT.tar.gz --root-name NAME [--mtime EPOCH] DIR

Python 3.7 compatible (Debian 10 build container).
"""

import argparse
import gzip
import os
import stat
import sys
import tarfile


def normalised_mode(st_mode):
    if stat.S_ISDIR(st_mode):
        return 0o755
    if st_mode & (stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH):
        return 0o755
    return 0o644


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--output", required=True)
    ap.add_argument("--root-name", required=True,
                    help="name of the single top-level directory in the archive")
    ap.add_argument("--mtime", type=int,
                    default=int(os.environ.get("SOURCE_DATE_EPOCH", "0")))
    ap.add_argument("directory")
    args = ap.parse_args()

    root = os.path.abspath(args.directory)
    if not os.path.isdir(root):
        sys.exit("not a directory: %s" % root)

    entries = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames.sort()
        for name in sorted(dirnames + filenames):
            entries.append(os.path.join(dirpath, name))
    entries.sort()

    tmp = args.output + ".part"
    count = 0
    with open(tmp, "wb") as raw:
        with gzip.GzipFile(filename="", mode="wb", fileobj=raw, mtime=0) as gz:
            with tarfile.open(fileobj=gz, mode="w", format=tarfile.PAX_FORMAT) as tar:
                top = tarfile.TarInfo(args.root_name)
                top.type = tarfile.DIRTYPE
                top.mode = 0o755
                top.mtime = args.mtime
                tar.addfile(top)
                for path in entries:
                    rel = os.path.relpath(path, root).replace(os.sep, "/")
                    st = os.lstat(path)
                    info = tarfile.TarInfo(args.root_name + "/" + rel)
                    info.mtime = args.mtime
                    info.uid = info.gid = 0
                    info.uname = info.gname = ""
                    info.mode = normalised_mode(st.st_mode)
                    if stat.S_ISLNK(st.st_mode):
                        info.type = tarfile.SYMTYPE
                        info.linkname = os.readlink(path).replace(os.sep, "/")
                        tar.addfile(info)
                    elif stat.S_ISDIR(st.st_mode):
                        info.type = tarfile.DIRTYPE
                        tar.addfile(info)
                    elif stat.S_ISREG(st.st_mode):
                        info.type = tarfile.REGTYPE
                        info.size = st.st_size
                        with open(path, "rb") as f:
                            tar.addfile(info, f)
                    else:
                        sys.exit("unsupported file type: %s" % path)
                    count += 1
    os.replace(tmp, args.output)
    print("%s: %d entries" % (args.output, count))


if __name__ == "__main__":
    main()

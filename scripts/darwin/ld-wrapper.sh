#!/bin/sh
# Installed as libexec/gcc/<triple>/<version>/ld on macOS, where the GCC
# driver looks before PATH.  Xcode 15+ ships a new linker that still has
# rough edges with GCC-produced objects; use ld-classic when the installed
# Xcode / Command Line Tools provide it, otherwise fall back to the default.
classic=$(xcrun --find ld-classic 2>/dev/null) || true
if [ -n "$classic" ]; then
    exec "$classic" "$@"
fi
exec ld "$@"

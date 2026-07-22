#!/bin/zsh
# Run the test suite. With Command Line Tools only (no Xcode), Swift Testing's
# framework isn't on SwiftPM's default search path — point at it explicitly.
# With full Xcode installed (e.g. CI), plain `swift test` works; these flags
# are harmless there.
set -euo pipefail
cd "$(dirname "$0")"

CLT_FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
CLT_TESTLIB=/Library/Developer/CommandLineTools/Library/Developer/usr/lib

exec swift test \
    -Xswiftc -F -Xswiftc "$CLT_FRAMEWORKS" \
    -Xlinker -F"$CLT_FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$CLT_FRAMEWORKS" \
    -Xlinker -rpath -Xlinker "$CLT_TESTLIB" \
    "$@"

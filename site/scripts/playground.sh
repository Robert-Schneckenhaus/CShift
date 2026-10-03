#!/usr/bin/env bash
# Builds the compiler of the playground (src/components/Playground.astro): cshc as WebAssembly, into public/playground/,
# with the compiler given (a cshiftc of this version). Its examples (src/playground/examples.js) must compile and run.
#
#   site/scripts/playground.sh <cshiftc>
#
# Needs clang with the C library of WASI (Ubuntu: wasi-libc, libclang-rt-<version>-dev-wasm32, lld-<version>) and node.
set -euo pipefail
CSHIFTC="$(cd "$(dirname "${1:?cshiftc}")" && pwd)/$(basename "$1")"
SITE="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$(cd "$SITE/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# the examples compile (with this version of the compiler)
node --input-type=module -e "
import { examples } from '$SITE/src/playground/examples.js';
import { writeFileSync } from 'node:fs';
examples.forEach((e, i) => writeFileSync('$WORK/example' + i + '.csh', e.code));
"
for example in "$WORK"/example*.csh; do
    if ! "$CSHIFTC" check "$example"; then
        echo "error: an example of the playground does not compile: $example" >&2
        exit 1
    fi
    # ... and runs (Run: the wasm backend, like in the page)
    if ! "$CSHIFTC" --backend wasm "$example" -o "$WORK/example.wasm" || ! node --no-warnings "$ROOT/tests/wasi-run.mjs" "$WORK/example.wasm" > /dev/null; then
        echo "error: an example of the playground does not run: $example" >&2
        exit 1
    fi
done

mkdir -p "$SITE/public/playground"
(cd "$ROOT" && "$CSHIFTC" build selfhost --target wasm32-wasi -o "$SITE/public/playground/cshc.wasm")
echo "built $SITE/public/playground/cshc.wasm ($(wc -c < "$SITE/public/playground/cshc.wasm") bytes)"

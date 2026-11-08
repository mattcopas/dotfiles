#!/usr/bin/env bash
# Regenerates test/golden/expected from real Emacs and org. Home machine only.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
export ORGFLOW_GOLDEN_WORK="$(mktemp -d)"
trap 'rm -rf "$ORGFLOW_GOLDEN_WORK"' EXIT
rm -rf "$here/expected"
TZ=UTC LC_ALL=C emacs -Q --batch --load "$here/generate.el" < /dev/null

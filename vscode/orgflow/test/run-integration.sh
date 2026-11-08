#!/usr/bin/env bash
# Runs src/test/integration.ts in a throwaway VS Code profile. The VS Code CLI exits 0
# even when a test throws, so this reads a result file, and fails if the tests never
# reached the end. Your own settings and extensions are not touched.
set -uo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export ORGFLOW_TEST_ROOT="$work/files"
export ORGFLOW_TEST_RESULT="$work/result.txt"
mkdir -p "$ORGFLOW_TEST_ROOT"

run=(code)
if [[ -z "${DISPLAY:-}" ]] || [[ "${ORGFLOW_HEADLESS:-1}" == "1" ]]; then
  if command -v xvfb-run >/dev/null; then
    run=(xvfb-run -a code)
  fi
fi

timeout 180 "${run[@]}" \
  --user-data-dir "$work/data" --extensions-dir "$work/extensions" \
  --disable-gpu --disable-workspace-trust \
  --extensionDevelopmentPath="$here" \
  --extensionTestsPath="$here/out/test/integration.js" \
  --wait >"$work/log.txt" 2>&1 </dev/null

if [[ ! -f "$ORGFLOW_TEST_RESULT" ]] || ! grep -q '^DONE$' "$ORGFLOW_TEST_RESULT"; then
  echo "Integration tests did not finish. Log tail:"
  tail -20 "$work/log.txt"
  exit 1
fi
grep -v '^DONE$' "$ORGFLOW_TEST_RESULT"
if grep -q '^FAILED' "$ORGFLOW_TEST_RESULT"; then
  echo "Some integration tests failed."
  exit 1
fi
echo "All integration tests passed: $(grep -c '^ok' "$ORGFLOW_TEST_RESULT")"

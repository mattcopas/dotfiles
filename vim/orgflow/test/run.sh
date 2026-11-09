#!/usr/bin/env bash
# Runs a headless test script in a clean Vim and reports from its result file, because
# Vim's own exit status doesn't reflect what a script found.
#   test/run.sh            engine and editor tests
#   VIM=/path/to/vim test/run.sh   the same with another Vim, such as a 9.0 build
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
vim=${VIM:-/usr/bin/vim}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
status=0

"$vim" --version | head -2 | tr '\n' ' '
echo

for name in engine editor; do
  script="$root/test/$name.vim"
  [ -f "$script" ] || continue
  result="$work/$name.txt"
  HOME="$work/home" XDG_STATE_HOME="$work/state" "$vim" -u NONE -i NONE -n -N -e -s -V1"$work/$name.log" \
    --cmd "set rtp^=$root" \
    --cmd "let g:orgflow_root = '$root'" \
    --cmd "let g:orgflow_shared_tests = '$root/../../vscode/orgflow/test'" \
    --cmd "let g:orgflow_result = '$result'" \
    --cmd "let g:orgflow_work = '$work'" \
    -S "$script" -c 'qa!' </dev/null >"$work/$name.out" 2>&1
  echo "== $name"
  if [ -f "$result" ]; then
    cat "$result"
  else
    echo "no result file: the script stopped early"
  fi
  if [ ! -f "$result.ok" ]; then
    status=1
    grep -hE '^(E[0-9]+|Error detected|line +[0-9]+:)' "$work/$name.log" 2>/dev/null | tail -n 24
  fi
done
exit $status

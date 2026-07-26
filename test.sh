#!/usr/bin/env bash
# Self-check for sudo-guard.sh. No framework: feed it hook payloads on stdin
# and assert on what comes back.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

pass=0 fail=0

run() { jq -n --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}' | ./hooks/sudo-guard.sh; }

check() { # description, actual, expected
  if [ "$2" = "$3" ]; then
    pass=$((pass + 1))
  else
    fail=$((fail + 1))
    printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$3" "$2" >&2
  fi
}

out=$(run 'sudo apt install foo')
check "sudo asks for approval" \
  "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision')" "ask"
check "sudo command gets askpass exported" \
  "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.command' | grep -c '^export SUDO_ASKPASS=')" "1"
check "original command survives the rewrite" \
  "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.command' | grep -c 'sudo apt install foo$')" "1"

check "plain command is left alone" "$(run 'ls -l')" ""

# The bug this guards: an inline "VAR=x cmd" assignment only applies to the
# first command, so the second sudo would hang.
out=$(run 'sudo a && sudo b')
check "compound sudo uses export, not inline assignment" \
  "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.updatedInput.command' | grep -c '^export SUDO_ASKPASS=[^ ]*; sudo a && sudo b$')" "1"

check "sudoedit is caught too" \
  "$(run 'sudoedit /etc/hosts' | jq -r '.hookSpecificOutput.permissionDecision')" "ask"
check "pseudo does not trigger" "$(run 'grep pseudo notes.txt')" ""
check "sudoku does not trigger" "$(run 'echo sudoku')" ""

# askpass.sh: stub secret-tool on PATH rather than touching the real keyring.
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/empty" "$tmpdir/bin"

out=$(PATH="$tmpdir/empty" ./scripts/askpass.sh 2>&1); rc=$?
check "askpass fails when secret-tool is missing" \
  "$rc:$(printf '%s' "$out" | grep -c 'secret-tool not installed')" "1:1"

printf '#!/bin/sh\nexit 1\n' > "$tmpdir/bin/secret-tool"
chmod +x "$tmpdir/bin/secret-tool"
out=$(PATH="$tmpdir/bin" ./scripts/askpass.sh 2>&1); rc=$?
check "askpass fails when keyring entry is missing" \
  "$rc:$(printf '%s' "$out" | grep -c 'no password stored')" "1:1"

printf '#!/bin/sh\necho s3cr3t\n' > "$tmpdir/bin/secret-tool"
chmod +x "$tmpdir/bin/secret-tool"
out=$(PATH="$tmpdir/bin" ./scripts/askpass.sh 2>/dev/null); rc=$?
check "askpass prints the password and exits 0" "$rc:$out" "0:s3cr3t"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

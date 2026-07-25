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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]

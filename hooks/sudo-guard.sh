#!/usr/bin/env bash
# PreToolUse hook for Bash. When a command needs root, ask the user for
# approval in the Claude Code TUI and point sudo at our keyring askpass
# helper, since the tool process has no terminal to prompt on.
set -uo pipefail

# Fall back to the repo root so the script is runnable outside Claude Code.
plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

cmd=$(jq -r '.tool_input.command // empty')

# Word boundaries so "pseudo" and "sudoku" don't trigger a pointless prompt.
# Erring toward false positives is deliberate: an extra approval costs a
# keystroke, a miss costs a two-minute hang.
if [[ ! "$cmd" =~ (^|[^[:alnum:]_-])sudo(edit)?([^[:alnum:]_-]|$) ]]; then
  exit 0
fi

# "export" rather than an inline "VAR=x cmd" assignment: inline applies only
# to the first command, so `sudo a && sudo b` would hang on the second.
askpass="$plugin_root/scripts/askpass.sh"
printf -v new_cmd 'export SUDO_ASKPASS=%q; %s' "$askpass" "$cmd"

jq -n --arg c "$new_cmd" --arg orig "$cmd" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: ("Runs with root privileges: " + $orig),
    updatedInput: { command: $c }
  }
}'

#!/bin/sh
# sudo askpass helper. The whole contract is: print the password on stdout.
# sudo runs this automatically when no terminal is available.
#
# Exits non-zero on any failure so sudo gives up in about a second instead of
# hanging until the Bash tool times out.

if ! command -v secret-tool >/dev/null 2>&1; then
  echo "claude-sudo: secret-tool not installed. Run: sudo apt install libsecret-tools" >&2
  exit 1
fi

if pw=$(secret-tool lookup service claude-sudo user "$USER" 2>/dev/null) && [ -n "$pw" ]; then
  printf '%s\n' "$pw"
  exit 0
fi

echo "claude-sudo: no password stored. In a real terminal, run:" >&2
echo "  secret-tool store --label='claude sudo' service claude-sudo user $USER" >&2
exit 1

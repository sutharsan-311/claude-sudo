# claude-sudo: password prompts for Claude Code's Bash tool

**Date:** 2026-07-25
**Status:** implemented
**Platform:** Linux only (GNOME Keyring via `secret-tool`). Not supported on
macOS or Windows — see "Out of scope."

## The problem

Any `sudo` command Claude Code runs hangs until the Bash tool times out, then fails with:

```
sudo: a terminal is required to read the password; either use the -S option
to read from standard input or configure an askpass helper
```

Cursor's agent doesn't have this problem, which is what prompted the work.

## Why it happens

Measured on this machine, inside a Bash tool call:

| Property | Value |
|---|---|
| `TT` (controlling terminal) | `?` — none |
| stdin | `/dev/null` |
| stdout | pipe |
| session id | its own, distinct from the Claude Code process |
| `open("/dev/tty")` | fails |

The tool process is `setsid`-ed into a fresh session with no controlling
terminal. `sudo` reads passwords from `/dev/tty` specifically so they can't be
piped in casually, and that open fails. Nothing is misconfigured; there is
simply no terminal to prompt on.

Cursor avoids this by running agent commands in the IDE's integrated terminal,
a real PTY the user can type into. Claude Code deliberately does not, so a
runaway command can't capture the keyboard.

## Approaches rejected

**Prompt on the user's real terminal.** The tty is findable — `ps` shows the
Claude Code node process on `pts/0` and `pts/1`. Writing a prompt there works.
Reading the answer back does not: the TUI holds that terminal in raw mode and
consumes every keystroke, so the password would land in the Claude Code input
box and from there into the transcript.

**Ask the user through the model.** The only text-input channel a plugin can
reach is the conversation itself. That writes the password to
`~/.claude/projects/*.jsonl` in plaintext and sends it to the API. Considered
and declined; see "Alternative considered" below.

**Graphical dialog via zenity.** Works, and `zenity` is installed. Rejected on
ergonomics — a popup window pulls focus out of the CLI, which is the thing the
user wanted to stay in.

## Design

Two independent pieces, joined by an environment variable.

**The approval prompt** is a `PreToolUse` hook. When a Bash command mentions
`sudo`, the hook returns `permissionDecision: "ask"`, which surfaces a native
approve/deny in the Claude Code TUI. This is the same channel the official
plugin-dev examples use for privilege escalation, and it is the entire reason
the interaction feels like Cursor's: the decision happens in the CLI.

**The password** comes from GNOME Keyring, never from the conversation. The
same hook rewrites the command via `updatedInput` to prepend:

```sh
export SUDO_ASKPASS=${CLAUDE_PLUGIN_ROOT}/scripts/askpass.sh;
```

`sudo` consults `SUDO_ASKPASS` automatically when no terminal is available —
the `-A` flag is not needed, so the command itself is never parsed or rewritten
beyond that prefix.

`export` rather than an inline `VAR=x cmd` assignment is load-bearing. Inline
assignments apply only to the first command, so `sudo a && sudo b` would
authenticate the first and hang on the second.

### Layout

```
claude-sudo/
├── plugin.json
├── hooks/
│   ├── hooks.json          # PreToolUse, matcher: Bash
│   └── sudo-guard.sh       # detect sudo → inject askpass → ask approval
├── scripts/
│   └── askpass.sh          # keyring lookup, prints password to stdout
├── test.sh                 # asserts hook output on three payloads
└── README.md               # the two setup commands
```

### Components

**`hooks/sudo-guard.sh`** — reads the hook JSON on stdin, pulls
`.tool_input.command`. No `sudo` in it, exit 0 silently and the command runs
untouched. Otherwise emit the ask-plus-rewrite JSON. The match is a plain
substring test on purpose: a false positive costs one extra approval prompt,
a false negative costs a two-minute hang.

**`scripts/askpass.sh`** — the entire contract is "print the password to
stdout and exit 0".

```sh
#!/bin/sh
secret-tool lookup service claude-sudo user "$USER" 2>/dev/null && exit 0
echo "claude-sudo: no password in keyring. Run:" >&2
echo "  secret-tool store --label='claude sudo' service claude-sudo user $USER" >&2
exit 1
```

Exiting non-zero makes `sudo` fail in about a second instead of hanging, and
the stderr reaches the transcript so the failure explains itself.

### Flow

1. Claude runs `sudo apt install foo`
2. `sudo-guard.sh` fires, sees `sudo`, returns `ask` + rewritten command
3. User sees the approval in the CLI, approves
4. Bash runs `export SUDO_ASKPASS=...; sudo apt install foo`
5. `sudo` finds no tty, executes the askpass helper
6. Helper reads the keyring, prints the password on stdout
7. `sudo` authenticates, command runs

Steps 5–7 involve no terminal, no popup, and no model.

## Setup

Both commands must be run by the user in a real terminal, not through Claude
Code. `secret-tool store` reads the secret from a tty, so it hits the same wall
this plugin exists to route around.

```sh
sudo apt install libsecret-tools
secret-tool store --label='claude sudo' service claude-sudo user "$USER"
```

## Error handling

| Condition | Behaviour |
|---|---|
| `secret-tool` not installed | askpass exits 1 with the install command on stderr |
| Keyring entry missing | askpass exits 1 with the `store` command on stderr |
| Keyring locked | `secret-tool` blocks on its own unlock dialog; sudo fails on tool timeout |
| User denies at the approval prompt | Command never runs; hook decision is final |
| Wrong password stored | `sudo` retries, askpass returns the same value, sudo fails after 3 tries |

The wrong-password case is worth stating plainly: it produces three identical
keyring reads and then a normal auth failure. Fix is re-running `secret-tool
store`. Not worth detecting in code.

## Security properties

What this deliberately does and does not protect:

- The password never enters the transcript, the model's context, or the API.
- It does live in GNOME Keyring, encrypted at rest, unlocked at login. On Linux
  the per-application isolation is weak — anything running as the user can read
  it. That is also true of anything that can invoke `sudo` as the user, so the
  keyring does not widen the blast radius so much as make it explicit.
- The approval prompt is the real control. It shows the command before it runs
  and it cannot be bypassed by the model, because the hook runs out of process.
- The plugin never writes the password to disk, and never passes it as a command
  argument, so it stays out of shell history and the process table.

## Testing

One check, runnable, no framework:

**`test.sh`** feeds three crafted JSON payloads to `sudo-guard.sh` and asserts
on the output — a command with `sudo` produces `permissionDecision: "ask"` and
an `updatedInput.command` that starts with `export SUDO_ASKPASS=`; a command
without `sudo` produces no rewrite; and a compound `sudo a && sudo b` gets the
`export` form rather than an inline assignment. That last assertion is the one
guarding the bug that would otherwise show up only on the second command.

Manual verification, once, after install: `sudo -K` to clear any cached
timestamp, then have Claude run `sudo true` and confirm the approval appears in
the CLI and the command succeeds.

## Known risk to validate first

The official examples emit `permissionDecision` on **stderr with exit 2** for
the deny path. This design needs `ask` combined with `updatedInput`, which is
the stdout-with-exit-0 structured-output path. These two conventions are not
documented together.

**First implementation step** is a throwaway hook that returns exactly this
payload on stdout with exit 0, to confirm the approval prompt appears and the
command is actually rewritten. If `updatedInput` turns out not to apply on the
`ask` path, the fallback is writing `SUDO_ASKPASS` into `~/.claude/settings.json`
under `env` and reducing the hook to approval only. That fallback costs one
setup step and changes nothing else in this design.

## Alternative considered: ask in the CLI every time

Rejected, recorded because it was close.

No keyring and no setup. On the first sudo of a session the model asks the user
via AskUserQuestion, writes the answer to `$XDG_RUNTIME_DIR/claude-sudo.pw`
under `umask 077`, and a `SessionEnd` hook shreds it. The runtime dir is tmpfs,
so the file dies at reboot.

The cost is that the password is written to the session transcript twice — once
as the answer, once in the `Write` call — and the transcript is plaintext on
disk and goes to the API. Zero setup was not worth a root password in a log
file. Worth revisiting only for a machine where `libsecret-tools` cannot be
installed.

## Out of scope

- **macOS and Windows.** The password backend is GNOME Keyring via
  `secret-tool`, a Linux/libsecret-specific tool. Keychain (macOS) and
  Credential Manager (Windows) would need their own askpass backends; not
  attempted here.
- Headless and SSH sessions. Nothing can prompt there; the askpass helper fails
  fast with a readable message and the user runs the command themselves.
- Per-command allowlists or denylists. The approval prompt already shows the
  command and requires a human keystroke.
- Any attempt to cache or extend `sudo`'s own timestamp. `tty_tickets` is on by
  default and keys the cache to a terminal this process does not have.

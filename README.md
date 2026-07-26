# claude-sudo

`sudo` `askpass` `keyring` `hooks` `security`

**Linux only.** The password backend is GNOME Keyring via `secret-tool`; there
is no macOS (Keychain) or Windows (Credential Manager) support.

`sudo` doesn't work in Claude Code. Commands hang until the Bash tool times
out, then fail with:

```
sudo: a terminal is required to read the password
```

This plugin fixes that. You approve each root command in the CLI, and the
password comes from your keyring rather than being typed into the chat.

## Why sudo breaks

Claude Code runs Bash tool commands in a process with no controlling terminal
— `setsid`-ed into its own session, stdin on `/dev/null`, and `open("/dev/tty")`
fails. `sudo` reads passwords from `/dev/tty` specifically so they can't be
piped in casually, so it gives up.

Cursor doesn't hit this because its agent runs commands in the IDE's integrated
terminal, which is a real PTY you can type into.

## How this works

Two pieces.

A `PreToolUse` hook spots `sudo` in a command and returns
`permissionDecision: "ask"`, which surfaces a native approve/deny in the Claude
Code TUI. The same hook rewrites the command to export `SUDO_ASKPASS`.

`sudo` consults `SUDO_ASKPASS` on its own when no terminal is available — no
`-A` flag needed — and the helper reads your password out of GNOME Keyring.

The password never enters the conversation, the transcript, or the API.

## Setup

Both commands must run in a **real terminal**, not through Claude Code.
`secret-tool store` reads the secret from a tty, which is the exact thing this
plugin exists to work around.

```sh
sudo apt install libsecret-tools
secret-tool store --label='claude sudo' service claude-sudo user "$USER"
```

Then install the plugin and restart Claude Code:

```
/plugin marketplace add sutharsan-311/claude-sudo
/plugin install claude-sudo@claude-sudo
```

Hooks load at startup, so the restart is required.

## Verifying

```sh
sudo -K              # clear any cached sudo timestamp
```

Then ask Claude to run `sudo true`. You should see an approval prompt naming
the command, and after approving, it succeeds.

## Tests

```sh
./test.sh
```

Feeds crafted hook payloads to `sudo-guard.sh` and asserts on the output. No
framework.

## Security notes

- The approval prompt is the real control. It shows the command before it runs
  and the model cannot bypass it, because the hook runs out of process.
- The password lives in GNOME Keyring, encrypted at rest, unlocked at login. On
  Linux, per-application isolation is weak — anything running as you can read
  it. That's equally true of anything that can just run `sudo` as you, so this
  doesn't widen the blast radius so much as make it explicit.
- Nothing is written to disk, and the password is never passed as a command
  argument, so it stays out of shell history and the process table.

## Limitations

- **Needs a keyring.** On a headless box with no `secret-tool`, the helper fails
  fast with a readable message instead of hanging. Run the command yourself.
- **Wrong password stored?** `sudo` retries three times against the same keyring
  value and fails. Re-run `secret-tool store`.
- **Detection is a word-boundary match on `sudo`/`sudoedit`.** It errs toward
  false positives on purpose: an extra approval prompt costs one keystroke, a
  miss costs a two-minute hang.

## License

[MIT](LICENSE)

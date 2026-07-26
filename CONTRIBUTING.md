# Contributing

## Setup

No build step. Edit the shell scripts under `hooks/` and `scripts/`, then:

```sh
./test.sh
```

To test against a live Claude Code session, restart it (hooks load at
startup) and run `sudo true` — see "Verifying" in the README.

## Scope

This plugin is Linux-only by design: the password backend is GNOME Keyring
via `secret-tool`, and there's no macOS/Windows equivalent wired up. A macOS
(Keychain) or Windows (Credential Manager) backend is welcome as a PR, but it
needs its own askpass script and can't assume `secret-tool` exists — don't
special-case it into the Linux path.

Also out of scope, already considered and rejected — see
`docs/design.md#approaches-rejected` and `#out-of-scope` before proposing
these:

- Prompting on the user's own terminal instead of the CLI approval dialog
- Per-command allowlists/denylists (the approval prompt already is the gate)
- Caching or extending `sudo`'s own timestamp across commands
- Headless/SSH support (nothing can prompt there by design)

## Pull requests

- Keep `test.sh` passing; add a case to it if you change `sudo-guard.sh`'s
  detection or output.
- No test framework — `test.sh` is plain assertions on hook JSON output,
  keep new tests in the same style.
- Explain *why*, not just what, in the PR description if the change touches
  the detection regex or the approval flow — those have security
  implications and the reasoning in `docs/design.md` should stay accurate.

# omarchy-teleport

[![License: MIT](https://img.shields.io/github/license/WSeubring/omarchy-teleport)](LICENSE)
![Scope: personal](https://img.shields.io/badge/scope-personal-blue)

> **Disclaimer:** vibe-coded for my own machine. Personal use, no support,
> no guarantees - read the code before you run it.

[Teleport](https://goteleport.com) session state and the active Kubernetes
cluster in the [Omarchy](https://omarchy.org) bar. Logged out it is a lone
icon that logs you in; logged in it shows the cluster you are pointed at, and
shouts when that cluster is production.

## Install

```bash
git clone https://github.com/WSeubring/omarchy-teleport.git
cd omarchy-teleport
./install.sh                 # links it as <user>.teleport and puts it on the bar
```

The script links the checkout into `~/.config/omarchy/plugins/`, so edits are
live. A bar widget's QML is instantiated once, though: after changing a `.qml`
file, run `omarchy restart shell` — a plugin reload alone keeps the old
instance (and its stale IPC handlers) running.

Needs `tsh`, `jq`, and `wl-copy` on `PATH`.

## States

| State | Means |
|---|---|
| **active** | Valid certificate; label is the active kube cluster |
| **expired** | Profile exists, certificate ran out |
| **off** | Not logged in — the widget dims to a single icon |

The label goes urgent with a `󰀦` when the active cluster looks like
production, and when the certificate is close to expiry. What counts as
non-production is a regex you own:

```bash
omarchy bar set <user>.teleport nonProductionPattern '(^|[-_])(dev|test|acc)([-_]|$)'
```

Anything the pattern does not match is treated as production, so a cluster you
forgot to name is loud rather than silent.

## Login

`tsh login` is interactive, so the widget delegates it. Two modes:

- **Silent (default).** Runs `bin/teleport-login`, which sources a
  `tsh-login.sh` from `$TSH_LOGIN_SH` (default
  `~/.config/bash/tsh-login.sh`) and calls `tsh-login`, or
  `tsh-kube-login <cluster>` when a cluster switch needs re-auth. That file is
  yours to write: anything that authenticates non-interactively works — a
  password manager CLI, a hardware token, an SSO helper. Mine pulls password
  and OTP out of 1Password and drives `tsh` through a pty.
- **Floating terminal.** For a login you want to watch or type into:

  ```bash
  omarchy bar set <user>.teleport useTerminal true
  omarchy bar set <user>.teleport loginCommand 'tsh login --proxy=example.com:443'
  ```

Expired certs are re-authenticated on a cluster switch rather than failing it.

## Interactions

- Bar icon: left = panel (or login when logged out), middle = copy the cluster
  name, right = refresh. Scroll = walk the cluster list.
- Panel row: left = switch to that cluster, middle = copy its name.
- Keys in the panel: `r` refresh, `l` login, `o` logout, `c` copy cluster,
  `y` copy proxy.

## Settings

| Key | Default | What |
|---|---|---|
| `refreshIntervalSec` | `30` | How often `tsh status` is polled |
| `nonProductionPattern` | dev/stag/test/… regex | Everything else is production |
| `useTerminal` | `false` | Log in in a floating terminal instead of silently |
| `loginCommand` | `source ~/.config/bash/tsh-login.sh && tsh-login` | Floating-terminal mode only |

## Layout

- `TeleportPanel.qml` — bar label, popup panel, IPC handlers.
- `TeleportService.qml` — process orchestration and parsed session state.
- `bin/teleport-status` — `tsh status` → JSON (state, cluster, user, proxy, expiry).
- `bin/teleport-clusters` — `tsh kube ls` → JSON array, with a plain-table fallback.
- `bin/teleport-login` — login/kube-login shim over your `tsh-login.sh`.

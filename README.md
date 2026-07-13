# Claudebox

Minimal Docker sandbox for running Claude Code with network isolation.

## What it does

- Blocks all access to private/local IP ranges (your LAN, Docker host,
  cloud metadata endpoints) at the network level
- Allows all public internet access (Anthropic API, package registries,
  GitHub, etc.)
- Runs Claude Code as an unprivileged user; sudo is available only to
  run the firewall setup script
- If the firewall fails to initialize, the container refuses to start

## Images

Three images are published to ghcr.io nightly:

- **`ghcr.io/jvasileff/claudebox:latest`** — the sandbox. Firewall,
  firewall-only sudo, SUID bits stripped, entrypoint that refuses to
  start without network isolation.
- **`ghcr.io/jvasileff/claudebox:base`** — everything except the sandbox
  setup: the same toolchains and AI CLIs, with the `coder` user (uid 1000)
  granted passwordless sudo, and no firewall or entrypoint. Useful as a
  general-purpose dev image or as a parent for custom images.
- **`ghcr.io/jvasileff/claudebox:sync-auth`** — a single-purpose helper
  behind the `cbox-sync-auth` shell function: validates Claude credentials
  received on stdin and installs them into a project volume. Runs with
  `--network=none`. Built on `base`, so it shares its layers.

The Dockerfile builds four stages:

| Stage | Adds | Published as |
|-------|------|--------------|
| `toolchain` | Debian + dev tools, Node (nvm), Java (sdkman), Python (uv), Go, Rust, nix | — |
| `base` | Claude Code, Codex, pi-mono; daily OS security patches; passwordless sudo | `:base` |
| `sync-auth` | credentials installer entrypoint, cleared `~/.claude` mount point | `:sync-auth` |
| `sandbox` | firewall, firewall-only sudoers, SUID strip, entrypoint | `:latest` |

CI resolves the current tool versions (Claude Code stable channel, npm
registry) and passes them as build args, so layers for unchanged tools
stay identical night to night and pulls download only what actually
changed. Local builds need no build args — the version ARGs default to
latest/stable.

## Usage

### Build from source

```bash
# sandbox image (default — the final stage)
docker build -f Dockerfile -t claudebox context

# base image only (no sandbox setup)
docker build -f Dockerfile --target base -t claudebox:base context
```

### Shell functions

Source `claudebox.sh` from your shell config to get the `cbox` and `codexbox`
functions:

```bash
source /path/to/claudebox/claudebox.sh
```

Then just `cd` into any project and run `cbox`. To run OpenAI Codex instead,
use `codexbox`.

Each tool gets its own isolated volume — `cbox` mounts `~/.claude` and
`codexbox` mounts `~/.codex`. Neither tool has access to the other's state.

The functions read `user.name` and `user.email` from your host git config and pass
them into the container as `GIT_AUTHOR_NAME`, `GIT_COMMITTER_NAME`, etc. Only name
and email are passed — no credentials, signing keys, or helpers. The host timezone
is also passed via `TZ`.

The volume name is derived from the project's basename and a hash of its real path
(symlinks resolved), e.g. `claude-myproject-a3f2b1c4`. Each project gets its own
isolated Claude auth and memory. To skip the per-project `/login`, copy existing
credentials in with `cbox-sync-auth` (below).

### Syncing Claude credentials

A brand-new project volume starts unauthenticated. From the project directory,
`cbox-sync-auth` copies existing Claude credentials into that project's volume
so no `/login` is needed:

```bash
cd ~/src/myproject
cbox-sync-auth
```

The default source is the host's own Claude Code login: the macOS keychain
(the "Claude Code-credentials" item), falling back to
`~/.claude/.credentials.json`. Credentials can also be supplied explicitly:

```bash
cbox-sync-auth --file work-creds.json   # a credentials JSON file
cbox-sync-auth -                        # stdin (paste, Enter, ctrl-d)
cbox-sync-auth --print                  # dump host credentials to stdout
```

`--print` and `-` compose for remote machines, where the keychain is not
available (it cannot be unlocked or approved from an ssh session):

```bash
cbox-sync-auth --print | ssh worker 'cd ~/proj && cbox-sync-auth -'
```

The credentials are piped over stdin into a short-lived `:sync-auth` container
running with `--network=none`; they never appear in command-line arguments,
environment variables, or storage shared between sandboxes. Sharing stays a
per-project, per-invocation decision — there is no always-on credential store.

Only `.credentials.json` is written. Claude Code rebuilds the rest of its
account state (`oauthAccount` in `.claude.json`) from the API at startup, and
refreshes an expired access token from the refresh token. Running
`cbox-sync-auth` before a project's first `cbox` is fine: the volume is created
containing only the credentials file, and `container-init.sh` seeds everything
else on the first real run.

### What the flags do

| Flag | Purpose |
|------|---------|
| `--cap-drop=ALL` | Remove all Linux capabilities |
| `--cap-add=NET_ADMIN,NET_RAW` | Required for iptables firewall setup, used once at startup via sudo |
| `--cap-add=SETUID,SETGID` | Required for sudo to set up the target process's UID/GID when running the firewall script |
| `--cap-add=AUDIT_WRITE` | Required for sudo to log to the kernel audit subsystem |
| `-v "$(pwd):..."` | Mount your project into the container |

## VS Code Dev Container

The sandbox can be used as a VS Code Dev Container. The same firewall and
privilege model applies.

Two configurations are available under `.devcontainer/`:

- **prebuilt** — uses the prebuilt image from `ghcr.io/jvasileff/claudebox:latest`. Fast to start.
- **source** — builds from the local `Dockerfile` and `context/` directory. Use this when developing the image itself.

Open this repository in VS Code and run **Dev Containers: Reopen in Container**.
VS Code will prompt you to choose a configuration.

### How it works

The container starts as the `coder` user. `postStartCommand` runs
`container-init.sh`, which calls `sudo init-firewall.sh` to set up the
firewall, selects the Java version, and sets up the memory sync symlink.
VS Code waits for `postStartCommand` to complete before opening a terminal
(`waitFor: postStartCommand`), so the firewall is always up before Claude
Code can be run.

Run Claude Code from the VS Code terminal:

```bash
claude --dangerously-skip-permissions
```

### Known limitation: VS Code IPC escape vector

**Dev Container mode weakens the sandbox's isolation guarantees.**

In standalone `docker run` mode, the only channel out of the container is the
network (which is firewalled). In Dev Container mode, VS Code injects Unix
sockets and environment variables into the container to enable remote
development features (`VSCODE_IPC_HOOK_CLI`, git credential helpers, extension
host sockets). A process inside the container that discovers these sockets can
communicate with the host VS Code process, potentially accessing host files or
credentials — bypassing the network firewall entirely.

The network firewall still works. The IPC risk is a separate, non-network
channel inherent to how VS Code Dev Containers work and cannot be mitigated
within devcontainer.json. For full isolation, use standalone `docker run` mode.

### Auth and memory between rebuilds

`/home/coder/.claude` is mounted as a named Docker volume keyed to
`${devcontainerId}` — a stable identifier VS Code derives from the workspace
folder and devcontainer config. The volume persists across **Rebuild Container**
operations, so Claude auth tokens and config survive rebuilds.

Note: the devcontainer volume is separate from the standalone `docker run`
volume (which uses a basename+path-hash name). Switching between modes requires
re-authenticating.

Project memory (`.claude/memory-sync/`) persists via the bind-mounted project
directory and the symlink is recreated automatically on each container start.

## GitHub Codespaces

The sandbox can run as a GitHub Codespace using the same devcontainer
configurations. However, **the iptables firewall is currently skipped
in Codespaces** because the standard ruleset blocks Codespaces' internal
communication, causing the container to hang. The container detects
Codespaces and skips the firewall to avoid this.

## Security model

**Threat model**: prevent Claude Code from accessing your local network,
Docker host, or other containers. Public internet access is allowed
because Claude needs its API, and blocking package registries makes
development impractical.

**Layers**:

1. **iptables firewall** (`container-init.sh`, via sudo): blocks RFC 1918 ranges,
   link-local, and CGNAT ranges. DNS is allowed only to the container's
   configured resolver. All public internet traffic is permitted.
   IPv6 is blocked, and the image configures `/etc/gai.conf` to prefer IPv4
   address selection so clients do not try unreachable AAAA records first.

   To allow one private destination through (e.g. a local Ollama server),
   set `FIREWALL_ALLOWED_DEST=hostname_or_ip:port` in the container's
   environment. The hostname is resolved at firewall setup and a single
   ACCEPT rule is added before the private-IP block. This is an explicit,
   user-opted hole in the firewall — anything reachable at that host:port
   is reachable from inside the sandbox.

2. **Privilege isolation** (build time + runtime): all SUID/SGID bits stripped
   except sudo; sudo is configured to allow only `/usr/local/libexec/init-firewall.sh`
   as root — no other privilege escalation path exists.

3. **Docker runtime flags**: all capabilities dropped except NET_ADMIN/NET_RAW,
   which are needed only for the firewall setup.

4. **Unprivileged by default**: the container runs as the `coder` user from the
   start (`USER coder` in the Dockerfile). No root process ever runs Claude Code.

If the firewall script fails, the container exits — there is no state
where Claude Code runs without network isolation. (Exception: in GitHub
Codespaces, where iptables rules would block internal communication, the
firewall is skipped — see [GitHub Codespaces](#github-codespaces) above.)

## Java version

To select a specific Java version for a project, add a `.java-version` file to
the project root containing just the major version number:

```
21
```

`container-init.sh` reads this file at startup, finds the best installed match,
and sets it as the default before Claude Code or any VS Code extension starts.
If the requested major version is not installed in the image, a warning is
printed and the image default is used.

## What this does NOT protect against

- Claude sending data through the Anthropic API (it always does — that's
  how it works)
- Prompt injection via content Claude fetches from the public internet
- Kernel exploits (containers share the host kernel; use a VM for stronger
  isolation)

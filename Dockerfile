FROM debian:trixie-slim AS sqlite3_builder

RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
        gcc make wget ca-certificates \
        libreadline-dev zlib1g-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ARG SQLITE_VERSION=3530000
ARG SQLITE_YEAR=2026

RUN wget https://www.sqlite.org/${SQLITE_YEAR}/sqlite-autoconf-${SQLITE_VERSION}.tar.gz && \
    tar xzf sqlite-autoconf-${SQLITE_VERSION}.tar.gz && \
    cd sqlite-autoconf-${SQLITE_VERSION} && \
    CFLAGS="-O2 \
            -DSQLITE_ENABLE_API_ARMOR \
            -DSQLITE_ENABLE_COLUMN_METADATA \
            -DSQLITE_ENABLE_FTS5 \
            -DSQLITE_ENABLE_GEOPOLY \
            -DSQLITE_ENABLE_MEMORY_MANAGEMENT \
            -DSQLITE_ENABLE_PREUPDATE_HOOK \
            -DSQLITE_ENABLE_SESSION \
            -DSQLITE_ENABLE_STAT4 \
            -DSQLITE_ENABLE_UNLOCK_NOTIFY \
            -DSQLITE_ENABLE_UPDATE_DELETE_LIMIT \
            -DSQLITE_USE_URI \
            -DSQLITE_SECURE_DELETE \
            -DSQLITE_LIKE_DOESNT_MATCH_BLOBS \
            -DSQLITE_SOUNDEX \
            -DSQLITE_MAX_VARIABLE_NUMBER=250000" \
    ./configure --prefix=/usr/local && \
    make -j$(nproc) && \
    make install

# ======================================================================
# Stage: toolchain
# OS packages and language toolchains. Rebuilt monthly (CACHE_BUSTER).
# ======================================================================
FROM debian:trixie-slim AS toolchain

ARG CACHE_BUSTER=2026-07

# -- Install runtime dependencies -------------------------------------
# sudo:               scoped privilege escalation for firewall setup only
# iptables:           firewall setup
# zip, unzip:         required by sdkman to unpack SDK archives
# dnsutils:           dig/nslookup for DNS debugging
# curl, ca-certificates, git, vim, tmux, lsof: dev tools
# gcc, zlib1g-dev:    required by GraalVM native-image
# gh, jq, fzf:        GitHub CLI, JSON processor, fuzzy finder
# less, procps:       pager and process tools (ps, top)
# gnupg2:             GPG for git signing and package verification
# libreadline8t64:    for sqlite3
# ripgrep bubblewrap socat: required for claude code sandbox
# build-essential:    make, g++, headers for building native deps
# git-delta:          nicer git diff output (delta)
# moreutils:          sponge, ts, and other pipe utilities
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
        sudo iptables iproute2 zip unzip curl ca-certificates \
        man git vim hx tmux lsof dnsutils bash-completion zsh \
        gcc zlib1g-dev gh jq fzf less procps gnupg2 age \
        openssh-client iputils-ping rsync file wget \
        ripgrep fd-find bat tree just bc gawk \
        build-essential git-delta moreutils \
        tzdata locales \
        libreadline8t64 \
        bubblewrap socat \
        nix shellcheck \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen \
    && locale-gen

# -- install sqlite3
COPY --from=sqlite3_builder /usr/local /usr/local
RUN ldconfig

# -- Create unprivileged user -----------------------------------------
RUN groupadd -g 1000 coder \
    && useradd -m -u 1000 -g coder -s /bin/bash coder

# -- Install nvm (Node version manager, for project use) --------------
RUN su - coder -c "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | PROFILE=/dev/null bash"

# -- Install Node.js LTS via nvm --------------------------------------
RUN su - coder -c ". ~/.nvm/nvm.sh && nvm install --lts && nvm alias default node"

# -- Install sdkman ---------------------------------------------------
RUN su - coder -c "curl -fsSL 'https://get.sdkman.io?rcupdate=false' | bash"

# -- Install SDKs (last java install becomes the default) -------------
RUN su - coder -c ". ~/.sdkman/bin/sdkman-init.sh && \
    sdk install java \$(sdk list java | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-amzn' | grep '^8\.' | sort -V | tail -1) && \
    sdk install java \$(sdk list java | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-amzn' | grep '^11\.' | sort -V | tail -1) && \
    sdk install java \$(sdk list java | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-graalce' | grep '^17\.' | sort -V | tail -1) && \
    sdk install java \$(sdk list java | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-graalce' | grep '^21\.' | sort -V | tail -1) && \
    sdk install java \$(sdk list java | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-graalce' | grep '^25\.' | sort -V | tail -1) && \
    sdk install gradle && \
    sdk install maven && \
    sdk install jextract && \
    sdk install jbang && \
    sdk install ant && \
    sdk flush"

# -- Install uv (Python package/version manager) ----------------------
RUN su - coder -c "curl -LsSf https://astral.sh/uv/install.sh | sh"

# -- Install Python via uv (pre-bake to avoid on-demand download) -----
RUN su - coder -c "uv python install"

# -- Python wrapper scripts (shim pip/pip3/python/python3 → uv) -------
RUN mkdir -p /home/coder/.local/bin
COPY --chown=coder:coder --chmod=755 shims/pip    /home/coder/.local/bin/pip
COPY --chown=coder:coder --chmod=755 shims/python /home/coder/.local/bin/python
COPY --chown=coder:coder --chmod=755 home/claudebox-memory-init /home/coder/.local/bin/claudebox-memory-init
RUN ln -s pip /home/coder/.local/bin/pip3 \
    && ln -s python /home/coder/.local/bin/python3

# -- Install Go -------------------------------------------------------
RUN GOVERSION=$(curl -fsSL https://go.dev/VERSION?m=text | head -1) && \
    GOARCH=$(dpkg --print-architecture) && \
    curl -fsSL "https://go.dev/dl/${GOVERSION}.linux-${GOARCH}.tar.gz" | tar -C /usr/local -xz

# -- Install Rust via rustup ------------------------------------------
RUN su - coder -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"

# configure nix for single-user use
RUN echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf
RUN echo "build-users-group =" >> /etc/nix/nix.conf
RUN chown -R coder:coder /nix

# -- Shell environment (nvm, sdkman) for all shell types --------------
# BASH_ENV is sourced by bash for every non-interactive script.
# .zshenv is sourced by zsh for every invocation (interactive or not).
# The guard variable in dot.shell_env prevents double-init.
COPY --chown=coder:coder home/dot.shell_env /home/coder/.shell_env
COPY --chown=coder:coder home/dot.zshenv /home/coder/.zshenv
RUN cat >> /home/coder/.bashrc <<'EOF'

if [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
fi

if [ -f "$HOME/.shell_env" ]; then
    . "$HOME/.shell_env"
fi
EOF

RUN cat >> /home/coder/.profile <<'EOF'

if [ -f "$HOME/.shell_env" ]; then
    . "$HOME/.shell_env"
fi
EOF

ENV BASH_ENV=/home/coder/.shell_env

# -- Convenience symlinks ---------------------------------------------
# Debian installs fd/bat as fdfind/batcat; symlink to canonical names so
# Claude Code (which knows them as fd and bat) can invoke them directly
RUN ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && ln -s /usr/bin/batcat /usr/local/bin/bat

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

ENV UV_SYSTEM_PYTHON=1

# ======================================================================
# Stage: base
# Adds AI coding tools and daily OS security patches. Published as
# ghcr.io/.../claudebox:base — fully usable, without the sandbox setup.
#
# Tool version ARGs: the defaults install the latest release, so a
# standalone `docker build` needs no arguments. CI passes exact resolved
# versions so that unchanged tools are cache hits (identical layers,
# nothing to re-pull nightly). Tools are installed least-frequently to
# most-frequently released, so frequent releases (claude, near-daily)
# don't invalidate the larger, rarely-changing layers above them.
# ======================================================================
FROM toolchain AS base

# -- Install https://github.com/badlogic/pi-mono ----------------------
ARG PI_VERSIONS="pi-ai pi-agent-core pi-coding-agent pi-mom pi-tui"
RUN su - coder -c ". ~/.nvm/nvm.sh && npm i -g $(printf '@mariozechner/%s ' $PI_VERSIONS)"

# -- Install OpenAI Codex CLI ------------------------------------------
ARG CODEX_VERSION=latest
RUN su - coder -c ". ~/.nvm/nvm.sh && npm i -g @openai/codex@${CODEX_VERSION}"

# -- Install Claude Code (native installer) ---------------------------
# The installer accepts stable|latest|X.Y.Z as its target argument.
ARG CLAUDE_VERSION=stable
RUN su - coder -c "curl -fsSL https://claude.ai/install.sh | bash -s -- ${CLAUDE_VERSION}"

ENV CLAUDE_CONFIG_DIR=/home/coder/.claude

# -- Default config templates -----------------------------------------
# Canonical defaults live in /etc/skel (inherited by the sandbox stage,
# which seeds them into $HOME at runtime because it mounts ~/.claude as a
# volume that would shadow anything baked there). Here in base nothing
# shadows $HOME, so bake our files straight in so the image is usable as
# is. Only our own files are copied (not all of /etc/skel) so the
# toolchain's customized ~/.bashrc and ~/.profile stay intact; cp -a
# preserves modes, including the statusline script's exec bit.
#
# ~/.claude is wiped before baking so its config comes solely from
# /etc/skel — the same clean slate the sandbox gets — rather than our
# config merged over the Claude installer's default artifacts. Safe
# because the claude launcher lives in ~/.local/bin, not ~/.claude.
COPY --chown=coder:coder             home/dot.gitconfig             /etc/skel/.gitconfig
COPY --chown=coder:coder             home/dot.claude.settings.json  /etc/skel/.claude/settings.json
COPY --chown=coder:coder --chmod=755 home/dot.claude.statusline.sh  /etc/skel/.claude/statusline.sh
RUN su - coder -c "cp -a /etc/skel/.gitconfig ~/.gitconfig \
    && rm -rf ~/.claude && mkdir -p ~/.claude \
    && cp -a /etc/skel/.claude/. ~/.claude/"

# -- Daily OS security patches ----------------------------------------
# Last among the daily steps: its nightly churn must not invalidate the
# tool layers above.
ARG AI_CACHE_BUSTER=2026-07-06
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# -- Convenience sudo (this image only) --------------------------------
# Passwordless sudo for coder, as is conventional for dev images. The
# sandbox stage deletes this drop-in and replaces /etc/sudoers with a
# firewall-only rule.
RUN echo "coder ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/coder \
    && chmod 0440 /etc/sudoers.d/coder \
    && visudo -c

USER coder
WORKDIR /workspaces/project

CMD ["/bin/bash"]

# ======================================================================
# Stage: sandbox
# Firewall, privilege hardening, and container init. Published as
# ghcr.io/.../claudebox:latest.
# ======================================================================
FROM base AS sandbox

USER root

# -- Volume mount points -----------------------------------------------
# Pre-create as coder:coder so Docker honours ownership for new volumes.
# Clear the baked ~/.claude (installer artifacts + baked defaults); only
# volume data belongs here, and container-init re-seeds the defaults from
# /etc/skel at runtime. Drop the baked ~/.gitconfig too, so the runtime
# seed — which skips it under DEVCONTAINER — governs whether the default
# git config is installed.
RUN rm -rf /home/coder/.claude /home/coder/.gitconfig \
    && mkdir -p /home/coder/.claude /home/coder/.codex \
    && chown coder:coder /home/coder/.claude /home/coder/.codex

# -- Firewall script (must be in place before sudoers references it) --
COPY libexec/init-firewall.sh /usr/local/libexec/init-firewall.sh
RUN chown root:root /usr/local/libexec/init-firewall.sh \
    && chmod 0755 /usr/local/libexec/init-firewall.sh

# -- Configure sudo: coder may only run init-firewall.sh as root ------
# The base image's convenience grant must not survive into the sandbox:
# delete the drop-in (rm without -f: fail the build if it ever moves)
# and replace /etc/sudoers wholesale (it has no @includedir, so nothing
# under /etc/sudoers.d is consulted even if a file slips through).
COPY etc/sudoers /etc/sudoers
RUN rm /etc/sudoers.d/coder \
    && chown root:root /etc/sudoers \
    && chmod 0440 /etc/sudoers

# -- Hardening (build time) -------------------------------------------
# Strip all SUID/SGID bits from every binary on the system, except sudo.
# sudo retains its SUID bit so coder can escalate only to run the
# firewall script (governed by the tightly-scoped sudoers config above).
# Must run after the daily apt upgrade in the base stage: upgraded
# packages reinstall their SUID bits.
RUN find / -xdev -perm /6000 -type f ! -path /usr/bin/sudo \
        -exec chmod a-s {} + 2>/dev/null; true

# -- Entrypoint and container init ------------------------------------
COPY libexec/container-init.sh /usr/local/libexec/container-init.sh
COPY libexec/entrypoint.sh /usr/local/libexec/entrypoint.sh
RUN chmod +x /usr/local/libexec/container-init.sh /usr/local/libexec/entrypoint.sh

# -- Prefer IPv4 address selection ------------------------------------
# The firewall explicitly blocks IPv6. Prefer IPv4 in getaddrinfo so
# tools do not try unreachable AAAA records first.
RUN printf 'precedence ::ffff:0:0/96  100\n' >> /etc/gai.conf

USER coder

ENTRYPOINT ["/usr/local/libexec/entrypoint.sh"]
CMD ["/bin/bash"]

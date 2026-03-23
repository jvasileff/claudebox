FROM debian:trixie-slim

ARG CACHE_BUSTER=2026-03-25

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
RUN apt-get update
RUN apt-get upgrade -y
RUN apt-get install -y --no-install-recommends \
        sudo iptables iproute2 zip unzip curl ca-certificates \
        git vim tmux lsof dnsutils bash-completion \
        gcc zlib1g-dev gh jq fzf less procps gnupg2 \
        openssh-client iputils-ping rsync file \
        ripgrep fd-find bat tree \
        tzdata locales \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen \
    && locale-gen

# -- Create unprivileged user -----------------------------------------
RUN groupadd -g 1000 coder \
    && useradd -m -u 1000 -g coder -s /bin/bash coder \
    && mkdir -p /home/coder/.claude \
    && chown coder:coder /home/coder/.claude

# -- Install nvm (Node version manager, for project use) --------------
RUN su - coder -c "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | PROFILE=/dev/null bash"

# -- Install Node.js LTS via nvm --------------------------------------
RUN su - coder -c ". ~/.nvm/nvm.sh && nvm install --lts && nvm alias default node"

# -- Install sdkman ---------------------------------------------------
RUN su - coder -c "curl -fsSL 'https://get.sdkman.io?rcupdate=false' | bash"

# -- Install SDKs (last java install becomes the default) -------------
RUN su - coder -c ". ~/.sdkman/bin/sdkman-init.sh && \
    sdk install java \$(sdk list java | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-amzn' | grep '^8\.' | sort -V | tail -1) && \
    sdk install java \$(sdk list java | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-graalce' | grep '^17\.' | sort -V | tail -1) && \
    sdk install java \$(sdk list java | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-graalce' | grep '^21\.' | sort -V | tail -1) && \
    sdk install java \$(sdk list java | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-graalce' | grep '^25\.' | sort -V | tail -1) && \
    sdk install gradle && \
    sdk install maven && \
    sdk install jbang && \
    sdk flush"

# -- Install uv (Python package/version manager) ----------------------
RUN su - coder -c "curl -LsSf https://astral.sh/uv/install.sh | sh"

# -- Install Python via uv (pre-bake to avoid on-demand download) -----
RUN su - coder -c "uv python install"

# -- Python wrapper scripts (shim pip/pip3/python/python3 → uv) -------
RUN mkdir -p /home/coder/.local/bin
COPY --chown=coder:coder --chmod=755 shims/pip    /home/coder/.local/bin/pip
COPY --chown=coder:coder --chmod=755 shims/python /home/coder/.local/bin/python
RUN ln -s pip /home/coder/.local/bin/pip3 \
    && ln -s python /home/coder/.local/bin/python3

# -- Install Claude Code (native installer) ---------------------------
RUN su - coder -c "curl -fsSL https://claude.ai/install.sh | bash"

# -- Firewall script (must be in place before sudoers references it) --
COPY libexec/init-firewall.sh /usr/local/libexec/init-firewall.sh
RUN chown root:root /usr/local/libexec/init-firewall.sh \
    && chmod 0755 /usr/local/libexec/init-firewall.sh

# -- Configure sudo: coder may only run init-firewall.sh as root ------
COPY etc/sudoers /etc/sudoers
RUN chown root:root /etc/sudoers \
    && chmod 0440 /etc/sudoers

# -- Hardening (build time) -------------------------------------------
# Strip all SUID/SGID bits from every binary on the system, except sudo.
# sudo retains its SUID bit so coder can escalate only to run the
# firewall script (governed by the tightly-scoped sudoers config above).
RUN find / -xdev -perm /6000 -type f ! -path /usr/bin/sudo \
        -exec chmod a-s {} + 2>/dev/null; true

# -- Shell environment (nvm, sdkman) for all shell types --------------
# BASH_ENV is sourced by bash for every non-interactive script.
# .zshenv is sourced by zsh for every invocation (interactive or not).
# The guard variable in dot.shell_env prevents double-init.
COPY home/dot.gitconfig /etc/skel/.gitconfig
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

# -- Entrypoint and container init ------------------------------------
COPY libexec/container-init.sh /usr/local/libexec/container-init.sh
COPY libexec/entrypoint.sh /usr/local/libexec/entrypoint.sh
RUN chmod +x /usr/local/libexec/container-init.sh /usr/local/libexec/entrypoint.sh

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

ENV CLAUDE_CONFIG_DIR=/home/coder/.claude
ENV UV_SYSTEM_PYTHON=1

USER coder
WORKDIR /workspaces/project

ENTRYPOINT ["/usr/local/libexec/entrypoint.sh"]
CMD ["claude", "--dangerously-skip-permissions"]

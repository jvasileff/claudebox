FROM debian:trixie-slim

ARG CACHE_BUSTER=2026-03-26h

# -- Install runtime dependencies -------------------------------------
# sudo:               scoped privilege escalation for firewall setup only
# iptables:           firewall setup
RUN echo "=== [Dockerfile] Installing packages ===" \
    && apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y --no-install-recommends \
        sudo iptables iproute2 zip unzip curl ca-certificates \
        git vim tmux lsof dnsutils bash-completion \
        gh jq fzf less procps gnupg2 \
        openssh-client iputils-ping rsync file \
        ripgrep fd-find bat tree \
        tzdata locales \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen \
    && locale-gen \
    && echo "=== [Dockerfile] Packages installed ==="

# -- Create unprivileged user -----------------------------------------
RUN echo "=== [Dockerfile] Creating user coder ===" \
    && groupadd -g 1000 coder \
    && useradd -m -u 1000 -g coder -s /bin/bash coder \
    && mkdir -p /home/coder/.claude \
    && chown coder:coder /home/coder/.claude \
    && echo "=== [Dockerfile] User coder created ===" \
    && id coder \
    && grep coder /etc/passwd

## -- Heavy installs commented out for Codespaces boot debugging ------
## Uncomment these once the container boots successfully.
#
# # -- Install nvm (Node version manager, for project use) --------------
# RUN su - coder -c "curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | PROFILE=/dev/null bash"
#
# # -- Install Node.js LTS via nvm --------------------------------------
# RUN su - coder -c ". ~/.nvm/nvm.sh && nvm install --lts && nvm alias default node"
#
# # -- Install sdkman ---------------------------------------------------
# RUN su - coder -c "curl -fsSL 'https://get.sdkman.io?rcupdate=false' | bash"
#
# # -- Install SDKs (last java install becomes the default) -------------
# RUN su - coder -c ". ~/.sdkman/bin/sdkman-init.sh && \
#     sdk install java \$(sdk list java | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-amzn' | grep '^8\.' | sort -V | tail -1) && \
#     sdk install java \$(sdk list java | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-graalce' | grep '^17\.' | sort -V | tail -1) && \
#     sdk install java \$(sdk list java | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-graalce' | grep '^21\.' | sort -V | tail -1) && \
#     sdk install java \$(sdk list java | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-graalce' | grep '^25\.' | sort -V | tail -1) && \
#     sdk install gradle && \
#     sdk install maven && \
#     sdk install jbang && \
#     sdk flush"
#
# # -- Install uv (Python package/version manager) ----------------------
# RUN su - coder -c "curl -LsSf https://astral.sh/uv/install.sh | sh"
#
# # -- Install Python via uv (pre-bake to avoid on-demand download) -----
# RUN su - coder -c "uv python install"
#
# # -- Python wrapper scripts (shim pip/pip3/python/python3 → uv) -------
# RUN mkdir -p /home/coder/.local/bin
# COPY --chown=coder:coder --chmod=755 shims/pip    /home/coder/.local/bin/pip
# COPY --chown=coder:coder --chmod=755 shims/python /home/coder/.local/bin/python
# COPY --chown=coder:coder --chmod=755 home/claudebox-memory-init /home/coder/.local/bin/claudebox-memory-init
# RUN ln -s pip /home/coder/.local/bin/pip3 \
#     && ln -s python /home/coder/.local/bin/python3
#
# # -- Install Claude Code (native installer) ---------------------------
# RUN su - coder -c "curl -fsSL https://claude.ai/install.sh | bash"

# -- Minimal local/bin setup (full shims commented out above) ----------
RUN mkdir -p /home/coder/.local/bin \
    && chown -R coder:coder /home/coder/.local

# -- Firewall script (must be in place before sudoers references it) --
COPY libexec/init-firewall.sh /usr/local/libexec/init-firewall.sh
RUN chown root:root /usr/local/libexec/init-firewall.sh \
    && chmod 0755 /usr/local/libexec/init-firewall.sh

# -- Configure sudo: coder may only run init-firewall.sh as root ------
COPY etc/sudoers /etc/sudoers
RUN chown root:root /etc/sudoers \
    && chmod 0440 /etc/sudoers

# -- Hardening (build time) — DISABLED for Codespaces debugging -------
# Strip all SUID/SGID bits from every binary on the system, except sudo.
# sudo retains its SUID bit so coder can escalate only to run the
# firewall script (governed by the tightly-scoped sudoers config above).
# RUN find / -xdev -perm /6000 -type f ! -path /usr/bin/sudo \
#         -exec chmod a-s {} + 2>/dev/null; true

# -- Shell environment ------------------------------------------------
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
RUN ln -s /usr/bin/fdfind /usr/local/bin/fd \
    && ln -s /usr/bin/batcat /usr/local/bin/bat

# -- Entrypoint and container init ------------------------------------
COPY libexec/container-init.sh /usr/local/libexec/container-init.sh
COPY libexec/entrypoint.sh /usr/local/libexec/entrypoint.sh
RUN chmod +x /usr/local/libexec/container-init.sh /usr/local/libexec/entrypoint.sh

# -- Final verification -----------------------------------------------
RUN echo "=== [Dockerfile] Final verification ===" \
    && id coder \
    && grep coder /etc/passwd \
    && ls -la /usr/local/libexec/ \
    && echo "=== [Dockerfile] Build complete ==="

ENV LANG=en_US.UTF-8
ENV LC_ALL=en_US.UTF-8

ENV CLAUDE_CONFIG_DIR=/home/coder/.claude

USER coder
WORKDIR /workspaces/project

ENTRYPOINT ["/usr/local/libexec/entrypoint.sh"]
CMD ["bash"]

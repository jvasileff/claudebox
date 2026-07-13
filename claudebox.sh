# claudebox.sh — shell functions for running Claude Code and Codex in a sandbox
# Source this file from your shell config, e.g.:
#   source /path/to/claudebox/claudebox.sh

# Container engine: prefer podman, fall back to docker.
_claudebox_engine() {
    if command -v podman >/dev/null 2>&1; then
        echo podman
    else
        echo docker
    fi
}

# Per-project volume name: prefix + project basename + hash of its real path.
_claudebox_vol() {
    local _prefix=$1 _real
    _real=$(cd -P "$(pwd)" && pwd)
    echo "${_prefix}-$(basename "$_real")-$(echo -n "$_real" | shasum | cut -c1-8)"
}

_claudebox_run() {
    local _prefix=$1 _state_dir=$2; shift 2
    local _real _vol _git_name _git_email _tz _engine
    local -a _env_args=()
    _engine=$(_claudebox_engine)
    _real=$(cd -P "$(pwd)" && pwd)
    _vol=$(_claudebox_vol "$_prefix")
    _git_name=$(git config --global user.name 2>/dev/null || true)
    _git_email=$(git config --global user.email 2>/dev/null || true)
    _tz=$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')
    [[ -n "$_git_name" ]]  && _env_args+=(-e "GIT_AUTHOR_NAME=$_git_name"  -e "GIT_COMMITTER_NAME=$_git_name")
    [[ -n "$_git_email" ]] && _env_args+=(-e "GIT_AUTHOR_EMAIL=$_git_email" -e "GIT_COMMITTER_EMAIL=$_git_email")
    [[ -n "$_tz" ]]        && _env_args+=(-e "TZ=$_tz")
    echo "Pulling latest image..." >&2
    "$_engine" pull --quiet ghcr.io/jvasileff/claudebox:latest 2>/dev/null || true
    "$_engine" run -it --rm \
        --name "$_vol" \
        --cap-drop=ALL \
        --cap-add=NET_ADMIN \
        --cap-add=NET_RAW \
        --cap-add=SETUID \
        --cap-add=SETGID \
        --cap-add=AUDIT_WRITE \
        "${_env_args[@]}" \
        -v "$_vol:/home/coder/$_state_dir" \
        -v "$_real:/workspaces/project" \
        ghcr.io/jvasileff/claudebox:latest "$@"
}

cbox() {
    if [[ $# -eq 0 ]]; then
        set -- bash -c 'echo "Updating..." && claude update && exec claude --dangerously-skip-permissions'
    fi
    _claudebox_run claudebox .claude "$@"
}

# Copy Claude credentials into the current project's volume so a fresh
# project needs no /login. Default source: the macOS keychain, falling
# back to ~/.claude/.credentials.json. `--file PATH` or `-` (stdin;
# paste, Enter, ctrl-d) supply credentials explicitly, and --print dumps
# the host credentials to stdout — the two compose for remote machines,
# where the keychain is unavailable:
#   cbox-sync-auth --print | ssh worker 'cd ~/proj && cbox-sync-auth -'
cbox-sync-auth() {
    local _engine _creds="" _print="" _src=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            --print) _print=1; shift ;;
            --file)
                [[ $# -ge 2 ]] || { echo "cbox-sync-auth: --file requires a path" >&2; return 2; }
                _src=$2; shift 2 ;;
            -) _src=-; shift ;;
            *) echo "usage: cbox-sync-auth [--print] [--file PATH | -]" >&2; return 2 ;;
        esac
    done
    if [[ $_src == - ]]; then
        [[ -t 0 ]] && echo "Paste credentials JSON, then press Enter and ctrl-d:" >&2
        _creds=$(cat)
    elif [[ -n $_src ]]; then
        _creds=$(cat "$_src") || return 1
    else
        command -v security >/dev/null 2>&1 \
            && _creds=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
        [[ -z $_creds && -r "$HOME/.claude/.credentials.json" ]] \
            && _creds=$(cat "$HOME/.claude/.credentials.json")
    fi
    if [[ -z $_creds ]]; then
        echo "cbox-sync-auth: no credentials found (no keychain item or ~/.claude/.credentials.json)" >&2
        return 1
    fi
    if [[ -n $_print ]]; then
        printf '%s\n' "$_creds"
        return 0
    fi
    _engine=$(_claudebox_engine)
    "$_engine" pull --quiet ghcr.io/jvasileff/claudebox:sync-auth 2>/dev/null || true
    printf '%s' "$_creds" | "$_engine" run -i --rm --network=none \
        -v "$(_claudebox_vol claudebox):/home/coder/.claude" \
        ghcr.io/jvasileff/claudebox:sync-auth
}

codexbox() {
    if [[ $# -eq 0 ]]; then
        set -- bash -c 'echo "Updating..." && npm update -g @openai/codex && exec codex --yolo'
    fi
    _claudebox_run codexbox .codex "$@"
}

# Run the unsandboxed base image. Options before `--` go to the container
# engine (e.g. volume mounts); anything after `--` is the command run in
# the container:
#   cboxbase -v ~/data:/data -- bash -lc 'echo hi'
cboxbase() {
    local _engine; _engine=$(_claudebox_engine)
    local -a opts=()
    while [[ $# -gt 0 && $1 != -- ]]; do opts+=("$1"); shift; done
    [[ $1 == -- ]] && shift
    echo "Pulling latest image..." >&2
    "$_engine" pull --quiet ghcr.io/jvasileff/claudebox:base 2>/dev/null || true
    "$_engine" run --rm -it "${opts[@]}" ghcr.io/jvasileff/claudebox:base "$@"
}

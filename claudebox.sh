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

_claudebox_run() {
    local _prefix=$1 _state_dir=$2; shift 2
    local _real _vol _git_name _git_email _tz _engine
    local -a _env_args=()
    _engine=$(_claudebox_engine)
    _real=$(cd -P "$(pwd)" && pwd)
    _vol="${_prefix}-$(basename "$_real")-$(echo -n "$_real" | shasum | cut -c1-8)"
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

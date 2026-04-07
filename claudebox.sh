# claudebox.sh — shell functions for running Claude Code and Codex in a sandbox
# Source this file from your shell config, e.g.:
#   source /path/to/claudebox/claudebox.sh

_claudebox_run() {
    local _prefix=$1 _state_dir=$2; shift 2
    local _real _vol _git_name _git_email _tz
    local -a _env_args=()
    _real=$(cd -P "$(pwd)" && pwd)
    _vol="${_prefix}-$(basename "$_real")-$(echo -n "$_real" | shasum | cut -c1-8)"
    _git_name=$(git config --global user.name 2>/dev/null || true)
    _git_email=$(git config --global user.email 2>/dev/null || true)
    _tz=$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')
    [[ -n "$_git_name" ]]  && _env_args+=(-e "GIT_AUTHOR_NAME=$_git_name"  -e "GIT_COMMITTER_NAME=$_git_name")
    [[ -n "$_git_email" ]] && _env_args+=(-e "GIT_AUTHOR_EMAIL=$_git_email" -e "GIT_COMMITTER_EMAIL=$_git_email")
    [[ -n "$_tz" ]]        && _env_args+=(-e "TZ=$_tz")
    echo "Pulling latest image..." >&2
    docker pull --quiet ghcr.io/jvasileff/claudebox:latest 2>/dev/null || true
    docker run -it --rm \
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

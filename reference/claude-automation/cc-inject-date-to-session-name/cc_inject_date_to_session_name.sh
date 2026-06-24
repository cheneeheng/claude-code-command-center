#!/usr/bin/env bash
# Claude wrapper — auto-injects --name <dir>-<timestamp> if not already supplied
# Install: place in a directory on your PATH *before* the real claude binary
#          e.g. $HOME/.local/bin/claude  (chmod +x, add that dir to $PATH)

has_name=0
for arg in "$@"; do
    if [[ "$arg" == "-n" || "$arg" == "--name" ]]; then
        has_name=1
        break
    fi
done

if [[ $has_name -eq 0 ]]; then
    dir_name=$(basename "$PWD" | tr -cs 'a-zA-Z0-9_-' '-' | sed 's/-$//')
    stamp=$(date '+%y%m%d%H%M')
    auto_name="${dir_name}-${stamp}"
    set -- --name "$auto_name" "$@"
fi

# Resolve the real claude binary (skip this script itself)
real_claude=$(
    IFS=:
    for dir in $PATH; do
        candidate="$dir/claude"
        if [[ -x "$candidate" && "$candidate" != "$(realpath "$0")" ]]; then
            echo "$candidate"
            break
        fi
    done
)

if [[ -z "$real_claude" ]]; then
    echo "claude binary not found on PATH" >&2
    exit 1
fi

exec "$real_claude" "$@"

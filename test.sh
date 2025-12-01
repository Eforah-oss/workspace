#!/usr/bin/env sh
set -eu

in_unix_shells() (
    for x in bash dash ksh ksh93 mksh zsh; do
        if [ -z "$$(command -v "$$x" 2>/dev/null)" ]; then
            printf "Shell %s was not found and could not be tested\n" \
                "$$x" >&2
        else
            "$$x" "$@"
        fi
    done
)


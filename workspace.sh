#!/usr/bin/env sh
set -eu

die() { if [ "$#" -gt 0 ]; then printf "%s\n" "$*" >&2; fi; exit 1; }
abspath() ( cd "`dirname "$1"`"; d="`pwd -P`"; echo "${d%/}/`basename "$1"`"; )
fnmatch() { case "$2" in $1) return 0 ;; *) return 1 ;; esac ; }

escape() {
    case "$1" in
    *[!A-Za-z0-9:_/.+@-]*) echo "$1" | sed "s/'/'\\''/g;s/^/'/;s/$/'/";;
    *) echo "$1";;
    esac
}

workspace_info() {
    <"$XDG_CONFIG_HOME/workspace/config.mk" TARGET="${1-}" awk '
        function output(target, clonestring) {
            if (ENVIRON["TARGET"] && ENVIRON["TARGET"] != target) return;
            location_index = index(clonestring, " ")
            if (location_index) {
                url = substr(clonestring, 0, location_index - 1)
                location = substr(clonestring, location_index + 1)
            } else {
                url = clonestring
                location = clonestring ""
                sub(/.git\/?$/, "", location)
                sub(/\/$/, "", location)
                sub(/[^/]*:/, "", location)
                sub(/.*\//, "", location)
            }
            printf("%s %s %s\n", target, url, location)
        }
        /^[A-Za-z0-9._]*:/ {
            target = substr($0, 0, index($0, ":") - 1)
            clone_index = index($0, "; git clone ")
            if (clone_index) {
                output(target, substr($0, clone_index + 12))
            }
        }
        /^\tgit clone / {
            output(target, substr($0, index($0, "git clone ") + 10))
        }
    '
}

workspace() {
    XDG_CONFIG_HOME="${XDG_CONFIG_HOME-$HOME/.config}"
    XDG_DATA_HOME="${XDG_DATA_HOME-$HOME/.local/share}"
    WORKSPACE_CONFIG="${WORKSPACE_CONFIG-$XDG_CONFIG_HOME/workspace/config.mk}"
    WORKSPACE_REPO_HOME="${WORKSPACE_REPO_HOME:-$XDG_DATA_HOME/workspace}"
    if ! [ -e "$WORKSPACE_CONFIG" ]; then
        mkdir -p "$(dirname "$WORKSPACE_CONFIG")"
        printf ".POSIX:\n.SUFFIXES:\n" >"$WORKSPACE_CONFIG"
    fi
    cd "$WORKSPACE_REPO_HOME"
    case "$1" in
    add)
        shift
        set -- "${2-$(echo "$1" \
            | sed 's_.git/\{0,1\}$__;s_/$__;s_[^/]*:__;s_.*/__')}" "$1" "${2-}"
        if fnmatch '*[!A-Za-z0-9._]*' "$1"; then
            die "ERROR: Invalid characters in target ($1)"
        fi
        if grep -q "^$1:" "$WORKSPACE_CONFIG"; then
            die "ERROR: Already added"
        fi
        printf "\n%s:; git clone %s%s\n" "$1" "$(escape "$2")" "${3:+ $3}" \
            >>"$WORKSPACE_CONFIG"
        ;;
    sync)
        shift
        workspace_info | while read -r TARGET URL LOCATION; do
            LOCATION="$(abspath "$(eval "echo $LOCATION")")"
            [ -d "$LOCATION" ] || make -sf "$WORKSPACE_CONFIG" "$TARGET"
        done
        ;;
    foreach)
        shift
        workspace_info | while read -r TARGET URL LOCATION; do
            sh -c "cd $LOCATION; $1"
        done
        ;;
    print-zsh-setup)
        shift
        echo "${1-workon}"'() {
            [ $# = 1 ] \
                || set -- "$(workspace workspace-info | cut -d\  -f1 | fzy)"
            [ -n "$1" ] || return 1
            set -- "$1" "" "$(workspace dir-of "$1")"
            [ -d "$3" ] || (
                cd "$WORKSPACE_REPO_HOME"
                make -sf "$WORKSPACE_CONFIG" "$1"
            )
            cd "$3"
        }'
        ;;
    workspace-info)
        shift
        workspace_info "$@"
        ;;
    dir-of)
        shift
        workspace_info "$1" | {
            read -r TARGET URL LOCATION
            abspath "$(eval "echo $LOCATION")"
        }
        ;;
    esac
}

workspace "$@"

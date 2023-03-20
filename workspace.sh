#!/usr/bin/env sh
set -eu

die() { if [ "$#" -gt 0 ]; then printf "%s\n" "$*" >&2; fi; exit 1; }
fnmatch() { case "$2" in $1) return 0 ;; *) return 1 ;; esac ; }
in_dir() ( cd "$1"; shift; "$@"; )

print_sh_setup() {
echo \
"${1-workon}"'() {
    [ $# = 1 ] || set -- "$(workspace workspace-info | cut -d\  -f1 | fzy)"
    [ -n "$1" ] || return 1
    set -- "$1" "" "$(workspace dir-of "$1")"
    [ -n "$3" ] || { echo "ERROR: Unknown workspace: $1" >&2; return 1; }
    [ -d "$3" ] || workspace sync "$1" || return $?
    cd "$3"
    eval "$(workspace script-of "$1" cd)"
}
'
}

print_bash_setup() {
print_sh_setup "$@"
echo '
_'"${1-workon}"'() {
    [ "$3" = "'"${1-workon}"'" ] || return
    local workspaces workspace
    COMPREPLY=()
    <<<"$(workspace workspace-info)" readarray -t workspaces
    for workspace in "${workspaces[@]%% *}"; do
        ! [[ "$workspace" =~ ^$2 ]] || COMPREPLY+=("$workspace")
    done
}
complete -F _'"${1-workon}"' '"${1-workon}"'
'
}

print_zsh_setup() {
print_sh_setup "$@"
echo '
_'"${1-workon}"'() {
    _arguments "1:workspace name:(${(j: :)${(@fq-)$(\
        workspace workspace-info | cut -d\  -f1)}})"
}

compdef _'"${1-workon}"' '"${1-workon}"'
'
}

escape() {
    case "$1" in
    *[!A-Za-z0-9:_/.+@-]*) echo "$1" | sed "s/'/'\\''/g;s/^/'/;s/$/'/";;
    *) echo "$1";;
    esac
}

workspace_info() {
    [ -e "$WORKSPACE_CONFIG" ] || die "ERROR: No config, add a workspace first"
    WORKSPACE="${1-}" awk '
        /^##([^#].*|)$/ {
            sub(/^## ?/, "");
            name = $0
            path = name
            if (length(name) == 0) next;
            if (match(name, /^[^ ]* /)) {
                name = substr($0, 1, RLENGTH - 1)
                path = substr($0, RLENGTH + 1)
                while (match(path, /\$(\{[A-Za-z0-9_]*\}|[A-Za-z0-9_]*)/)) {
                    var = substr(path, RSTART + 1, RLENGTH - 1);
                    if (substr(var, 1, 1) == "{")
                        var = substr(var, 2, length(var) - 2)
                    path = substr(path, 1, RSTART - 1) ENVIRON[var] \
                        substr(path, RSTART + RLENGTH)
                }
            }
            if (ENVIRON["WORKSPACE"] && ENVIRON["WORKSPACE"] != name) next;
            if (substr(path, 1, 1) != "/")
                path = ENVIRON["WORKSPACE_REPO_HOME"] "/" path
            printf("%s %s\n", name, path);
        }
    ' "$WORKSPACE_CONFIG"
}

workspace_sync_one() { #1: workspace 2: workspace_path
    if ! [ -d "$2" ]; then
        clean() {
            WORKSPACE_ERROR=$?
            rm -rf "$2"
            echo "ERROR: Could not initialize $1" >&2
            trap - EXIT INT TERM
            exit $WORKSPACE_ERROR
        }
        trap clean EXIT INT TERM
        mkdir -p "$2"
        get_script "$1" clone | in_dir "$2" sh -e /dev/stdin || clean
        trap - EXIT INT TERM
    fi
}

get_script() {
    [ -e "$WORKSPACE_CONFIG" ] || die "ERROR: No config, add a workspace first"
    WORKSPACE="$1" ACTION="$2" awk '
        BEGIN {
            name = ENVIRON["WORKSPACE"]
            action = ENVIRON["ACTION"]
            shell = ENVIRON["SHELL"]
        }
        /^##([^#].*|)$/ {
            name = $0
            sub(/^## ?/, "", name);
            if (match(name, /^([^\\]|\\.|[^ ])* /)) {
                name = substr(name, 1, RLENGTH - 1)
            } else if (length(name) == 0) {
                name = ENVIRON["WORKSPACE"]
            }
            action = "clone"
            shell = ENVIRON["SHELL"]
        }
        /^###([^#].*|)$/ {
            action = $0
            sub(/^### ?/, "", action);
        }
        /^####([^#].*|)$/ {
            line = $0
            sub(/^#### ?/, "", line);
            if (line == "") {
                shell = ENVIRON["SHELL"]
            } else if (!match(line, /^[A-Za-z0-9_.]*$/)) {
                print "WARNING: " FILENAME ":" FNR ": Invalid shell: " line \
                    >"/dev/stderr"
                shell = "/" #Can not match a shell
            } else {
                shell = line
            }
        }
        /^[^#][^#]/ {
            if (ENVIRON["WORKSPACE"] != name) next;
            if (ENVIRON["ACTION"] != action) next;
            if (!match(ENVIRON["SHELL"], shell "$")) next;
            print $0
        }
    ' "$WORKSPACE_CONFIG"
}

workspace() {
    set -a
    XDG_CONFIG_HOME="${XDG_CONFIG_HOME-$HOME/.config}"
    XDG_DATA_HOME="${XDG_DATA_HOME-$HOME/.local/share}"
    WORKSPACE_CONFIG="${WORKSPACE_CONFIG-$XDG_CONFIG_HOME/workspace/config}"
    WORKSPACE_REPO_HOME="${WORKSPACE_REPO_HOME:-$XDG_DATA_HOME/workspace}"
    set +a
    mkdir -p "$WORKSPACE_REPO_HOME"
    case "$1" in
    add)
        shift
        set -- "${2-$(echo "$1" \
            | sed 's_.git/\{0,1\}$__;s_/$__;s_[^/]*:__;s_.*/__')}" "$1"
        if fnmatch '*[!-A-Za-z0-9._]*' "$1"; then
            die "ERROR: Invalid characters in workspace name: $1"
        fi
        if grep -qE "^## ?$1(| .*)\$" "$WORKSPACE_CONFIG" 2>/dev/null; then
            die "ERROR: Already added"
        fi
        mkdir -p "$(dirname "$WORKSPACE_CONFIG")"
        printf "## %s\ngit clone %s .\n" "$1" "$(escape "$2")" \
            >>"$WORKSPACE_CONFIG"
        ;;
    sync)
        shift
        workspace_info "$@" | while read -r WORKSPACE WORKSPACE_PATH; do
            workspace_sync_one "$WORKSPACE" "$WORKSPACE_PATH"
        done
        ;;
    "in")
        shift
        WORKSPACE="$1"; shift
        workspace_info "$WORKSPACE" | while read -r WORKSPACE WORKSPACE_PATH;do
            workspace_sync_one "$WORKSPACE" "$WORKSPACE_PATH"
            export WORKSPACE WORKSPACE_PATH
            in_dir "$WORKSPACE_PATH" "$@"
        done
        ;;
    print-bash-setup)
        shift
        print_bash_setup "$@"
        ;;
    print-zsh-setup)
        shift
        print_zsh_setup "$@"
        ;;
    workspace-info)
        shift
        workspace_info "$@"
        ;;
    dir-of)
        shift
        workspace_info "$1" | {
            read -r WORKSPACE WORKSPACE_PATH
            echo "$WORKSPACE_PATH"
        }
        ;;
    script-of)
        shift
        get_script "$@"
        ;;
    esac
}

workspace "$@"

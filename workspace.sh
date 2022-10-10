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
    [ -d "$3" ] || workspace sync "$1"
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
    local workspaces target
    COMPREPLY=()
    <<<"$(workspace workspace-info)" readarray -t workspaces
    for target in "${workspaces[@]%% *}"; do
        ! [[ "$target" =~ ^$2 ]] || COMPREPLY+=("$target")
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
    <"$WORKSPACE_CONFIG" TARGET="${1-}" awk '
        /^##([^#].*|)$/ {
            sub(/^## ?/, "");
            name = $0
            path = name
            if (match(name, /^[^ ]* /)) {
                name = substr($0, 1, RLENGTH - 1)
                path = substr($0, RLENGTH + 1)
                while (match(path, /\$({[A-Za-z0-9_]*}|[A-Za-z0-9_]*)/)) {
                    var = substr(path, RSTART + 1, RLENGTH - 1);
                    if (substr(var, 1, 1) == "{")
                        var = substr(var, 2, length(var) - 2)
                    path = substr(path, 1, RSTART - 1) ENVIRON[var] \
                        substr(path, RSTART + RLENGTH)
                }
            }
            if (ENVIRON["TARGET"] && ENVIRON["TARGET"] != name) next;
            if (substr(path, 1, 1) != "/")
                path = ENVIRON["WORKSPACE_REPO_HOME"] "/" path
            printf("%s %s\n", name, path);
        }
    '
}

get_script() {
    TARGET="$1" ACTION="$2" awk '
        /^##([^#].*|)$/ {
            name = $0
            sub(/^## ?/, "", name);
            if (match(name, /^([^\\]|\\.|[^ ])* /)) {
                name = substr($0, 1, RLENGTH - 1)
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
            if (ENVIRON["TARGET"] != name) next;
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
    if ! [ -e "$WORKSPACE_CONFIG" ]; then
        mkdir -p "$(dirname "$WORKSPACE_CONFIG")"
        touch "$WORKSPACE_CONFIG"
    fi
    mkdir -p "$WORKSPACE_REPO_HOME"
    case "$1" in
    add)
        shift
        set -- "${2-$(echo "$1" \
            | sed 's_.git/\{0,1\}$__;s_/$__;s_[^/]*:__;s_.*/__')}" "$1" "${2-}"
        if fnmatch '*[!A-Za-z0-9._]*' "$1"; then
            die "ERROR: Invalid characters in target: $1"
        fi
        if grep -qE "^## ?$1(| .*)\$" "$WORKSPACE_CONFIG"; then
            die "ERROR: Already added"
        fi
        printf "## %s\ngit clone %s%s\n" "$1" "$(escape "$2")" "${3:+ $3}" \
            >>"$WORKSPACE_CONFIG"
        ;;
    sync)
        shift
        workspace_info "$@" | while read -r TARGET LOCATION; do
            if ! [ -d "$LOCATION" ]; then
                mkdir -p "$(dirname "$LOCATION")"
                get_script "$TARGET" clone \
                    | in_dir "$WORKSPACE_REPO_HOME" sh /dev/stdin
            fi
        done
        ;;
    foreach)
        shift
        workspace_info | while read -r TARGET LOCATION; do
            in_dir "$LOCATION" sh -c "$1"
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
            read -r TARGET LOCATION
            echo "$LOCATION"
        }
        ;;
    script-of)
        shift
        get_script "$@"
        ;;
    esac
}

workspace "$@"

#!/usr/bin/env sh
# shellcheck disable=SC2016,SC2254
set -eu

die() { if [ "$#" -gt 0 ]; then printf "%s\n" "$*" >&2; fi && exit 1; }
fnmatch() { case "$2" in $1) return 0 ;; *) return 1 ;; esac }
in_dir() (cd "$1" && shift && "$@")
sponge() { set -- "$1" "$(mktemp)" && cat >"$2" && cp "$2" "$1" && rm "$2"; }
quote() {
    while [ "$#" -gt 0 ]; do
        printf "'" && printf %s "$1" | sed "s/'/'\\\\''/g" && printf "' " \
            || return 1
        shift
    done
}

print_sh_setup() {
    printf %s \
        "${1-workon}"'() {
            [ $# = 1 ] || set -- "$(
                workspace info | cut -d\  -f1 \
                    | "$( (command -v fzf || command -v fzy) 2>/dev/null)"
            )"
            [ -n "$1" ] || return 1
            set -- "$1" "" "$(workspace info "$1")"
            set -- "$1" "" "${3#* }"
            [ -n "$3" ] \
                || { echo "ERROR: Unknown workspace: $1" >&2 && return 1; }
            [ -d "$3" ] || workspace sync "$1" || return $?
            cd "$3"
            eval "$(workspace script-of "$1" cd)"
        }

        eval "$(
            workspace info | awk -F "^[^ ]* " "
                \$2 == ENVIRON[\"PWD\"] {
                    w = substr(\$0, 0, length(\$0) - length(\$2) - 1);
                    gsub(\"[^A-Za-z0-9:_/.+@-]\", \"\\\\\\\\&\", w);
                    while ( \
                        ((\"workspace script-of \" w \" cd\") | getline x) \
                        > 0 \
                    ) {
                        print x
                    }
                }
            "
        )"
    '
}

print_bash_setup() {
    print_sh_setup "$@"
    printf %s '
        _'"${1-workon}"'() {
            [ "$3" = "'"${1-workon}"'" ] || return
            local workspaces workspace
            COMPREPLY=()
            <<<"$(workspace info)" readarray -t workspaces
            for workspace in "${workspaces[@]%% *}"; do
                ! [[ "$workspace" =~ ^$2 ]] || COMPREPLY+=("$workspace")
            done
        }
        complete -F _'"${1-workon}"' '"${1-workon}"'
    '
}

print_fish_setup() {
    printf %s '
        function '"${1-workon}"' --argument-names name
            if test -z "$name"
                set -l picker (command -v fzf; or command -v fzy)
                set name (workspace info | cut -d\  -f1 | $picker)
            end
            test -n "$name"; or return 1
            set -l dir (workspace info "$name" | string replace -r "[^ ]* " "")
            if test -z "$dir"
                echo "ERROR: Unknown workspace: $name" >&2
                return 1
            end
            test -d "$dir"; or workspace sync "$name"; or return $status
            cd "$dir"; or return $status
            eval (workspace script-of "$name" cd | string collect)
        end

        workspace info | while read -l name dir
            test "$dir" = "$PWD"; or continue
            eval (workspace script-of "$name" cd | string collect)
            break
        end

        function __'"${1-workon}"'_complete_workspaces
            workspace info | cut -d\  -f1
        end
        complete -c '"${1-workon}"' -f -n __fish_is_first_arg \
            -a '\''(__'"${1-workon}"'_complete_workspaces)'\''
        complete -c '"${1-workon}"' -f -n '\''not __fish_is_first_arg'\''
    '
}

print_zsh_setup() {
    print_sh_setup "$@"
    printf %s '
        _'"${1-workon}"'() {
            _arguments "1:workspace name:(${(j: :)${(@fq-)$(\
                workspace info | cut -d\  -f1
            )}})"
        }

        ! command -v compdef >/dev/null 2>&1 \
            || compdef _'"${1-workon}"' '"${1-workon}"'
    '
}

escape() {
    case "$1" in
    *[!A-Za-z0-9:_/.+@-]*) printf %s "$1" | sed "s/'/'\\''/g;s/^/'/;s/$/'/" ;;
    *) printf %s "$1" ;;
    esac
}

workspace_info() {
    [ -e "$WORKSPACE_CONFIG" ] || die "ERROR: No config, add a workspace first"
    awk -vselector="$1" '
        /^##[^#].*$/ {
            sub(/^## ?/, "");
            name = $0
            path = name
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
            if (substr(path, 1, 1) != "/")
                path = ENVIRON["WORKSPACE_REPO_HOME"] "/" path
            if (match(selector, /^--name=/) && name == substr(selector, 8))
                printf("%s %s\n", name, path);
            else if (selector == "--all")
                printf("%s %s\n", name, path);
        }
    ' "$WORKSPACE_CONFIG"
}

# Create and initialize the workspace if the workspace path does not exist.
workspace_sync_one() { #1: workspace 2: workspace_path
    if ! [ -d "$2" ]; then
        eval '
            clean() {
                WORKSPACE_ERROR=$?
                rm -rf '\'"$(escape "$2")"\''
                echo '\''ERROR: Could not initialize '"$(escape "$1")"\'' >&2
                trap - EXIT INT TERM
                exit "$(($WORKSPACE_ERROR > 0 ? $WORKSPACE_ERROR : 1))"
            }
        '
        trap clean EXIT INT TERM
        mkdir -p "$2"
        WORKSPACE="$1" ACTION="clone" get_script \
            | in_dir "$2" sh -e /dev/stdin >&2 || clean
        trap - EXIT INT TERM
    fi
}

get_script() {
    [ -e "$WORKSPACE_CONFIG" ] || die "ERROR: No config, add a workspace first"
    awk '
        BEGIN {
            name = ""
            action = ""
            shell = ""
        }
        /^(##[^#].*|##)$/ {
            name = $0
            sub(/^## ?/, "", name)
            if (match(name, /[^\\] /)) {
                name = substr(name, 1, RSTART)
            } else if (length(name) == 0) {
                name = ""
            }
            action = "clone"
            shell = ""
        }
        /^(###[^#].*|###)$/ {
            action = $0
            sub(/^### ?/, "", action)
        }
        /^(####[^#].*|####)$/ {
            shell = $0
            sub(/^#### ?/, "", shell);
            if (!match(shell, /^[A-Za-z0-9_.]*$/)) {
                print "WARNING: " FILENAME ":" FNR ": Invalid shell: " shell \
                    >"/dev/stderr"
                shell = "/" #Can not match a shell
            }
        }
        1 {
            if (ENVIRON["REMOVE_WORKSPACE"]) {
                if (ENVIRON["REMOVE_WORKSPACE"] != name)
                    print $0
            } else if ( \
                (ENVIRON["WORKSPACE"] == name || "" == name) \
                && (ENVIRON["ACTION"] == action || "" == action) \
                && (match(ENVIRON["SHELL"], shell "$") || "" == shell) \
            )
                print $0
        }
    ' "$WORKSPACE_CONFIG"
}

workspace_help() {
    >&2 printf %s\\n \
        "Usage: workspace <command> [arguments...]" \
        "" \
        "Manage, initialize and quickly open workspaces." \
        "" \
        "Commands:" \
        "  add <git-url> [name]       Add new workspace (like \`git clone\`)" \
        "  del <selector>             Delete workspace" \
        "  sync [selector]            Initialize given or all workspaces" \
        "  in <selector> [exe...]     Run executable with args in workspaces" \
        "  info [selector]            Info for workspaces: \"name path\\n\"" \
        "  script-of <name> <action>  Get script for workspace and action" \
        "  print-bash-setup [alias]   Print bash setup" \
        "  print-fish-setup [alias]   Print fish setup" \
        "  print-zsh-setup [alias]    Print zsh setup" \
        "" \
        "Selectors are a name of a workspace or '--all' for all workspaces" \
        "The default alias if none is given is 'workon'."
}

workspace() {
    XDG_CONFIG_HOME="${XDG_CONFIG_HOME-$HOME/.config}"
    XDG_DATA_HOME="${XDG_DATA_HOME-$HOME/.local/share}"
    WORKSPACE_CONFIG="${WORKSPACE_CONFIG-$XDG_CONFIG_HOME/workspace/config}"
    WORKSPACE_REPO_HOME="${WORKSPACE_REPO_HOME:-$XDG_DATA_HOME/workspace}"
    export XDG_CONFIG_HOME XDG_DATA_HOME WORKSPACE_CONFIG WORKSPACE_REPO_HOME
    mkdir -p "$WORKSPACE_REPO_HOME"
    case "${1-}" in
    del | sync | "in" | info)
        [ "$#" -lt 2 ] || case "$2" in
        --all | --name=*) ;;
        --name)
            [ $# -ge 3 ] || die "Usage: --name <name>"
            eval "shift 3; set -- $1 --name=$(quote "$3") \"\$@\""
            ;;
        --*) die "Invalid workspace selection option: $2" ;;
        "") eval "shift 2; set -- $1 --all \"\$@\"" ;;
        *) eval "shift 2; set -- $1 --name=$(quote "$2") \"\$@\"" ;;
        esac
        ;;
    esac
    case "${1:-}" in
    add)
        shift
        [ "$#" -gt 0 ] || die "Usage: workspace add <git-url> [name]"
        set -- "${2-$(printf %s\\n "$1" \
            | sed 's_.git/\{0,1\}$__;s_/$__;s_[^/]*:__;s_.*/__')}" "$1"
        if fnmatch '*[!-A-Za-z0-9._]*' "$1"; then
            die "ERROR: Invalid characters in workspace name: $1"
        fi
        if
            [ -e "$WORKSPACE_CONFIG" ] \
                && [ -n "$(workspace_info --name="$1" 2>/dev/null)" ]
        then
            die "ERROR: Already added"
        fi
        mkdir -p "$(dirname "$WORKSPACE_CONFIG")"
        printf "%s %s\ngit clone %s .\n" \
            "$([ -e "$WORKSPACE_CONFIG" ] && printf '\n##' || printf '##')" \
            "$1" "$(escape "$2")" \
            >>"$WORKSPACE_CONFIG"
        ;;
    del)
        shift
        [ "$#" -eq 1 ] || die "Usage: workspace del <selector>"
        workspace_info "$1" | {
            shift
            while read -r WORKSPACE WORKSPACE_PATH; do
                rm -rf "$WORKSPACE_PATH"
                REMOVE_WORKSPACE="$WORKSPACE" get_script \
                    | sponge "$WORKSPACE_CONFIG"
            done
        }
        ;;
    sync)
        shift
        workspace_info "${1:---all}" | {
            shift
            while read -r WORKSPACE WORKSPACE_PATH; do
                workspace_sync_one "$WORKSPACE" "$WORKSPACE_PATH"
            done
        }
        ;;
    "in")
        shift
        [ "$#" -ge 2 ] || die "Usage: workspace in <selector> <exe...>"
        exec 3<&0
        workspace_info "$1" | {
            shift
            while read -r WORKSPACE WORKSPACE_PATH; do
                workspace_sync_one "$WORKSPACE" "$WORKSPACE_PATH"
                export WORKSPACE WORKSPACE_PATH
                <&3 in_dir "$WORKSPACE_PATH" "$@"
            done
        }
        exec 3<&-
        ;;
    print-bash-setup)
        shift
        print_bash_setup "$@"
        ;;
    print-fish-setup)
        shift
        print_fish_setup "$@"
        ;;
    print-zsh-setup)
        shift
        print_zsh_setup "$@"
        ;;
    info)
        shift
        [ "$#" -ge 1 ] || set -- --all
        workspace_info "$@"
        ;;
    script-of)
        shift
        [ "$#" -eq 2 ] || die "Usage: workspace script-of [name] [action]"
        WORKSPACE="$1" ACTION="$2" get_script
        ;;
    *)
        workspace_help
        if [ "${1-}" = help ]; then exit; else return 1; fi
        ;;
    esac
}

workspace "$@"

`workspace` - Git repository organiser
======================================

  > Of course you should make a wrapper for git clone.

— No one

Using `workspace` you can configure the repositories you use. This means
that they are automatically cloned when you want to use them. It also
integrates with your shell, so you can easily cd to them.

`workspace` is heavily inspired by
[fw](https://github.com/brocode/fw). The difference is that this is
written in simple (YMMV) POSIX shell script, so should run unmodified
on your MacBook, WSL or router, if that floats your goat.

### Installation
If you put your binaries in `~/.local/bin`:

    PREFIX="$HOME/.local" make install

If you can't figure this out and want to use this tool anyway, message me.

Afterwards, add something like this to your `.zshrc`:

    eval "$(workspace print-zsh-setup workon)"

The word `workon` is the default value and can be omitted, but is the
name for the shell function that you can use to switch to a workspace.

### Usage

First, add a repository.

    workspace add https://github.com/milhnl/pass.git pass_clone

This adds the repository to the workspace configuration file, which can
be found at `$XDG_CONFIG_HOME/workspace/config.mk`. `pass_clone` is the
name of your workspace, and will default to the name of repository if
you omit this.

Then you can switch to it using `workon pass_clone`. If you run only
`workon`, it wil present you a fuzzy finder to select your repository. You
will currently need [fzy](https://github.com/jhawthorn/fzy) for this.

### Configuration

`workspace` has a default location for your repositories:

  - `$WORKSPACE_REPO_HOME` which defaults to
  - `$XDG_DATA_HOME/workspace` which defaults to
  - `~/.local/share/workspace`

You can change this default by changing the environment variable, or
customize the path on a per-repository basis as seen below.

#### Configuration file

The configuration file can be found at:

  - `$WORKSPACE_CONFIG` which defaults to
  - `$XDG_CONFIG_HOME/workspace/config.mk` which defaults to
  - `~/.config/workspace/config.mk`

The `.mk` extension does indeed mean that this is a Makefile. This is
not the most natural configuration format, so there are a few gotchas
when editing this file by hand. It does have the advantage of making
your configuration extremely customizable. This might get a bit technical
and is not necessary for normal usage.

#### Workspace definition in config.mk
`workspace` sees all `make` targets that run `git clone` as a
workspace. The heuristic for detecting this is currently a bit limited,
but does support some variations and their combinations:

    workspace:; git clone https://milhnl@github.com/milhnl/workspace.git
    
    better_pass:
    	git clone git@github.com:milhnl/pass better_pass
    
    website:
    	git clone https://git.example.com/website /srv/http/default
    	echo 'You can put initialization commands here'
    
    passwords:
    	git clone git@mysite.com:passwords ${PASSWORD_STORE_DIR}

As you can probably infer from these examples, the `make` target name is
the workspace name, the string `git clone` is detected by `workspace`,
and the target path is either taken from the last part of the URL (as git
does) or specified after (also like git). This last bit is the tricky
part, if you want to use environment variables, use the syntax that is
supported by both `make` and `sh`: `${VAR}`.

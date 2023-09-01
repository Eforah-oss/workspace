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

#### Linux/WSL/macOS/... (Unix)

If you put your binaries in `~/.local/bin`:

    PREFIX="$HOME/.local" make install

If you can't figure this out and want to use this tool anyway, message me.

Afterwards, add something like this to your `.bashrc`:

    eval "$(workspace print-bash-setup workon)"

Or, if you use Zsh, your `.zshrc`:

    eval "$(workspace print-zsh-setup workon)"

The word `workon` is the default value and can be omitted, but is the
name for the shell function that you can use to switch to a workspace.

#### Windows/PowerShell

Run `./Install.ps1`, which will put the Workspace module where PowerShell
expects it. PowerShell support is very new and does not work like the
Unix version yet.

To set an alias for `Enter-Workspace` (which works like `workon` below),
add something like

    Set-Alias workon Enter-Workspace

to your PowerShell profile.

### Usage

First, add a repository.

    workspace add https://github.com/milhnl/pass.git pass_clone

This adds the repository to the workspace configuration file, which can
be found at `$XDG_CONFIG_HOME/workspace/config`. `pass_clone` is the
name of your workspace, and will default to the name of repository if
you omit this.

Then you can switch to it using `workon pass_clone`. If you run
only `workon`, it wil present you a fuzzy finder to select your
repository. You will currently need [fzf](https://github.com/junegunn/fzf)
or [fzy](https://github.com/jhawthorn/fzy) for this.

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
  - `$XDG_CONFIG_HOME/workspace/config` which defaults to
  - `~/.config/workspace/config`

`workspace` uses a custom line-based configuration file format, which
has lines starting with two pound signs (`#`) labeling your workspaces,
which then contain a script to initialise them. Running the command
`workspace add https://github.com/myusername/project` would add this to
your configuration file:

    ## project
    git clone https://github.com/myusername/project .

Straightforward right? After every heading with two pounds, you can
have a script that'll clone your repository. This script is run in the
target directory, so don't forget to include the final `.` when running
`git`.

#### Other destination folders

If you want the destination folder to be different than the default
(which is the same as the workspace name), you'll need to specify it
after the name of the workspace. Environment variables are interpreted
using simple `$VARIABLE` or `${VARIABLE}` syntax.

    ## dotfiles $HOME/.config
    rm -r *
    git clone https://github.com/myusername/dotfiles .

As you can see, `workspace` only really reads the lines with pounds to
know which workspaces you have and where they are. The rest is just
scripting lines that'll be run in your current shell.

#### Initialization scripts

First: let's have an example:

    ## saas_monorepo
    git clone https://smith@git.mycompany.com/saas_monorepo .
    npm --prefix react-app install
    #### powershell
    choco install -y php
    #### sh
    apt install php
    ####
    git config user.email smith@mycompany.com

Now we see more commands, and also 4-pound directives with the name of
a shell. These tell `workspace` that the following commands may only be
run in the specified shell. To reset this, use a line with only `####`,
also like above.

You can use if you use for example both powershell and the WSL on
Windows, or sometimes switch between `fish` and `bash`. For the
use case above (installing system dependencies) it is recommended to use
[pmmmux](https://github.com/Eforah-oss/pmmux).

This segment is run when the repository is first cloned. If you want
some commands to run when you open a workspace, see the next paragraphs.

#### Integration with `workon`
Suppose you use `node`. Versions are a pain, and you don't just use
`node`, but also `nvm`. You want to run `nvm use` after opening your
workspace. This is possible by adding a `cd` script like this:

    ## node_project
    git clone https://example.com/node_project.git .
    ### cd
    nvm use

This script is run in your shell via the shell integration every time
you run `workon` (or whatever you named it, see "Installation"). You can
also use this section to set environment variables or start your database.
The shell directives explained above work here as well.
